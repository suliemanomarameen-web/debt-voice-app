import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static final _auth = LocalAuthentication();
  static const _keyEnabled = 'biometric_enabled';
  static const _keyPasswordHash = 'password_hash';

  // ========== تفعيل/تعطيل ==========
  static Future<bool> isEnabled() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getBool(_keyEnabled) ?? false;
  }

  static Future<void> setEnabled(bool value) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_keyEnabled, value);
  }

  // ========== كلمة المرور ==========
  static Future<void> setPassword(String password) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_keyPasswordHash, _hash(password));
  }

  static Future<bool> verifyPassword(String password) async {
    final sp = await SharedPreferences.getInstance();
    final stored = sp.getString(_keyPasswordHash);
    if (stored == null) return false;
    return stored == _hash(password);
  }

  static Future<bool> hasPassword() async {
    final sp = await SharedPreferences.getInstance();
    return sp.containsKey(_keyPasswordHash);
  }

  static Future<void> removePassword() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_keyPasswordHash);
  }

  static String _hash(String text) {
    final bytes = utf8.encode(text);
    return sha256.convert(bytes).toString();
  }

  // ========== البصمة ==========
  static Future<bool> canUseBiometrics() async {
    try {
      final supported = await _auth.isDeviceSupported();
      final canCheck = await _auth.canCheckBiometrics;
      return supported && canCheck;
    } on PlatformException {
      return false;
    }
  }

  static Future<bool> authenticate({String reason = 'افتح دفتر الديون'}) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
          useErrorDialogs: true,
        ),
      );
    } on PlatformException {
      return false;
    }
  }
}
