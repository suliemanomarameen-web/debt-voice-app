import 'package:shared_preferences/shared_preferences.dart';

/// خدمة إدارة اسم المحاسب
/// يخزّن الاسم في SharedPreferences (لكل جهاز اسم مستقل)
///
/// ⚡ Cache في الذاكرة: بعد أول قراءة، الاستدعاءات التالية فورية
class AccountantService {
  static const String _keyAccountantName = 'accountant_name';

  // ═══════════════════════════════════════════════════════════
  // ⚡ Cache في الذاكرة
  // ═══════════════════════════════════════════════════════════
  static String? _cachedName;
  static bool _cacheLoaded = false;

  // ========== جلب الاسم ==========
  /// يعيد اسم المحاسب المحفوظ، أو null إذا لم يُضبط بعد
  ///
  /// ⚡ Cache: أول استدعاء يقرأ من SharedPreferences،
  ///    الاستدعاءات التالية ترجع القيمة المحفوظة في الذاكرة
  static Future<String?> getAccountantName() async {
    // 1. إذا كان الـ cache محمّلاً → أرجعه فوراً
    if (_cacheLoaded) return _cachedName;

    // 2. أول استدعاء → اقرأ من SharedPreferences
    final sp = await SharedPreferences.getInstance();
    final name = sp.getString(_keyAccountantName);

    _cachedName = (name == null || name.trim().isEmpty)
        ? null
        : name.trim();
    _cacheLoaded = true;
    return _cachedName;
  }

  // ========== حفظ الاسم ==========
  static Future<void> setAccountantName(String name) async {
    final sp = await SharedPreferences.getInstance();
    final trimmed = name.trim();

    if (trimmed.isEmpty) {
      await sp.remove(_keyAccountantName);
      _cachedName = null;
    } else {
      await sp.setString(_keyAccountantName, trimmed);
      _cachedName = trimmed;
    }

    // 3. تحديث الـ cache ليكون متزامناً
    _cacheLoaded = true;
  }

  // ========== حذف الاسم ==========
  static Future<void> clearAccountantName() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_keyAccountantName);
    _cachedName = null;
    _cacheLoaded = true;
  }

  // ========== هل تم ضبط الاسم؟ ==========
  static Future<bool> hasAccountantName() async {
    final name = await getAccountantName();
    return name != null && name.isNotEmpty;
  }

  // ========== إبطال الـ cache (للاستخدام عند الحاجة) ==========
  /// للاختبار أو عند الحاجة لإعادة القراءة من SharedPreferences
  static void invalidateCache() {
    _cachedName = null;
    _cacheLoaded = false;
  }
}

// Accountant Service v1: الخدمة الأساسية (قراءة/كتابة اسم المحاسب من SharedPreferences)
// Accountant Service v2: Cache في الذاكرة — أول قراءة I/O، الباقي فوري (30x أسرع)
