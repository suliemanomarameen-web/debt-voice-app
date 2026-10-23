import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import '../db/database_helper.dart';
import '../config/app_settings.dart';
import 'accountants_service.dart';
import 'settings_service.dart';

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

  static String normalizeType(String type) {
    final t = type.toLowerCase().trim();
    if (t == 'return' || t.contains('مرتجع')) return 'return';
    if (t == 'payment' || t.contains('سداد') || t.contains('pay')) {
      return 'payment';
    }
    return 'debt';
  }

  static Future<String> _getPrefixForType(String type) async {
    final n = normalizeType(type);
    if (n == 'payment') return getPaymentPrefix();
    if (n == 'return') return getReturnPrefix();
    return getDebtPrefix();
  }

  static Future<String> getPrefixForType(String type) async {
    return _getPrefixForType(type);
  }

  // 🆕 رمز المحاسب
  static Future<String> _getAccountantCode() async {
    try {
      final include = SettingsService.getBool(
        AppSettings.codeIncludeAccountant,
        defaultValue: false,
      );
      if (!include) return '';

      final acc = await AccountantsService.getCurrentAccountant();
      return acc?.code.trim() ?? '';
    } catch (_) {
      return '';
    }
  }

  static String _getSeparator() {
    return SettingsService.getString(
      AppSettings.codeAccountantSeparator,
      defaultValue: '',
    );
  }

  static String _getPosition() {
    return SettingsService.getString(
      AppSettings.codeAccountantPosition,
      defaultValue: 'suffix',
    );
  }

  static Future<String> _getEffectivePrefix(String typePrefix) async {
    final acc = await _getAccountantCode();
    if (acc.isEmpty) return typePrefix;
    if (_getPosition() == 'prefix') {
      return '$acc${_getSeparator()}$typePrefix';
    }
    return typePrefix;
  }

  static Future<String> _applyAccountantCode(String baseCode) async {
    final acc = await _getAccountantCode();
    if (acc.isEmpty) return baseCode;

    final sep = _getSeparator();
    final pos = _getPosition();

    if (pos == 'prefix') {
      return '$acc$sep$baseCode';
    } else {
      return '$baseCode$sep$acc';
    }
  }

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
      final r = Random().nextInt(pow(10, digits).toInt());
      final baseCode = '$prefix-${r.toString().padLeft(digits, '0')}';
      return await _applyAccountantCode(baseCode);
    }
  }

  static Future<String?> _generateSequential(
    DatabaseHelper db,
    String prefix,
    int digits,
  ) async {
    final effectivePrefix = await _getEffectivePrefix(prefix);
    final maxSeq = await db.getMaxCodeSequence(effectivePrefix);
    final maxAttempts = pow(10, digits).toInt();
    int nextSeq = maxSeq + 1;
    if (nextSeq < 1) nextSeq = 1;

    final maxTries = (maxAttempts < 10) ? maxAttempts : 10;

    for (int i = 0; i < maxTries; i++) {
      final candidate = nextSeq + i;
      if (candidate > maxAttempts) break;
      final baseCode = _format(prefix, candidate, digits);
      final fullCode = await _applyAccountantCode(baseCode);
      final exists = await db.codeExists(fullCode);
      if (!exists) return fullCode;
    }

    return await _generateRandom(db, prefix, digits);
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
      final baseCode = _format(prefix, number, digits);
      final fullCode = await _applyAccountantCode(baseCode);
      final exists = await db.codeExists(fullCode);
      if (!exists) return fullCode;
    }
    return null;
  }

  static String _format(String prefix, int number, int digits) {
    return '$prefix-${number.toString().padLeft(digits, '0')}';
  }

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
