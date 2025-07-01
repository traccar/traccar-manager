import 'package:flutter/material.dart';
import 'package:traccar_manager/main.dart';

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

  void _submit() {
    final text = _controller.text.trim();
    final uri = Uri.tryParse(text);
    final valid = text.isNotEmpty && uri != null && uri.isAbsolute &&
      (uri.scheme == 'http' || uri.scheme == 'https');
    if (valid) {
      widget.onUrlSubmitted(text);
    } else {
      messengerKey.currentState?.showSnackBar(SnackBar(content: Text('Invalid URL')));
    }
  }

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
                    onTap: _submit,
                    child: Icon(Icons.check),
                  ),
                ),
                textInputAction: TextInputAction.go,
                onSubmitted: (_) => _submit(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
