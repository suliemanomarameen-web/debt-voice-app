import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import '../db/database_helper.dart';

class CodeService {
  // ========== مفاتيح الإعدادات ==========
  static const String _keyDebtPrefix = 'code_debt_prefix';
  static const String _keyPaymentPrefix = 'code_payment_prefix';
  static const String _keyReturnPrefix = 'code_return_prefix';
  static const String _keyDigits = 'code_digits';
  static const String _keyMode = 'code_mode'; // 'sequential' أو 'random'
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
    return getDebtPrefix(); // debt
  }

  // ========== توليد رمز جديد ==========
  /// يولّد رمزاً فريداً للعملية حسب الإعدادات
  /// مثال: D-0001 أو P-482917
  static Future<String?> generateCode(String type) async {
    // إذا كانت الميزة معطلة، لا نولّد رمزاً
    final enabled = await isEnabled();
    if (!enabled) return null;

    final prefix = await _getPrefixForType(type);
    final digits = await getDigits();
    final mode = await getMode();

    // ⚠️ ملاحظة: نوع 'return' يُخزّن في DB كـ 'payment'
    // لكن نستخدم البادئة الخاصة به إذا كان 'return'
    final codeType = type; // نحتفظ بالنوع الأصلي لجدول used_codes

    final db = DatabaseHelper.instance;

    if (mode == 'random') {
      return _generateRandom(db, prefix, digits, codeType);
    } else {
      return _generateSequential(db, prefix, digits, codeType);
    }
  }

  /// توليد مرتب (تسلسلي)
  static Future<String?> _generateSequential(
    DatabaseHelper db,
    String prefix,
    int digits,
    String type,
  ) async {
    // جلب أعلى رقم تسلسلي مستخدم لهذا النوع (حسب البادئة الحالية)
    final maxSeq = await db.getMaxSequence(type);

    // البحث عن أول رقم غير مستخدم بدءاً من maxSeq+1
    final maxAttempts = pow(10, digits).toInt(); // الحد الأقصى للأرقام
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

    // إذا وصلنا هنا، فالمساحة ممتلئة
    // نعيد null مع رسالة تحذير
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
    final maxAttempts = 100; // محاولات البحث عن رقم فريد

    for (int i = 0; i < maxAttempts; i++) {
      // توليد رقم عشوائي بعدد الأرقام المطلوب
      final minValue = pow(10, digits - 1).toInt(); // 1000 لـ 4 أرقام
      final maxValue = pow(10, digits).toInt() - 1; // 9999 لـ 4 أرقام
      final number = minValue + random.nextInt(maxValue - minValue + 1);

      final code = _format(prefix, number, digits);
      final exists = await db.codeExists(code);
      if (!exists) {
        return code;
      }
    }

    // إذا فشل بعد كل المحاولات
    return null;
  }

  /// تنسيق الرمز: PREFIX-NUMBER (مع padding)
  static String _format(String prefix, int number, int digits) {
    final paddedNumber = number.toString().padLeft(digits, '0');
    return '$prefix-$paddedNumber';
  }

  // ========== إحصائيات (للعرض) ==========
  /// عدد العمليات المتوقع حسب عدد الأرقام
  static int getMaxPossible(int digits) {
    // 10^digits - 10^(digits-1) = عدد الأرقام المتاحة
    // مثال: 4 أرقام → 9000 رقم (1000-9999)
    return pow(10, digits).toInt() - pow(10, digits - 1).toInt();
  }

  /// وصف طريقة التوليد
  static String describeMode(String mode) {
    return mode == 'random' ? 'عشوائي' : 'مرتب (تسلسلي)';
  }

  /// وصف عدد الأرقام
  static String describeDigits(int digits) {
    return '$digits أرقام';
  }
}
