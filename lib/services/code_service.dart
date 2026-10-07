import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import '../db/database_helper.dart';

class CodeService {
  static const String _keyDebtPrefix = 'code_debt_prefix';
  static const String _keyPaymentPrefix = 'code_payment_prefix';
  static const String _keyReturnPrefix = 'code_return_prefix';
  static const String _keyDigits = 'code_digits';
  static const String _keyMode = 'code_mode';
  static const String _keyEnabled = 'code_enabled';

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

  // ========== تطبيع النوع ==========
  static String normalizeType(String type) {
    final t = type.toLowerCase().trim();
    if (t == 'return' || t.contains('مرتجع')) return 'return';
    if (t == 'payment' || t.contains('سداد') || t.contains('pay')) {
      return 'payment';
    }
    return 'debt';
  }

  // ========== بادئة النوع ==========
  static Future<String> _getPrefixForType(String type) async {
    final n = normalizeType(type);
    if (n == 'payment') return getPaymentPrefix();
    if (n == 'return') return getReturnPrefix();
    return getDebtPrefix();
  }

  static Future<String> getPrefixForType(String type) async {
    return _getPrefixForType(type);
  }

  // ========== توليد رمز ==========
  static Future<String?> generateCode(String type) async {
    final enabled = await isEnabled();
    if (!enabled) return null;

    final normalized = normalizeType(type);
    final prefix = await _getPrefixForType(normalized);
    final digits = await getDigits();
    final mode = await getMode();

    final db = DatabaseHelper.instance;

    try {
      if (mode == 'random') {
        return await _generateRandom(db, prefix, digits);
      }
      return await _generateSequential(db, prefix, digits);
    } catch (e) {
      // fallback
      final r = Random().nextInt(pow(10, digits).toInt());
      return '$prefix-${r.toString().padLeft(digits, '0')}';
    }
  }

  static Future<String?> _generateSequential(
    DatabaseHelper db,
    String prefix,
    int digits,
  ) async {
    final maxSeq = await _getMaxSequenceByPrefix(db, prefix);
    final maxAttempts = pow(10, digits).toInt();
    int nextSeq = maxSeq + 1;
    if (nextSeq < 1) nextSeq = 1;

    for (int i = 0; i < maxAttempts; i++) {
      final candidate = nextSeq + i;
      if (candidate > maxAttempts) break;
      final code = _format(prefix, candidate, digits);
      final exists = await db.codeExists(code);
      if (!exists) return code;
    }
    return null;
  }

  static Future<String?> _generateRandom(
    DatabaseHelper db,
    String prefix,
    int digits,
  ) async {
    final random = Random.secure();
    for (int i = 0; i < 100; i++) {
      final minValue = pow(10, digits - 1).toInt();
      final maxValue = pow(10, digits).toInt() - 1;
      final number = minValue + random.nextInt(maxValue - minValue + 1);
      final code = _format(prefix, number, digits);
      final exists = await db.codeExists(code);
      if (!exists) return code;
    }
    return null;
  }

  static Future<int> _getMaxSequenceByPrefix(
      DatabaseHelper db, String prefix) async {
    final allCodes = await db.allUsedCodesRaw();
    int maxSeq = 0;
    for (final row in allCodes) {
      final code = row['code'] as String? ?? '';
      if (!code.startsWith('$prefix-')) continue;
      final parts = code.split('-');
      if (parts.length >= 2) {
        final numPart = int.tryParse(parts.sublist(1).join('-'));
        if (numPart != null && numPart > maxSeq) maxSeq = numPart;
      }
    }
    return maxSeq;
  }

  static String _format(String prefix, int number, int digits) {
    return '$prefix-${number.toString().padLeft(digits, '0')}';
  }

  // ========== تحديث رموز العمليات القديمة ==========
  static Future<int> updateOldCodes({
    required String oldPrefix,
    required String newPrefix,
  }) async {
    if (oldPrefix.isEmpty || newPrefix.isEmpty) return 0;
    if (oldPrefix == newPrefix) return 0;
    final db = DatabaseHelper.instance;
    return db.updateCodesPrefix(
      oldPrefix: oldPrefix,
      newPrefix: newPrefix,
    );
  }

  // ========== إحصائيات ==========
  static int getMaxPossible(int digits) {
    return pow(10, digits).toInt() - pow(10, digits - 1).toInt();
  }

  static String describeMode(String mode) {
    return mode == 'random' ? 'عشوائي' : 'مرتب (تسلسلي)';
  }

  static Future<Map<String, int>> getStats() async {
    return DatabaseHelper.instance.getCodesStats();
  }
}
