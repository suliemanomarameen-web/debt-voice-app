import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static const _keyEnabled = 'lock_enabled';
  static const _keyPasswordHash = 'password_hash';
  static const _keySecurityQuestion = 'security_question';
  static const _keySecurityAnswerHash = 'security_answer_hash';

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
      await sp.remove(_keySecurityQuestion);
      await sp.remove(_keySecurityAnswerHash);
    } catch (e) {
      debugPrint('removePassword error: $e');
    }
  }

  // ========== سؤال الأمان ==========
  static Future<void> setSecurity({
    required String question,
    required String answer,
  }) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_keySecurityQuestion, question);
      await sp.setString(_keySecurityAnswerHash, _hash(answer.toLowerCase().trim()));
    } catch (e) {
      debugPrint('setSecurity error: $e');
    }
  }

  static Future<String?> getSecurityQuestion() async {
    try {
      final sp = await SharedPreferences.getInstance();
      return sp.getString(_keySecurityQuestion);
    } catch (e) {
      return null;
    }
  }

  static Future<bool> verifySecurityAnswer(String answer) async {
    try {
      final sp = await SharedPreferences.getInstance();
      final stored = sp.getString(_keySecurityAnswerHash);
      if (stored == null) return false;
      return stored == _hash(answer.toLowerCase().trim());
    } catch (e) {
      debugPrint('verifySecurityAnswer error: $e');
      return false;
    }
  }

  static Future<bool> hasSecurity() async {
    try {
      final sp = await SharedPreferences.getInstance();
      return sp.containsKey(_keySecurityQuestion) &&
          sp.containsKey(_keySecurityAnswerHash);
    } catch (e) {
      return false;
    }
  }

  // ========== Hash ==========
  static String _hash(String text) {
    final bytes = utf8.encode(text);
    return sha256.convert(bytes).toString();
  }
}
