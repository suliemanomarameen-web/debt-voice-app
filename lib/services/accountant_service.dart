import 'package:shared_preferences/shared_preferences.dart';

/// خدمة إدارة اسم المحاسب
/// يخزّن الاسم في SharedPreferences (لكل جهاز اسم مستقل)
class AccountantService {
  static const String _keyAccountantName = 'accountant_name';

  // ========== جلب الاسم ==========
  /// يعيد اسم المحاسب المحفوظ، أو null إذا لم يُضبط بعد
  static Future<String?> getAccountantName() async {
    final sp = await SharedPreferences.getInstance();
    final name = sp.getString(_keyAccountantName);
    if (name == null || name.trim().isEmpty) return null;
    return name.trim();
  }

  // ========== حفظ الاسم ==========
  static Future<void> setAccountantName(String name) async {
    final sp = await SharedPreferences.getInstance();
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      await sp.remove(_keyAccountantName);
    } else {
      await sp.setString(_keyAccountantName, trimmed);
    }
  }

  // ========== حذف الاسم ==========
  static Future<void> clearAccountantName() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_keyAccountantName);
  }

  // ========== هل تم ضبط الاسم؟ ==========
  static Future<bool> hasAccountantName() async {
    final name = await getAccountantName();
    return name != null && name.isNotEmpty;
  }
}
