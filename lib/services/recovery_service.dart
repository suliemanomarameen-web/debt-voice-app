import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// خدمة الاستعادة — تُدير:
/// - رمز الاسترداد (توليد + تخزين + تحقق)
/// - سؤال الأمان (جاهز + مخصص)
class RecoveryService {
  // ═══════════════════════════════════════════════════════════
  // المفاتيح
  // ═══════════════════════════════════════════════════════════
  static const String _keyRecoveryCodeHash = 'recovery_code_hash';
  static const String _keyRecoveryCodePlain = 'recovery_code_plain';
  static const String _keySecurityQuestion = 'security_question';
  static const String _keySecurityAnswerHash = 'security_answer_hash';
  static const String _keyQuestionIsCustom = 'security_question_is_custom';
  static const String _keyRecoveryEnabled = 'recovery_enabled';

  // ═══════════════════════════════════════════════════════════
  // الأسئلة الجاهزة
  // ═══════════════════════════════════════════════════════════
  static const List<String> presetQuestions = [
    'ما اسم مدينتك الأولى؟',
    'ما اسم أول مدرسة درست فيها؟',
    'ما اسم والدتك؟',
    'ما اسم أول صديق لك؟',
    'ما اسم حيوانك المفضل؟',
    'ما اسم أول معلم لك؟',
    'ما هو لونك المفضل؟',
  ];

  // ═══════════════════════════════════════════════════════════
  // توليد رمز الاسترداد
  // ═══════════════════════════════════════════════════════════
  /// توليد رمز عشوائي بصيغة: A3K9-P2M7-X5N1-Q8R4
  static String generateRecoveryCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();

    String makeGroup() {
      return List.generate(4, (_) => chars[random.nextInt(chars.length)])
          .join();
    }

    return '${makeGroup()}-${makeGroup()}-${makeGroup()}-${makeGroup()}';
  }

  // ═══════════════════════════════════════════════════════════
  // حفظ رمز الاسترداد
  // ═══════════════════════════════════════════════════════════
  static Future<void> setRecoveryCode(String code) async {
    try {
      final cleaned = code.trim().toUpperCase();
      if (cleaned.isEmpty) return;

      final sp = await SharedPreferences.getInstance();
      await sp.setString(_keyRecoveryCodeHash, _hash(cleaned));
      await sp.setString(_keyRecoveryCodePlain, cleaned);
      await sp.setBool(_keyRecoveryEnabled, true);

      debugPrint('✅ [Recovery] Code saved');
    } catch (e) {
      debugPrint('❌ [Recovery] setRecoveryCode error: $e');
    }
  }

  static Future<bool> verifyRecoveryCode(String code) async {
    try {
      final sp = await SharedPreferences.getInstance();
      final storedHash = sp.getString(_keyRecoveryCodeHash);
      if (storedHash == null) return false;

      final input = code.trim().toUpperCase();
      return storedHash == _hash(input);
    } catch (e) {
      debugPrint('❌ [Recovery] verifyRecoveryCode error: $e');
      return false;
    }
  }

  /// جلب الرمز النصي
  /// ⚠️ يُستخدم فقط في الإعدادات (بعد التحقق من كلمة المرور)
  static Future<String?> getRecoveryCodePlain() async {
    try {
      final sp = await SharedPreferences.getInstance();
      return sp.getString(_keyRecoveryCodePlain);
    } catch (e) {
      return null;
    }
  }

  static Future<bool> hasRecoveryCode() async {
    try {
      final sp = await SharedPreferences.getInstance();
      return sp.containsKey(_keyRecoveryCodeHash);
    } catch (e) {
      return false;
    }
  }

  static Future<void> removeRecoveryCode() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(_keyRecoveryCodeHash);
      await sp.remove(_keyRecoveryCodePlain);
      debugPrint('✅ [Recovery] Code removed');
    } catch (e) {
      debugPrint('❌ [Recovery] removeRecoveryCode error: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // سؤال الأمان (جاهز + مخصص)
  // ═══════════════════════════════════════════════════════════
  static Future<void> setSecurityQuestion({
    required String question,
    required String answer,
    required bool isCustom,
  }) async {
    try {
      final q = question.trim();
      final a = answer.trim();
      if (q.isEmpty || a.isEmpty) return;

      final sp = await SharedPreferences.getInstance();
      await sp.setString(_keySecurityQuestion, q);
      await sp.setString(_keySecurityAnswerHash, _hash(a.toLowerCase()));
      await sp.setBool(_keyQuestionIsCustom, isCustom);

      debugPrint('✅ [Recovery] Security question saved (custom: $isCustom)');
    } catch (e) {
      debugPrint('❌ [Recovery] setSecurityQuestion error: $e');
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

  static Future<bool> isQuestionCustom() async {
    try {
      final sp = await SharedPreferences.getInstance();
      return sp.getBool(_keyQuestionIsCustom) ?? false;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> verifySecurityAnswer(String answer) async {
    try {
      final sp = await SharedPreferences.getInstance();
      final storedHash = sp.getString(_keySecurityAnswerHash);
      if (storedHash == null) return false;

      return storedHash == _hash(answer.trim().toLowerCase());
    } catch (e) {
      debugPrint('❌ [Recovery] verifySecurityAnswer error: $e');
      return false;
    }
  }

  static Future<bool> hasSecurityQuestion() async {
    try {
      final sp = await SharedPreferences.getInstance();
      return sp.containsKey(_keySecurityQuestion) &&
          sp.containsKey(_keySecurityAnswerHash);
    } catch (e) {
      return false;
    }
  }

  static Future<void> removeSecurityQuestion() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(_keySecurityQuestion);
      await sp.remove(_keySecurityAnswerHash);
      await sp.remove(_keyQuestionIsCustom);
    } catch (e) {
      debugPrint('❌ [Recovery] removeSecurityQuestion error: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // أدوات مساعدة
  // ═══════════════════════════════════════════════════════════
  static String _hash(String text) {
    final bytes = utf8.encode(text);
    return sha256.convert(bytes).toString();
  }

  /// فحص شامل: هل الاستعادة جاهزة؟
  static Future<bool> isRecoveryReady() async {
    final hasCode = await hasRecoveryCode();
    final hasQuestion = await hasSecurityQuestion();
    return hasCode && hasQuestion;
  }

  /// مسح كل بيانات الاستعادة
  static Future<void> clearAll() async {
    await removeRecoveryCode();
    await removeSecurityQuestion();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(_keyRecoveryEnabled);
    } catch (_) {}
    debugPrint('✅ [Recovery] All cleared');
  }
}
