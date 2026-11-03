import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../db/database_helper.dart';
import '../config/app_settings.dart';
import 'accountants_service.dart';
import 'code_counter_service.dart';
import 'settings_service.dart';

class CodeService {
  static const String _keyDebtPrefix = 'code_debt_prefix';
  static const String _keyPaymentPrefix = 'code_payment_prefix';
  static const String _keyReturnPrefix = 'code_return_prefix';
  static const String _keyDigits = 'code_digits';
  static const String _keyMode = 'code_mode';
  static const String _keyEnabled = 'code_enabled';

  static const String _keyMigrated = 'code_counters_migrated_v1';

  static const String _defaultDebtPrefix = 'D';
  static const String _defaultPaymentPrefix = 'P';
  static const String _defaultReturnPrefix = 'R';
  static const int _defaultDigits = 4;
  static const String _defaultMode = 'sequential';

  // ═══════════════════════════════════════════════════════════
  // قراءة/كتابة الإعدادات
  // ═══════════════════════════════════════════════════════════

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

  // ═══════════════════════════════════════════════════════════
  // نوع + بادئة + رمز محاسب
  // ═══════════════════════════════════════════════════════════

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

  static Future<String> _applyAccountantCode(String baseCode) async {
    final acc = await _getAccountantCode();
    if (acc.isEmpty) return baseCode;

    final sep = _getSeparator();
    final pos = _getPosition();

    if (pos == 'prefix') return '$acc$sep$baseCode';
    return '$baseCode$sep$acc';
  }

  // ═══════════════════════════════════════════════════════════
  // التهيئة الأولى (Migration) — مرة واحدة
  // ═══════════════════════════════════════════════════════════

