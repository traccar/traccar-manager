import 'package:flutter/material.dart';
import 'package:traccar_manager/token_store.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  bool _initialized = false;
  late final SharedPreferences _preferences;
  late final WebViewController _controller;
  final _tokenStore = TokenStore();

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  Future<void> _initWebView() async {
    _preferences = await SharedPreferences.getInstance();

    final url = _preferences.getString('url') ?? 'https://demo.traccar.org'; //'http://localhost:3000';
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('appInterface', onMessageReceived: _handleMessage)
      ..loadRequest(Uri.parse(url));

    setState(() {
      _initialized = true;
    });
  }

  void _handleMessage(JavaScriptMessage interfaceMessage) async {
    final List<String> parts = interfaceMessage.message.split('|');
    switch (parts[0]) {
      case 'login':
        if (parts.length > 1) {
          await _tokenStore.save(parts[1]);
        }
        // TODO register notification token
      case 'authentication':
        final token = await _tokenStore.read();
        if (token != null) {
          _controller.runJavaScript("handleLoginToken && handleLoginToken('$token')");
        }
      case 'logout':
        await _tokenStore.delete();
      case 'server':
        final url = parts[1];
        await _preferences.setString('url', url);
        _controller.loadRequest(Uri.parse(url));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return Scaffold(
      body: SafeArea(
        child: WebViewWidget(controller: _controller),
      ),
    );
  }
}
