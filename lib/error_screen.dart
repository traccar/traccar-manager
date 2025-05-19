import 'package:flutter/material.dart';

class ErrorScreen extends StatefulWidget {
  final String error;
  final String url;
  final ValueChanged<String> onUrlSubmitted;

  const ErrorScreen({
    super.key,
    required this.error,
    required this.url,
    required this.onUrlSubmitted,
  });

  @override
  State<ErrorScreen> createState() => _ErrorScreenState();
}

class _ErrorScreenState extends State<ErrorScreen> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.url);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off, size: 96),
            const SizedBox(height: 32),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Text(
                widget.error,
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 32),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: TextField(
                controller: _controller,
                decoration: InputDecoration(
                  border: OutlineInputBorder(),
                  suffixIcon: InkWell(
                    onTap: () => widget.onUrlSubmitted(_controller.text),
                    child: Icon(Icons.check),
                  ),
                ),
                textInputAction: TextInputAction.go,
                onSubmitted: (_) => widget.onUrlSubmitted(_controller.text),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
