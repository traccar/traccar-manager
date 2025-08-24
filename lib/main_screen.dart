import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:traccar_manager/error_screen.dart';
import 'package:traccar_manager/main.dart';
import 'package:traccar_manager/token_store.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_android/shared_preferences_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  static const _urlKey = 'url';

  final _initialized = Completer<void>();
  final _authenticated = Completer<void>();

  late final SharedPreferencesWithCache _preferences;
  late final WebViewController _controller;
  late final AppLinks _appLinks;
  StreamSubscription<Uri>? _appLinksSubscription;
  final _loginTokenStore = TokenStore();
  final _messaging = FirebaseMessaging.instance;
  String? _loadingError;

  @override
  void initState() {
    super.initState();
    _initWebView();
    _initAppLinks();
    _initNotifications();
  }

  Future<void> _initAppLinks() async {
    await _initialized.future;
    _appLinks = AppLinks();
    _appLinksSubscription = _appLinks.uriLinkStream.listen((uri) {
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
        _controller.loadRequest(updatedUri);
      } else {
        _controller.loadRequest(uri);
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
      await launchUrl(uri.replace(queryParameters: updatedQueryParameters), mode: LaunchMode.externalApplication);
    } catch (e) {
      developer.log('Failed to launch authorize request', error: e);
    }
  }

  @override
  void dispose() {
    _appLinksSubscription?.cancel();
    super.dispose();
  }

  String _getUrl() {
    return _preferences.getString(_urlKey) ?? 'https://demo.traccar.org';
  }

  bool _isDownloadable(Uri uri) {
    final lastSegment = uri.pathSegments.isNotEmpty ? uri.pathSegments.last.toLowerCase() : '';
    return ['xlsx', 'kml', 'csv', 'gpx'].contains(lastSegment);
  }

  Future<void> _downloadFile(Uri uri) async {
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
        ? SharedPreferencesAsyncAndroidOptions(backend: SharedPreferencesAndroidBackendLibrary.SharedPreferences)
        : SharedPreferencesOptions(),
      cacheOptions: SharedPreferencesWithCacheOptions(allowList: {'url'}),
    );

    String url = _getUrl();
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      final eventId = initialMessage.data['eventId'];
      if (eventId != null) {
        url = '$url/event/$eventId';
      }
    }

    final brightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
    final backgroundColor = brightness == Brightness.dark
      ? const Color(0xFF000000)
      : const Color(0xFFFFFFFF);

    _controller = WebViewController(
      onPermissionRequest: (request) async {
        bool allGranted = true;
        for (final type in request.types) {
          PermissionStatus status;
          switch (type) {
            case WebViewPermissionResourceType.camera:
              status = await Permission.camera.request();
            default:
              allGranted = false;
              continue;
          }
          if (!status.isGranted) allGranted = false;
        }
        if (allGranted) {
          await request.grant();
        } else {
          await request.deny();
        }
      },
    )
      ..setBackgroundColor(backgroundColor)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('appInterface', onMessageReceived: _handleWebMessage)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (NavigationRequest request) {
            final uri = Uri.parse(request.url);
            if (['response_type', 'client_id', 'redirect_uri', 'scope'].every(uri.queryParameters.containsKey)) {
              _launchAuthorizeRequest(uri);
              return NavigationDecision.prevent;
            }
            if (uri.authority != Uri.parse(_getUrl()).authority) {
              try {
                launchUrl(uri, mode: LaunchMode.externalApplication);
              } catch (e) {
                developer.log('Failed to launch url', error: e);
              }
              return NavigationDecision.prevent;
            }
            if (_isDownloadable(uri)) {
              _downloadFile(uri);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onPageStarted: (String url) {
            setState(() => _loadingError = null);
          },
          onWebResourceError: (WebResourceError error) {
            if (error.errorType == WebResourceErrorType.webContentProcessTerminated) {
              _controller.reload();
            } else if (error.isForMainFrame == true) {
              if (error is! WebKitWebResourceError || error.errorCode != 102) {
                final errorMessage = error.description.isNotEmpty
                  ? error.description
                  : error.errorType?.name ?? 'Error ${error.errorCode}';
                setState(() => _loadingError = errorMessage);
              }
            }
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
      _initialized.complete();
    });
  }

  Future<void> _initNotifications() async {
    await _initialized.future;
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      final eventId = message.data['eventId'];
      if (eventId != null) {
        _controller.loadRequest(Uri.parse('${_getUrl()}/event/$eventId'));
      }
    });
    await _messaging.requestPermission();
    await _authenticated.future.timeout(Duration(seconds: 30), onTimeout: () {});
    _messaging.onTokenRefresh.listen((newToken) {
      _controller.runJavaScript("updateNotificationToken?.('$newToken')");
    });
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final notification = message.notification;
      if (notification != null) {
        _controller.runJavaScript("handleNativeNotification?.(${jsonEncode(message.toMap())})");
        messengerKey.currentState?.showSnackBar(SnackBar(content: Text(notification.body ?? 'Unknown')));
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
          _controller.runJavaScript("updateNotificationToken?.('$notificationToken')");
        }
      case 'authentication':
        final loginToken = await _loginTokenStore.read(true);
        if (loginToken != null) {
          _controller.runJavaScript("handleLoginToken?.('$loginToken')");
        }
      case 'authenticated':
        if (!_authenticated.isCompleted) _authenticated.complete();
      case 'logout':
        await _loginTokenStore.delete();
      case 'server':
        final url = parts[1];
        await _loginTokenStore.delete();
        await _preferences.setString(_urlKey, url);
        await _controller.loadRequest(Uri.parse(url));
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
    if (!_initialized.isCompleted) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadingError != null) {
      return ErrorScreen(
        error: _loadingError!,
        url: _getUrl(),
        onUrlSubmitted: (url) async {
          await _loginTokenStore.delete();
          await _preferences.setString(_urlKey, url);
          await _controller.loadRequest(Uri.parse(url));
          setState(() { _loadingError = null; });
        },
      );
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
        resizeToAvoidBottomInset: false,
        body: SafeArea(
          maintainBottomViewPadding: true,
          child: WebViewWidget(controller: _controller),
        ),
      ),
    );
  }
}
