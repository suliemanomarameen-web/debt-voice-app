import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// خدمة الكلمات المفتاحية القابلة للتعديل
/// تُخزّن في SharedPreferences وتُحمّل عند البدء
class KeywordsService {
  // ═══════════════════════════════════════════════════════════
  // الفئات (Category Keys)
  // ═══════════════════════════════════════════════════════════
  static const String catDebt = 'debt';
  static const String catPayment = 'payment';
  static const String catReturn = 'return';
  static const String catAddAccount = 'add_account';
  static const String catQueryBalance = 'query_balance';
  static const String catQueryStatement = 'query_statement';
  static const String catQueryAll = 'query_all';

  /// كل الفئات بالترتيب
  static const List<String> allCategories = [
    catDebt,
    catPayment,
    catReturn,
    catAddAccount,
    catQueryBalance,
    catQueryStatement,
    catQueryAll,
  ];

  /// الأسماء العربية للعرض
  static const Map<String, String> categoryLabelsAr = {
    catDebt: 'كلمات الدين',
    catPayment: 'كلمات السداد',
    catReturn: 'كلمات المرتجع',
    catAddAccount: 'كلمات إنشاء حساب',
    catQueryBalance: 'كلمات الاستعلام عن رصيد',
    catQueryStatement: 'كلمات طلب كشف حساب',
    catQueryAll: 'كلمات الاستعلام الإجمالي',
  };

  /// الإيموجي لكل فئة
  static const Map<String, String> categoryEmojis = {
    catDebt: '📌',
    catPayment: '💰',
    catReturn: '🔄',
    catAddAccount: '➕',
    catQueryBalance: '❓',
    catQueryStatement: '📄',
    catQueryAll: '📊',
  };

  /// الأوصاف النصية
  static const Map<String, String> categoryDescriptions = {
    catDebt: 'عندما يقول المستخدم إحدى هذه الكلمات، سيُفهم أنها عملية دين',
    catPayment: 'عندما يقول المستخدم إحدى هذه الكلمات، سيُفهم أنها عملية سداد',
    catReturn: 'عندما يقول المستخدم إحدى هذه الكلمات، سيُفهم أنها مرتجع',
    catAddAccount: 'عندما يقول المستخدم إحدى هذه الكلمات، سيُفهم أنه يريد إنشاء حساب',
    catQueryBalance: 'عندما يسأل عن رصيد عميل',
    catQueryStatement: 'عندما يطلب كشف حساب',
    catQueryAll: 'عندما يسأل عن الإجمالي (كل الديون)',
  };

  // ═══════════════════════════════════════════════════════════
  // القيم الافتراضية
  // ═══════════════════════════════════════════════════════════
  static const Map<String, List<String>> _defaults = {
    catDebt: [
      'سجل على', 'سجل ل', 'سجل', 'دين', 'عليه', 'عليها',
      'record for', 'record',
    ],
    catPayment: [
      'دفع من', 'دفع ل', 'دفع', 'وصل من', 'وصل ل', 'وصل',
      'استلمت', 'استلم', 'سدد', 'سداد',
      'paid', 'payment',
    ],
    catReturn: [
      'مرتجع', 'رجع',
    ],
    catAddAccount: [
      'أضف حساب', 'اضف حساب', 'أضف عميل', 'اضف عميل',
      'أنشئ حساب', 'انشئ حساب', 'افتح حساب',
      'انشاء حساب', 'إنشاء حساب',
      'create account', 'add account',
    ],
    catQueryBalance: [
      'كم عنده', 'كم عندها', 'كم عند',
      'كم عليه', 'كم عليها',
      'كم له', 'كم لها',
      'كم باقي', 'كم باقي له', 'كم باقي عليها',
      'ماذا معه', 'ماذا معها', 'ماذا مع',
      'معه كم', 'معها كم',
      'how much', 'what does',
    ],
    catQueryStatement: [
      'كشف حساب', 'رصيد',
    ],
    catQueryAll: [
      'كل الحسابات', 'كل الديون', 'إجمالي', 'اجمالي', 'المجموع',
    ],
  };

  /// البادئة في SharedPreferences
  static const String _keyPrefix = 'kw_';

  // ═══════════════════════════════════════════════════════════
  // Cache في الذاكرة
  // ═══════════════════════════════════════════════════════════
  static Map<String, List<String>> _cache = {};
  static bool _loaded = false;

  // ═══════════════════════════════════════════════════════════
  // التهيئة
  // ═══════════════════════════════════════════════════════════
  /// يُستدعى من main() مرة واحدة عند بدء التطبيق
  static Future<void> init() async {
    if (_loaded) return;
    await reload();
  }

  /// إعادة تحميل الكلمات من SharedPreferences
  static Future<void> reload() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final result = <String, List<String>>{};

      for (final cat in allCategories) {
        final stored = sp.getString('$_keyPrefix$cat');
        if (stored == null || stored.isEmpty) {
          // لم تُعدّل بعد → الافتراضي
          result[cat] = List<String>.from(_defaults[cat] ?? []);
        } else {
          // مُعدّلة → نُقسّمها
          result[cat] = stored
              .split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList();
        }
      }