  /// يُستدعى من main.dart عند بدء التطبيق
  ///
  /// - للمستخدمين الجدد: العدّاد = 0 → يبدأ من 1.
  /// - للمستخدمين الحاليين: العدّاد = MAX(used_codes) — لكن فقط إذا كان
  ///   MAX ≤ قدرة الأرقام. وإلا، يبدأ من 1 (لتجاوز العشوائي الكبير).
  static Future<void> migrateCountersIfNeeded() async {
    try {
      final sp = await SharedPreferences.getInstance();
      if (sp.getBool(_keyMigrated) == true) return;

      final digits = await getDigits();
      final maxAttempts = pow(10, digits).toInt();
      final db = DatabaseHelper.instance;

      for (final type in ['debt', 'payment', 'return']) {
        final prefix = await _getPrefixForType(type);
        final maxSeq = await db.getMaxCodeSequence(prefix);

        if (maxSeq > 0 && maxSeq <= maxAttempts) {
          await CodeCounterService.set(type, maxSeq);
          debugPrint('📊 [Code] Migrated $type counter=$maxSeq');
        } else if (maxSeq > maxAttempts) {
          debugPrint(
              '📊 [Code] $type: MAX=$maxSeq > $maxAttempts (skip — start from 1)');
        }
      }

      await sp.setBool(_keyMigrated, true);
    } catch (e) {
      debugPrint('❌ [Code] migrateCounters: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // التوليد
  // ═══════════════════════════════════════════════════════════

  static Future<String?> generateCode(String type) async {
    final enabled = await isEnabled();
    if (!enabled) return null;

    final normalized = normalizeType(type);
    final mode = await getMode();

    if (mode == 'random') {
      return await _generateRandomOnly(normalized);
    }
    return await _generateSequentialOnly(normalized);
  }

  static String _format(String prefix, int number, int digits) {
    return '$prefix-${number.toString().padLeft(digits, '0')}';
  }

  // ═══════════════════════════════════════════════════════════
  // تسلسلي — يستخدم العدّاد المستقل
  // ═══════════════════════════════════════════════════════════

  static Future<String?> _generateSequentialOnly(String type) async {
    final prefix = await _getPrefixForType(type);
    final digits = await getDigits();
    final maxAttempts = pow(10, digits).toInt();

    int counter = await CodeCounterService.get(type);
    if (counter < 0) counter = 0;

    final db = DatabaseHelper.instance;

    // من counter+1 حتى maxAttempts
    for (int seq = counter + 1; seq <= maxAttempts; seq++) {
      final baseCode = _format(prefix, seq, digits);
      final fullCode = await _applyAccountantCode(baseCode);

      if (!await db.codeExists(fullCode)) {
        await CodeCounterService.set(type, seq);
        return fullCode;
      }
      // مستخدم (من وضع عشوائي أو سابق) → تابع
    }

    debugPrint(
        '⚠️ [Code] Exhausted: $type (counter=$counter, max=$maxAttempts)');
    return null;
  }

  // ═══════════════════════════════════════════════════════════
  // عشوائي — لا يمس العدّاد
  // ═══════════════════════════════════════════════════════════

  static Future<String?> _generateRandomOnly(String type) async {
    final prefix = await _getPrefixForType(type);
    final digits = await getDigits();
    final db = DatabaseHelper.instance;
    final random = Random.secure();

    for (int i = 0; i < 100; i++) {
      final minValue = pow(10, digits - 1).toInt();
      final maxValue = pow(10, digits).toInt() - 1;
      final number = minValue + random.nextInt(maxValue - minValue + 1);
      final baseCode = _format(prefix, number, digits);
      final fullCode = await _applyAccountantCode(baseCode);
      if (!await db.codeExists(fullCode)) return fullCode;
    }
    return null;
  }

  // ═══════════════════════════════════════════════════════════
  // معلومات العدّاد
  // ═══════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> getCounterInfo(String type) async {
    final normalized = normalizeType(type);
    final prefix = await _getPrefixForType(normalized);
    final digits = await getDigits();
    final counter = await CodeCounterService.get(normalized);
    final maxAttempts = pow(10, digits).toInt();

    return {
      'type': normalized,
      'counter': counter,
      'max': maxAttempts,
      'remaining': maxAttempts - counter,
      'next_code': _format(prefix, counter + 1, digits),
      'prefix': prefix,
      'digits': digits,
      'is_exhausted': counter >= maxAttempts,
    };
  }

  static Future<Map<String, Map<String, dynamic>>> getAllCountersInfo() async {
    return {
      'debt': await getCounterInfo('debt'),
      'payment': await getCounterInfo('payment'),
      'return': await getCounterInfo('return'),
    };
  }

  // ═══════════════════════════════════════════════════════════
  // التحكم في العدّاد
  // ═══════════════════════════════════════════════════════════

  static Future<void> resetCounter(String type) async {
    await CodeCounterService.reset(normalizeType(type));
    debugPrint('🔄 [Code] Reset counter: $type');
  }

  static Future<void> resetAllCounters() async {
    await CodeCounterService.resetAll();
    debugPrint('🔄 [Code] All counters reset');
  }

  static Future<void> setCounter(String type, int value) async {
    await CodeCounterService.set(normalizeType(type), value);
    debugPrint('⚙️ [Code] Set counter: $type = $value');
  }

  // ═══════════════════════════════════════════════════════════
  // كشف آخر تسلسل من المعاملات (للاستخدام اليدوي)
  // ═══════════════════════════════════════════════════════════

  /// يبحث في آخر N معاملة عن أطول تسلسل متصل من 1
  static Future<int> detectLastSequential({
    required String type,
    int limit = 100,
  }) async {
    final normalized = normalizeType(type);
    final prefix = await _getPrefixForType(normalized);
    final digits = await getDigits();
    final db = DatabaseHelper.instance;

    final transactions = await (await db.database).query(
      'transactions',
      columns: ['code'],
      where: 'code LIKE ?',
      whereArgs: ['$prefix-%'],
      orderBy: 'created_at DESC',
      limit: limit,
    );

    final usedSeqs = <int>{};
    for (final row in transactions) {
      final code = row['code'] as String?;
      if (code == null) continue;
      final seq = _extractSeq(code, prefix, digits);
      if (seq != null) usedSeqs.add(seq);
    }

    // أكبر تسلسل متصل من 1
    int lastContinuous = 0;
    final maxAttempts = pow(10, digits).toInt();
    for (int i = 1; i <= maxAttempts; i++) {
      if (usedSeqs.contains(i)) {
        lastContinuous = i;
      } else {
        break;
      }
    }

    return lastContinuous;
  }

  static int? _extractSeq(String code, String prefix, int digits) {
    final marker = '$prefix-';
    final idx = code.indexOf(marker);
    if (idx == -1) return null;

    final start = idx + marker.length;
    if (start + digits > code.length) return null;

    final digitsPart = code.substring(start, start + digits);
    if (!RegExp(r'^\d+$').hasMatch(digitsPart)) return null;

    return int.tryParse(digitsPart);
  }

  // ═══════════════════════════════════════════════════════════
  // فحص الإتاحة (قبل الحفظ)
  // ═══════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> checkAvailability(String type) async {
    if (!await isEnabled()) {
      return {'available': false, 'reason': 'الترميز معطل'};
    }

    final mode = await getMode();
    if (mode == 'random') {
      return {'available': true, 'mode': 'random'};
    }

    final info = await getCounterInfo(type);
    final counter = info['counter'] as int;
    final max = info['max'] as int;

    if (counter >= max) {
      return {
        'available': false,
        'reason':
            'استنفدت الأرقام المتاحة ($max). زد عدد الأرقام أو أعد تعيين العدّاد.',
        'counter': counter,
        'max': max,
      };
    }

    return {
      'available': true,
      'mode': 'sequential',
      'counter': counter,
      'max': max,
      'remaining': max - counter,
    };
  }

  // ═══════════════════════════════════════════════════════════
  // أدوات قديمة (تحديث الرموز)
  // ═══════════════════════════════════════════════════════════

  static Future<int> updateOldCodes({
    required String oldPrefix,
    required String newPrefix,
  }) async {
    if (oldPrefix.isEmpty || newPrefix.isEmpty) return 0;
    if (oldPrefix == newPrefix) return 0;
    return DatabaseHelper.instance.updateCodesPrefix(
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

// Code Service v1: التوليد الأساسي + بادئات مخصصة
// Code Service v2: إضافة رمز المحاسب + updateOldCodes
// Code Service v2.1: Fix P1-12 (10→100 tries)
// Code Service v3: إعادة تصميم كاملة — العدّاد مستقل عن العشوائي + كشف الاستنفاد + detectLastSequential
