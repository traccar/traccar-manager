import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:traccar_manager/main.dart';
import 'package:traccar_manager/token_store.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  static final urlKey = 'url';
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

  Future<void> _initWebView() async {
    _preferences = await SharedPreferences.getInstance();

    String url = _preferences.getString(urlKey) ?? 'https://demo.traccar.org'; //'http://localhost:3000';
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
            final serverUrl = _preferences.getString(urlKey);
            if (serverUrl != null && !request.url.startsWith(serverUrl)) {
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
      final url = _preferences.getString(urlKey);
      final eventId = message.data['eventId'];
      if (url != null && eventId != null) {
        _controller.loadRequest(Uri.parse('$url?eventId=$eventId'));
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
        await _preferences.setString(urlKey, url);
        _controller.loadRequest(Uri.parse(url));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const Center(child: CircularProgressIndicator());
    }
    final navigator = Navigator.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _controller.canGoBack().then((canGoBack) {
          if (canGoBack) {
            _controller.goBack();
          } else if (mounted) {
            navigator.pop();
          }
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
