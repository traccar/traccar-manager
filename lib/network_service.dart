import 'dart:async';
import 'dart:ui';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:internet_connection_checker/internet_connection_checker.dart';

class NetworkService {
  final Connectivity _connectivity = Connectivity();
  final InternetConnectionChecker _checker = InternetConnectionChecker();

  StreamSubscription? _subscription;

  void startListening({
    required VoidCallback onConnected,
    required VoidCallback onDisconnected,
  }) {
    _subscription = _connectivity.onConnectivityChanged.listen((_) async {
      final hasInternet = await _checker.hasConnection;
      if (hasInternet) {
        onConnected();
      } else {
        onDisconnected();
      }
    });
  }

  Future<bool> hasInternet() async {
    return _checker.hasConnection;
  }

  void dispose() {
    _subscription?.cancel();
  }
}
