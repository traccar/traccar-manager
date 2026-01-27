import 'package:flutter/material.dart';

void showNoInternetSnackbar(GlobalKey<ScaffoldMessengerState> key) {
  key.currentState?.showSnackBar(
    const SnackBar(
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.wifi_off),
          Text(
            'No internet connection. Please check your network settings!',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ],
      ),
      backgroundColor: Colors.redAccent,
      behavior: SnackBarBehavior.floating,
      duration: Duration(days: 1),
    ),
  );
}

void hideInternetSnackbar(GlobalKey<ScaffoldMessengerState> key) {
  key.currentState?.hideCurrentSnackBar();
}