      _cache = result;
      _loaded = true;
      debugPrint('✅ [Keywords] Loaded ${_cache.length} categories');
    } catch (e) {
      debugPrint('❌ [Keywords] reload error: $e');
      // fallback للافتراضي
      _cache = {
        for (final entry in _defaults.entries)
          entry.key: List<String>.from(entry.value)
      };
      _loaded = true;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // القراءة
  // ═══════════════════════════════════════════════════════════
  /// جلب كلمات فئة معينة
  static List<String> get(String category) {
    if (!_loaded) {
      // إذا لم تُحمّل بعد → الافتراضي
      return List<String>.from(_defaults[category] ?? []);
    }
    return List<String>.from(_cache[category] ?? _defaults[category] ?? []);
  }

  /// جلب كل الكلمات لفئة (في Map)
  static Map<String, List<String>> getAll() {
    if (!_loaded) {
      return {
        for (final entry in _defaults.entries)
          entry.key: List<String>.from(entry.value)
      };
    }
    return {
      for (final entry in _cache.entries)
        entry.key: List<String>.from(entry.value)
    };
  }

  /// جلب الكلمات الافتراضية لفئة
  static List<String> getDefaults(String category) {
    return List<String>.from(_defaults[category] ?? []);
  }

  /// جلب كل الكلمات الافتراضية
  static Map<String, List<String>> getAllDefaults() {
    return {
      for (final entry in _defaults.entries)
        entry.key: List<String>.from(entry.value)
    };
  }

  /// هل الفئة معدّلة عن الافتراضي؟
  static bool isModified(String category) {
    final current = get(category);
    final def = getDefaults(category);
    if (current.length != def.length) return true;
    for (int i = 0; i < current.length; i++) {
      if (current[i] != def[i]) return true;
    }
    return false;
  }

  /// هل هناك أي تعديل في أي فئة؟
  static bool hasAnyModification() {
    for (final cat in allCategories) {
      if (isModified(cat)) return true;
    }
    return false;
  }

  // ═══════════════════════════════════════════════════════════
  // الكتابة
  // ═══════════════════════════════════════════════════════════
  /// حفظ كلمات فئة معينة
  static Future<void> set(String category, List<String> keywords) async {
    try {
      // تنظيف
      final cleaned = keywords
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList(); // إزالة التكرار

      final sp = await SharedPreferences.getInstance();
      await sp.setString('$_keyPrefix$category', cleaned.join(','));

      // تحديث الـ cache
      _cache[category] = cleaned;
      debugPrint('✅ [Keywords] Saved ${cleaned.length} words for "$category"');
    } catch (e) {
      debugPrint('❌ [Keywords] set error: $e');
    }
  }

  /// إضافة كلمة واحدة
  static Future<void> add(String category, String keyword) async {
    final current = get(category);
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) return;
    if (current.contains(trimmed)) return;
    current.add(trimmed);
    await set(category, current);
  }

  /// حذف كلمة واحدة
  static Future<void> remove(String category, String keyword) async {
    final current = get(category);
    current.remove(keyword);
    await set(category, current);
  }

  /// استعادة الافتراضي لفئة
  static Future<void> reset(String category) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove('$_keyPrefix$category');
      _cache[category] = List<String>.from(_defaults[category] ?? []);
      debugPrint('✅ [Keywords] Reset "$category" to defaults');
    } catch (e) {
      debugPrint('❌ [Keywords] reset error: $e');
    }
  }

  /// استعادة كل الفئات للافتراضي
  static Future<void> resetAll() async {
    try {
      final sp = await SharedPreferences.getInstance();
      for (final cat in allCategories) {
        await sp.remove('$_keyPrefix$cat');
      }
      await reload();
      debugPrint('✅ [Keywords] Reset ALL to defaults');
    } catch (e) {
      debugPrint('❌ [Keywords] resetAll error: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // أدوات مساعدة
  // ═══════════════════════════════════════════════════════════

  /// فحص سريع: هل النص يحتوي على أي كلمة من فئة معينة؟
  static bool contains(String text, String category) {
    final lower = text.toLowerCase().trim();
    for (final kw in get(category)) {
      if (lower.contains(kw.toLowerCase())) return true;
    }
    return false;
  }

  /// إيجاد أطول كلمة مطابقة (مفيد لتحديد نوع العملية)
  static String? findLongestMatch(String text, String category) {
    final lower = text.toLowerCase().trim();
    String? best;
    for (final kw in get(category)) {
      final kwLower = kw.toLowerCase();
      if (lower.contains(kwLower)) {
        if (best == null || kw.length > best.length) {
          best = kw;
        }
      }
    }
    return best;
  }

  /// عدد الكلمات الكلي
  static int totalCount() {
    int total = 0;
    for (final cat in allCategories) {
      total += get(cat).length;
    }
    return total;
  }
}
