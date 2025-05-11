import 'dart:developer' as developer;

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

class TokenStore {
  static const _tokenKey = 'token';
  final _storage = const FlutterSecureStorage();
  final _auth = LocalAuthentication();

  Future<void> save(String token) async {
    await _storage.write(key: _tokenKey, value: token);
  }

  Future<String?> read() async {
    if (!await _storage.containsKey(key: _tokenKey)) {
      return null;
    }
    try {
      final bool authenticated = await _auth.authenticate(
        localizedReason: 'Authenticate to access login token',
      );
      if (authenticated) {
        return _storage.read(key: _tokenKey);
      }
    } on PlatformException catch (e) {
      developer.log('Failed to read token.', error: e);
    }
    return null;
  }

  Future<void> delete() async {
    _storage.delete(key: _tokenKey);
  }
}
