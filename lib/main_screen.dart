import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:traccar_manager/main.dart';
import 'package:traccar_manager/token_store.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  static const _urlKey = 'url';

  bool _initialized = false;
  late final SharedPreferences _preferences;
  late final WebViewController _controller;
  final _loginTokenStore = TokenStore();
  final _messaging = FirebaseMessaging.instance;

  @override
  void initState() {
    super.initState();
    _initWebView();
    _initNotifications();
  }

  String _getUrl() {
    return _preferences.getString(_urlKey) ?? 'https://demo.traccar.org'; //'http://localhost:3000';
  }

  Future<void> _initWebView() async {
    _preferences = await SharedPreferences.getInstance();

    String url = _getUrl();
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      final eventId = initialMessage.data['eventId'];
      if (eventId != null) {
        url = '$url?eventId=$eventId';
      }
    }

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('appInterface', onMessageReceived: _handleWebMessage)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (NavigationRequest request) async {
            if (!request.url.startsWith(_getUrl())) {
              if (await canLaunchUrl(Uri.parse(request.url))) {
                await launchUrl(Uri.parse(request.url));
              }
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(url));

    final platformController = _controller.platform;
    if (platformController is AndroidWebViewController) {
      platformController.setGeolocationPermissionsPromptCallbacks(
        onShowPrompt: (request) async {
          final status = await Permission.location.request();
          return GeolocationPermissionsResponse(allow: status.isGranted, retain: true);
        },
      );
    }

    setState(() {
      _initialized = true;
    });
  }

  Future<void> _initNotifications() async {
    await _messaging.requestPermission();
    _messaging.onTokenRefresh.listen((newToken) {
      _controller.runJavaScript("updateNotificationToken && updateNotificationToken('$newToken')");
    });
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final notification = message.notification;
      if (notification != null) {
        scaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(content: Text(notification.body ?? 'Unknown')),
        );
      }
    });
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      final eventId = message.data['eventId'];
      if (eventId != null) {
        _controller.loadRequest(Uri.parse('${_getUrl()}?eventId=$eventId'));
      }
    });
  }

  void _handleWebMessage(JavaScriptMessage interfaceMessage) async {
    final List<String> parts = interfaceMessage.message.split('|');
    switch (parts[0]) {
      case 'login':
        if (parts.length > 1) {
          await _loginTokenStore.save(parts[1]);
        }
        final notificationToken = await _messaging.getToken();
        if (notificationToken != null) {
          _controller.runJavaScript("updateNotificationToken && updateNotificationToken('$notificationToken')");
        }
      case 'authentication':
        final loginToken = await _loginTokenStore.read();
        if (loginToken != null) {
          _controller.runJavaScript("handleLoginToken && handleLoginToken('$loginToken')");
        }
      case 'logout':
        await _loginTokenStore.delete();
      case 'server':
        final url = parts[1];
        await _preferences.setString(_urlKey, url);
        _controller.loadRequest(Uri.parse(url));
    }
  }

  bool _isRootOrLogin(String baseUrl, String? currentUrl) {
    if (currentUrl == null) return false;
    final baseUri = Uri.parse(baseUrl);
    final currentUri = Uri.parse(currentUrl);
    if (baseUri.origin != currentUri.origin) return false;
    return currentUri.path == '/' || currentUri.path == '/login';
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _controller.currentUrl().then((url) {
          _controller.canGoBack().then((canGoBack) {
            if (canGoBack && !_isRootOrLogin(_getUrl(), url)) {
              _controller.goBack();
            } else {
              SystemNavigator.pop();
            }
          });
        });
      },
      child: Scaffold(
        body: SafeArea(
          child: WebViewWidget(controller: _controller),
        ),
      ),
    );
  }
}
