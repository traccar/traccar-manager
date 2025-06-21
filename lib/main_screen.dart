import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:traccar_manager/error_screen.dart';
import 'package:traccar_manager/main.dart';
import 'package:traccar_manager/token_store.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_android/shared_preferences_android.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  static const _urlKey = 'url';

  bool _initialized = false;
  late final SharedPreferencesWithCache _preferences;

  late InAppWebViewController _controller;
  final _controllerReady = Completer<void>();

  late final AppLinks _appLinks;
  StreamSubscription<Uri>? _appLinksSubscription;
  final _loginTokenStore = TokenStore();
  final _messaging = FirebaseMessaging.instance;
  String? _loadingError;

  @override
  void initState() {
    super.initState();
    _initWebView();
    _initNotifications();
    _initAppLinks();
  }

  void _initAppLinks() {
    _appLinks = AppLinks();
    _appLinksSubscription = _appLinks.uriLinkStream.listen((uri) async {
      await _controllerReady.future;
      if (uri.scheme == 'org.traccar.manager') {
        final baseUri = Uri.parse(_getUrl());
        final updatedQueryParameters = Map<String, String>.from(uri.queryParameters)
          ..['redirect_uri'] = uri.toString().split('?').first;
        final updatedUri = uri.replace(
          scheme: baseUri.scheme,
          host: baseUri.host,
          port: baseUri.port,
          queryParameters: updatedQueryParameters,
        );
        _controller.loadUrl(urlRequest: URLRequest(url: WebUri.uri(updatedUri)));
      } else {
        _controller.loadUrl(urlRequest: URLRequest(url: WebUri.uri(uri)));
      }
    });
  }

  Future<void> _launchAuthorizeRequest(Uri uri) async {
    try {
      final originalRedirect = Uri.parse(uri.queryParameters['redirect_uri']!);
      final updatedRedirect = Uri(
        scheme: 'org.traccar.manager',
        path: originalRedirect.path,
        queryParameters: originalRedirect.queryParameters.isEmpty ? null : originalRedirect.queryParameters,
      );
      final updatedQueryParameters = Map<String, String>.from(uri.queryParameters)
        ..['redirect_uri'] = updatedRedirect.toString();
      await launchUrl(
        uri.replace(queryParameters: updatedQueryParameters),
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      developer.log('Failed to launch authorize request', error: e);
    }
  }

  @override
  void dispose() {
    _appLinksSubscription?.cancel();
    super.dispose();
  }

  String _getUrl() => _preferences.getString(_urlKey) ?? 'https://demo.traccar.org';

  bool _isDownloadable(WebUri uri) {
    final lastSegment = uri.pathSegments.isNotEmpty ? uri.pathSegments.last.toLowerCase() : '';
    return ['xlsx', 'kml', 'csv', 'gpx'].contains(lastSegment);
  }

  Future<void> _downloadFile(WebUri uri) async {
    try {
      final token = await _loginTokenStore.read(false);
      if (token == null) return;
      final response = await http.get(uri, headers: {'Authorization': 'Bearer $token'});
      if (response.statusCode == 200) {
        final directory = Platform.isAndroid
            ? await getExternalStorageDirectory()
            : await getApplicationDocumentsDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final extension = uri.pathSegments.last;
        final file = File('${directory!.path}/$timestamp.$extension');
        await file.writeAsBytes(response.bodyBytes);
        await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
      } else {
        developer.log('Failed file download request');
      }
    } catch (e) {
      developer.log('Failed to download file', error: e);
    }
  }

  Future<void> _initWebView() async {
    _preferences = await SharedPreferencesWithCache.create(
      sharedPreferencesOptions: Platform.isAndroid
          ? SharedPreferencesAsyncAndroidOptions(
              backend: SharedPreferencesAndroidBackendLibrary.SharedPreferences)
          : const SharedPreferencesOptions(),
      cacheOptions: const SharedPreferencesWithCacheOptions(allowList: {_urlKey}),
    );
    setState(() => _initialized = true);
  }

  Future<void> _initNotifications() async {
    await _messaging.requestPermission();
    await _controllerReady.future;

    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      final eventId = initialMessage.data['eventId'];
      if (eventId != null) {
        _controller.loadUrl(urlRequest: URLRequest(url: WebUri('${_getUrl()}?eventId=$eventId')));
      }
    }

    _messaging.onTokenRefresh.listen((newToken) async {
      _controller.evaluateJavascript(source: "updateNotificationToken?.('$newToken')");
    });

    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      final notification = message.notification;
      if (notification != null) {
        _controller.evaluateJavascript(source: "handleNativeNotification?.(${jsonEncode(message.toMap())})");
        scaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(content: Text(notification.body ?? 'Unknown')),
        );
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) async {
      final eventId = message.data['eventId'];
      if (eventId != null) {
        _controller.loadUrl(urlRequest: URLRequest(url: WebUri('${_getUrl()}?eventId=$eventId')));
      }
    });
  }

  void _registerJavascriptHandlers() {
    _controller.addJavaScriptHandler(
      handlerName: 'appInterface',
      callback: (args) async {
        if (args.isEmpty) return;
        final List<String> parts = (args[0] as String).split('|');
        switch (parts[0]) {
          case 'login':
            if (parts.length > 1) {
              await _loginTokenStore.save(parts[1]);
            }
            final notificationToken = await _messaging.getToken();
            if (notificationToken != null) {
              _controller.evaluateJavascript(source: "updateNotificationToken?.('$notificationToken')");
            }
            break;
          case 'authentication':
            final loginToken = await _loginTokenStore.read(true);
            if (loginToken != null) {
              _controller.evaluateJavascript(source: "handleLoginToken?.('$loginToken')");
            }
            break;
          case 'logout':
            await _loginTokenStore.delete();
            break;
          case 'server':
            final url = parts[1];
            await _loginTokenStore.delete();
            await _preferences.setString(_urlKey, url);
            _controller.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
            break;
        }
      },
    );
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
    if (_loadingError != null) {
      return ErrorScreen(
        error: _loadingError!,
        url: _getUrl(),
        onUrlSubmitted: (url) async {
          await _loginTokenStore.delete();
          await _preferences.setString(_urlKey, url);
          // TODO load url
          setState(() => _loadingError = null);
        },
      );
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _controllerReady.future;
        final url = await _controller.getUrl();
        final canGoBack = await _controller.canGoBack();
        if (canGoBack && !_isRootOrLogin(_getUrl(), url?.toString())) {
          _controller.goBack();
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: SafeArea(
          maintainBottomViewPadding: true,
          child: InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(_getUrl())),

            initialSettings: InAppWebViewSettings(
              useShouldOverrideUrlLoading: true,
              transparentBackground: true,
            ),

            onWebViewCreated: (controller) {
              _controller = controller;
              _controllerReady.complete();
              _registerJavascriptHandlers();
            },

            shouldOverrideUrlLoading: (controller, navigationAction) async {
              final uri = navigationAction.request.url;
              if (uri == null) {
                return NavigationActionPolicy.ALLOW;
              }

              if (['response_type', 'client_id', 'redirect_uri', 'scope']
                  .every(uri.queryParameters.containsKey)) {
                _launchAuthorizeRequest(uri);
                return NavigationActionPolicy.CANCEL;
              }

              if (!uri.toString().startsWith(_getUrl())) {
                try {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                } catch (e) {
                  developer.log('Failed to launch url', error: e);
                }
                return NavigationActionPolicy.CANCEL;
              }

              if (_isDownloadable(uri)) {
                _downloadFile(uri);
                return NavigationActionPolicy.CANCEL;
              }

              return NavigationActionPolicy.ALLOW;
            },

            onLoadStart: (controller, url) {
              setState(() => _loadingError = null);
            },
            
            onReceivedError: (controller, request, error) {
              setState(() => _loadingError = error.description);
            },

            onGeolocationPermissionsShowPrompt: (controller, origin) async {
              final status = await Permission.location.request();
              return GeolocationPermissionShowPromptResponse(
                origin: origin,
                allow: status.isGranted,
                retain: true,
              );
            },

            onDownloadStartRequest: (controller, request) {
              if (_isDownloadable(request.url)) {
                _downloadFile(request.url);
              }
            },
          ),
        ),
      ),
    );
  }
}
