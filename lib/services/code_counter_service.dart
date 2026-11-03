import 'package:shared_preferences/shared_preferences.dart';

/// عدادات التسلسل المستقلة
///
/// - كل نوع (debt/payment/return) له عدّاد مستقل.
/// - لا يتأثر بالوضع العشوائي.
/// - مخزّن في SharedPreferences (وليس used_codes).
class CodeCounterService {
  static const String _keyPrefix = 'code_seq_counter_';

  // ═══════════════════════════════════════════════════════════
  // قراءة
  // ═══════════════════════════════════════════════════════════

  static Future<int> get(String type) async {
    final sp = await SharedPreferences.getInstance();
    return sp.getInt('$_keyPrefix$type') ?? 0;
  }

  static Future<Map<String, int>> getAll() async {
    return {
      'debt': await get('debt'),
      'payment': await get('payment'),
      'return': await get('return'),
    };
  }

  // ═══════════════════════════════════════════════════════════
  // كتابة
  // ═══════════════════════════════════════════════════════════

  static Future<void> set(String type, int value) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setInt('$_keyPrefix$type', value);
  }

  // ═══════════════════════════════════════════════════════════
  // إعادة تعيين
  // ═══════════════════════════════════════════════════════════

  static Future<void> reset(String type) async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove('$_keyPrefix$type');
  }

  static Future<void> resetAll() async {
    for (final t in ['debt', 'payment', 'return']) {
      await reset(t);
    }
  }
}

// Code Counter Service v1: عدادات تسلسل مستقلة (per type) — لا تتأثر بالوضع العشوائي
