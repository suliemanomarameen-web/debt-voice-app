import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static final _auth = LocalAuthentication();
  static const _keyEnabled = 'biometric_enabled';
  static const _keyPasswordHash = 'password_hash';

  // ========== تفعيل/تعطيل ==========
  static Future<bool> isEnabled() async {
    try {
      final sp = await SharedPreferences.getInstance();
      return sp.getBool(_keyEnabled) ?? false;
    } catch (e) {
      debugPrint('isEnabled error: $e');
      return false;
    }
  }

  static Future<void> setEnabled(bool value) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool(_keyEnabled, value);
    } catch (e) {
      debugPrint('setEnabled error: $e');
    }
  }

  // ========== كلمة المرور ==========
  static Future<void> setPassword(String password) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_keyPasswordHash, _hash(password));
    } catch (e) {
      debugPrint('setPassword error: $e');
    }
  }

  static Future<bool> verifyPassword(String password) async {
    try {
      final sp = await SharedPreferences.getInstance();
      final stored = sp.getString(_keyPasswordHash);
      if (stored == null) return false;
      return stored == _hash(password);
    } catch (e) {
      debugPrint('verifyPassword error: $e');
      return false;
    }
  }

  static Future<bool> hasPassword() async {
    try {
      final sp = await SharedPreferences.getInstance();
      return sp.containsKey(_keyPasswordHash);
    } catch (e) {
      return false;
    }
  }

  static Future<void> removePassword() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(_keyPasswordHash);
    } catch (e) {
      debugPrint('removePassword error: $e');
    }
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
    } catch (e) {
      debugPrint('canUseBiometrics error: $e');
      return false;
    }
  }

  /// Authenticate — مع معالجة كاملة للأخطاء
  static Future<bool> authenticate({String reason = 'افتح دفتر الديون'}) async {
    try {
      final result = await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
          useErrorDialogs: false, // ← نمنع dialogs مخصصة
        ),
      );
      return result;
    } on PlatformException catch (e) {
      debugPrint('authenticate PlatformException: ${e.code} - ${e.message}');
      return false;
    } catch (e) {
      debugPrint('authenticate error: $e');
      return false;
    }
  }
}
