import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  late final Future<WebViewController> _webViewControllerFuture;

  @override
  void initState() {
    super.initState();
    _webViewControllerFuture = _initWebView();
  }

  Future<WebViewController> _initWebView() async {
    final preferences = await SharedPreferences.getInstance();
    final url = preferences.getString('url') ?? 'https://demo.traccar.org'; //'http://localhost:3000';

    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse(url));

    return controller;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: FutureBuilder<WebViewController>(
          future: _webViewControllerFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.done && snapshot.hasData) {
              return WebViewWidget(controller: snapshot.data!);
            } else {
              return const Center(child: CircularProgressIndicator());
            }
          },
        ),
      ),
    );
  }
}
