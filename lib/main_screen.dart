import 'dart:async';
import 'dart:collection';
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
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_android/shared_preferences_android.dart';
import 'package:traccar_manager/error_screen.dart';
import 'package:traccar_manager/main.dart';
import 'package:traccar_manager/token_store.dart';
import 'package:url_launcher/url_launcher.dart';

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
  late final AppLinks _appLinks;
  StreamSubscription<Uri>? _appLinksSubscription;
  final _loginTokenStore = TokenStore();
  final _messaging = FirebaseMessaging.instance;
  InAppWebViewController? _controller;
  String? _loadingError;
  String? _initialUrl;
  bool _settingsReady = false;
  bool _controllerReady = false;

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
        final appPathSegments = [uri.host, ...uri.pathSegments];
        final updatedQueryParameters = Map<String, String>.from(uri.queryParameters)
          ..['redirect_uri'] = uri.toString().split('?').first;
        final updatedUri = uri.replace(
          scheme: baseUri.scheme,
          host: baseUri.host,
          port: baseUri.port,
          path: '/${appPathSegments.join('/')}',
          queryParameters: updatedQueryParameters,
        );
        _loadUrl(updatedUri);
      } else {
        _loadUrl(uri);
      }
    });
  }

  Future<void> _launchAuthorizeRequest(Uri uri) async {
    try {
      final originalRedirect = Uri.parse(uri.queryParameters['redirect_uri']!);
      final redirectSegments = originalRedirect.pathSegments;
      final updatedRedirect = Uri(
        scheme: 'org.traccar.manager',
        host: redirectSegments.first,
        path: '/${redirectSegments.skip(1).join('/')}',
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

  Future<void> _shareFile(String fileName, Uint8List bytes) async {
    final directory = Platform.isAndroid
      ? await getExternalStorageDirectory()
      : await getApplicationDocumentsDirectory();
    final file = File('${directory!.path}/$fileName');
    await file.writeAsBytes(bytes);
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
  }

  Future<void> _downloadFile(Uri uri) async {
    try {
      final token = await _loginTokenStore.read(false);
      if (token == null) return;
      final response = await http.get(uri, headers: {'Authorization': 'Bearer $token'});
      if (response.statusCode == 200) {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final extension = uri.pathSegments.last;
        _shareFile('$timestamp.$extension', response.bodyBytes);
      } else {
        developer.log('Failed file download request');
      }
    } catch (e) {
      developer.log('Failed to download file', error: e);
    }
  }

  void _maybeCompleteInitialized() {
    if (!_initialized.isCompleted && _settingsReady && _controllerReady) {
      _initialized.complete();
    }
  }

  Future<void> _initWebView() async {
    _preferences = await SharedPreferencesWithCache.create(
      sharedPreferencesOptions: Platform.isAndroid
        ? SharedPreferencesAsyncAndroidOptions(backend: SharedPreferencesAndroidBackendLibrary.SharedPreferences)
        : SharedPreferencesOptions(),
      cacheOptions: SharedPreferencesWithCacheOptions(allowList: {'url'}),
    );

    var url = _getUrl();
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      final eventId = initialMessage.data['eventId'];
      if (eventId != null) {
        url = '$url/event/$eventId';
      }
    }

    setState(() {
      _initialUrl = url;
      _settingsReady = true;
    });

    _maybeCompleteInitialized();
  }

  Future<void> _initNotifications() async {
    await _initialized.future;
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      final eventId = message.data['eventId'];
      if (eventId != null) {
        _loadUrl(Uri.parse('${_getUrl()}/event/$eventId'));
      }
    });
    await _messaging.requestPermission();
    await _authenticated.future.timeout(const Duration(seconds: 30), onTimeout: () {});
    _messaging.onTokenRefresh.listen((newToken) {
      _controller?.evaluateJavascript(source: "updateNotificationToken?.('$newToken')");
    });
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final notification = message.notification;
      if (notification != null) {
        _controller?.evaluateJavascript(source: "handleNativeNotification?.(${jsonEncode(message.toMap())})");
        messengerKey.currentState?.showSnackBar(SnackBar(content: Text(notification.body ?? 'Unknown')));
      }
    });
  }

  void _handleWebMessage(String message) async {
    final List<String> parts = message.split('|');
    switch (parts[0]) {
      case 'login':
        if (parts.length > 1) {
          await _loginTokenStore.save(parts[1]);
        }
        final notificationToken = await _messaging.getToken();
        if (notificationToken != null) {
          _controller?.evaluateJavascript(source: "updateNotificationToken?.('$notificationToken')");
        }
      case 'authentication':
        final loginToken = await _loginTokenStore.read(true);
        if (loginToken != null) {
          _controller?.evaluateJavascript(source: "handleLoginToken?.('$loginToken')");
        }
      case 'authenticated':
        if (!_authenticated.isCompleted) _authenticated.complete();
      case 'logout':
        await _loginTokenStore.delete();
      case 'download':
        try {
          _shareFile('report.xlsx', base64Decode(parts[1]));
        } catch (e) {
          developer.log('Failed to save downloaded file', error: e);
        }
      case 'server':
        final url = parts[1];
        await _loginTokenStore.delete();
        await _preferences.setString(_urlKey, url);
        await _loadUrl(Uri.parse(url));
    }
  }

  bool _isRootOrLogin(String baseUrl, String? currentUrl) {
    if (currentUrl == null) return false;
    final baseUri = Uri.parse(baseUrl);
    final currentUri = Uri.parse(currentUrl);
    if (baseUri.origin != currentUri.origin) return false;
    return currentUri.path == '/' || currentUri.path == '/login';
  }

  Future<void> _loadUrl(Uri uri) async {
    await _controller?.loadUrl(urlRequest: URLRequest(url: WebUri(uri.toString())));
  }

  @override
  Widget build(BuildContext context) {
    if (!_settingsReady) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadingError != null) {
      return ErrorScreen(
        error: _loadingError!,
        url: _getUrl(),
        onUrlSubmitted: (url) async {
          await _loginTokenStore.delete();
          await _preferences.setString(_urlKey, url);
          await _loadUrl(Uri.parse(url));
          setState(() { _loadingError = null; });
        },
      );
    }
    final brightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _controller?.getUrl().then((url) {
          _controller?.canGoBack().then((canGoBack) {
            if (canGoBack == true && !_isRootOrLogin(_getUrl(), url?.toString())) {
              _controller?.goBack();
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
          child: InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(_initialUrl!)),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              useShouldOverrideUrlLoading: true,
              underPageBackgroundColor:
                  brightness == Brightness.dark
                      ? const Color(0xFF000000)
                      : const Color(0xFFFFFFFF),
            ),
            initialUserScripts: UnmodifiableListView<UserScript>([
              UserScript(
                source: '''
                  window.appInterface = {
                    postMessage: function(message) {
                      if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                        window.flutter_inappwebview.callHandler('appInterface', message);
                      } else {
                        window.__traccarMessageQueue = window.__traccarMessageQueue || [];
                        window.__traccarMessageQueue.push(message);
                      }
                    }
                  };
                  const excelType = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
                  const originalCreateObjectURL = URL.createObjectURL;
                  URL.createObjectURL = function(object) {
                    if (object instanceof Blob && object.type === excelType) {
                      const reader = new FileReader();
                      reader.onload = () => {
                        window.appInterface.postMessage('download|' + reader.result.split(',')[1]);
                      };
                      reader.readAsDataURL(object);
                    }
                    return originalCreateObjectURL.apply(this, arguments);
                  };
                  window.addEventListener('flutterInAppWebViewPlatformReady', function() {
                    if (window.__traccarMessageQueue && window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                      window.__traccarMessageQueue.forEach(function(message) {
                        window.flutter_inappwebview.callHandler('appInterface', message);
                      });
                      window.__traccarMessageQueue = [];
                    }
                  });
                ''',
                injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
              ),
            ]),
            onWebViewCreated: (controller) {
              _controller = controller;
              controller.addJavaScriptHandler(
                handlerName: 'appInterface',
                callback: (args) {
                  if (args.isEmpty) return null;
                  _handleWebMessage(args.first.toString());
                  return null;
                },
              );
              _controllerReady = true;
              _maybeCompleteInitialized();
            },
            onLoadStart: (controller, url) {
              setState(() => _loadingError = null);
            },
            shouldOverrideUrlLoading: (controller, navigationAction) async {
              final target = navigationAction.request.url;
              if (target == null) {
                return NavigationActionPolicy.ALLOW;
              }
              final uri = Uri.parse(target.toString());
              if (['response_type', 'client_id', 'redirect_uri', 'scope'].every(uri.queryParameters.containsKey)) {
                _launchAuthorizeRequest(uri);
                return NavigationActionPolicy.CANCEL;
              }
              if (uri.authority != Uri.parse(_getUrl()).authority) {
                try {
                  launchUrl(uri, mode: LaunchMode.externalApplication);
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
            onReceivedError: (controller, request, error) {
              if (request.isForMainFrame == true) {
                if (error.type == WebResourceErrorType.CANCELLED) {
                  return;
                }
                final errorMessage = error.description.isNotEmpty
                  ? error.description
                  : error.type.toString();
                setState(() => _loadingError = errorMessage);
              }
            },
            onRenderProcessGone: (controller, detail) async {
              await controller.reload();
            },
            onWebContentProcessDidTerminate: (controller) {
              controller.reload();
            },
            onGeolocationPermissionsShowPrompt: (controller, origin) async {
              final status = await Permission.location.request();
              return GeolocationPermissionShowPromptResponse(
                origin: origin,
                allow: status.isGranted,
                retain: true,
              );
            },
            onPermissionRequest: (controller, request) async {
              var allGranted = true;
              for (final resource in request.resources) {
                PermissionStatus status;
                final resourceUpper = resource.toString().toUpperCase();
                if (resourceUpper.contains('VIDEO_CAPTURE') || resourceUpper.contains('CAMERA')) {
                  status = await Permission.camera.request();
                } else {
                  allGranted = false;
                  continue;
                }
                if (!status.isGranted) allGranted = false;
              }
              return PermissionResponse(
                resources: request.resources,
                action: allGranted
                  ? PermissionResponseAction.GRANT
                  : PermissionResponseAction.DENY,
              );
            },
          ),
        ),
      ),
    );
  }
}
