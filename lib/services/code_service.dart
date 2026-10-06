import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import '../db/database_helper.dart';

class CodeService {
  // ========== مفاتيح الإعدادات ==========
  static const String _keyDebtPrefix = 'code_debt_prefix';
  static const String _keyPaymentPrefix = 'code_payment_prefix';
  static const String _keyReturnPrefix = 'code_return_prefix';
  static const String _keyDigits = 'code_digits';
  static const String _keyMode = 'code_mode';
  static const String _keyEnabled = 'code_enabled';

  // ========== القيم الافتراضية ==========
  static const String _defaultDebtPrefix = 'D';
  static const String _defaultPaymentPrefix = 'P';
  static const String _defaultReturnPrefix = 'R';
  static const int _defaultDigits = 4;
  static const String _defaultMode = 'sequential';

  // ========== جلب الإعدادات ==========
  static Future<String> getDebtPrefix() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getString(_keyDebtPrefix) ?? _defaultDebtPrefix;
  }

  static Future<String> getPaymentPrefix() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getString(_keyPaymentPrefix) ?? _defaultPaymentPrefix;
  }

  static Future<String> getReturnPrefix() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getString(_keyReturnPrefix) ?? _defaultReturnPrefix;
  }

  static Future<int> getDigits() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getInt(_keyDigits) ?? _defaultDigits;
  }

  static Future<String> getMode() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getString(_keyMode) ?? _defaultMode;
  }

  static Future<bool> isEnabled() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getBool(_keyEnabled) ?? true;
  }

  // ========== حفظ الإعدادات ==========
  static Future<void> setDebtPrefix(String v) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_keyDebtPrefix, v.trim().toUpperCase());
  }

  static Future<void> setPaymentPrefix(String v) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_keyPaymentPrefix, v.trim().toUpperCase());
  }

  static Future<void> setReturnPrefix(String v) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_keyReturnPrefix, v.trim().toUpperCase());
  }

  static Future<void> setDigits(int v) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setInt(_keyDigits, v);
  }

  static Future<void> setMode(String v) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_keyMode, v);
  }

  static Future<void> setEnabled(bool v) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_keyEnabled, v);
  }

  // ========== الحصول على بادئة النوع ==========
  static Future<String> _getPrefixForType(String type) async {
    if (type == 'payment') return getPaymentPrefix();
    if (type == 'return') return getReturnPrefix();
    return getDebtPrefix();
  }

  /// جلب البادئة الحالية لنوع معين (للعامة)
  static Future<String> getPrefixForType(String type) async {
    return _getPrefixForType(type);
  }

  // ========== توليد رمز جديد ==========
  static Future<String?> generateCode(String type) async {
    final enabled = await isEnabled();
    if (!enabled) return null;

    final prefix = await _getPrefixForType(type);
    final digits = await getDigits();
    final mode = await getMode();

    final db = DatabaseHelper.instance;

    if (mode == 'random') {
      return _generateRandom(db, prefix, digits, type);
    } else {
      return _generateSequential(db, prefix, digits, type);
    }
  }

  /// توليد مرتب (تسلسلي)
  static Future<String?> _generateSequential(
    DatabaseHelper db,
    String prefix,
    int digits,
    String type,
  ) async {
    // نستخدم النوع المخزّن (payment للـ return)
    final storageType = (type == 'return') ? 'payment' : type;
    final maxSeq = await db.getMaxSequence(storageType);

    final maxAttempts = pow(10, digits).toInt();
    int nextSeq = maxSeq + 1;

    for (int i = 0; i < maxAttempts; i++) {
      final candidate = nextSeq + i;
      if (candidate > maxAttempts) break;

      final code = _format(prefix, candidate, digits);
      final exists = await db.codeExists(code);
      if (!exists) {
        return code;
      }
    }

    return null;
  }

  /// توليد عشوائي
  static Future<String?> _generateRandom(
    DatabaseHelper db,
    String prefix,
    int digits,
    String type,
  ) async {
    final random = Random.secure();
    final maxAttempts = 100;

    for (int i = 0; i < maxAttempts; i++) {
      final minValue = pow(10, digits - 1).toInt();
      final maxValue = pow(10, digits).toInt() - 1;
      final number = minValue + random.nextInt(maxValue - minValue + 1);

      final code = _format(prefix, number, digits);
      final exists = await db.codeExists(code);
      if (!exists) {
        return code;
      }
    }

    return null;
  }

  /// تنسيق الرمز: PREFIX-NUMBER
  static String _format(String prefix, int number, int digits) {
    final paddedNumber = number.toString().padLeft(digits, '0');
    return '$prefix-$paddedNumber';
  }

  // ============================================================
  // ============ تحديث رموز العمليات القديمة ====================
  // ============================================================

  /// تحديث رموز العمليات القديمة عند تغيير البادئة
  /// [type]: 'debt', 'payment', أو 'return'
  /// [newPrefix]: البادئة الجديدة
  /// يعيد: عدد العمليات المُحدَّثة
  static Future<int> updateOldCodes({
    required String type,
    required String newPrefix,
  }) async {
    final db = DatabaseHelper.instance;

    // جلب البادئة الحالية المخزنة
    final oldPrefix = await _getPrefixForType(type);

    if (oldPrefix == newPrefix) return 0;
    if (oldPrefix.isEmpty || newPrefix.isEmpty) return 0;

    // النوع المخزّن في DB
    final storageType = (type == 'return') ? 'payment' : type;

    // استدعاء دالة التحديث في DB
    final count = await db.updateCodesPrefix(
      oldPrefix: oldPrefix,
      newPrefix: newPrefix,
    );

    return count;
  }

  /// جلب عدد الرموز القديمة لنوع معين (لعرضه في الإعدادات)
  static Future<int> getOldCodesCount(String type) async {
    final db = DatabaseHelper.instance;
    final prefix = await _getPrefixForType(type);
    if (prefix.isEmpty) return 0;

    final allCodes = await db.allTransactionsRaw();
    int count = 0;
    for (final t in allCodes) {
      final code = t['code'] as String?;
      if (code != null && code.startsWith('$prefix-')) {
        count++;
      }
    }
    return count;
  }

  // ========== إحصائيات ==========
  static int getMaxPossible(int digits) {
    return pow(10, digits).toInt() - pow(10, digits - 1).toInt();
  }

  static String describeMode(String mode) {
    return mode == 'random' ? 'عشوائي' : 'مرتب (تسلسلي)';
  }

  static String describeDigits(int digits) {
    return '$digits أرقام';
  }

  /// فحص الرموز المستخدمة (للعرض)
  static Future<Map<String, int>> getStats() async {
    return DatabaseHelper.instance.getCodesStats();
  }
}
