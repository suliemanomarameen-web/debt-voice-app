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
  
  // إدارة الحساب
  static const String catBlockAccount = 'block_account';
  static const String catUnblockAccount = 'unblock_account';
  static const String catSetLimit = 'set_limit';
  static const String catRemoveLimit = 'remove_limit';
  static const String catProcess = 'process';

  // 🆕 عمليات متقدمة
  static const String catPrintStatement = 'print_statement';
  static const String catSendStatement = 'send_statement';
  static const String catStatistics = 'statistics';
  static const String catLastTransaction = 'last_transaction';
  static const String catSearch = 'search';
  static const String catDeleteCustomer = 'delete_customer';
  static const String catEditCustomer = 'edit_customer';
  static const String catRenameCustomer = 'rename_customer';

  /// كل الفئات بالترتيب
  static const List<String> allCategories = [
    catDebt,
    catPayment,
    catReturn,
    catAddAccount,
    catQueryBalance,
    catQueryStatement,
    catQueryAll,
    catBlockAccount,
    catUnblockAccount,
    catSetLimit,
    catRemoveLimit,
    catProcess,
    catPrintStatement,
    catSendStatement,
    catStatistics,
    catLastTransaction,
    catSearch,
    catDeleteCustomer,
    catEditCustomer,
    catRenameCustomer,
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
    catBlockAccount: 'كلمات إيقاف الحساب',
    catUnblockAccount: 'كلمات تفعيل الحساب',
    catSetLimit: 'كلمات تحديد السقف',
    catRemoveLimit: 'كلمات إلغاء سقف الحساب',
    catProcess: 'كلمات بدء عملية جديدة',
    catPrintStatement: 'كلمات طباعة كشف الحساب',
    catSendStatement: 'كلمات إرسال كشف الحساب',
    catStatistics: 'كلمات الإحصائيات',
    catLastTransaction: 'كلمات آخر عملية',
    catSearch: 'كلمات البحث',
    catDeleteCustomer: 'كلمات حذف حساب',
    catEditCustomer: 'كلمات تعديل حساب',
    catRenameCustomer: 'كلمات تغيير اسم الحساب',
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
    catBlockAccount: '🚫',
    catUnblockAccount: '✅',
    catSetLimit: '📏',
    catRemoveLimit: '🧹',
    catProcess: '⚡',
    catPrintStatement: '🖨️',
    catSendStatement: '📤',
    catStatistics: '📈',
    catLastTransaction: '⏮️',
    catSearch: '🔍',
    catDeleteCustomer: '🗑️',
    catEditCustomer: '✏️',
    catRenameCustomer: '🔤',
    catRenameCustomer: '🔤',
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
    catBlockAccount: 'عندما يطلب إيقاف حساب عميل',
    catUnblockAccount: 'عندما يطلب تفعيل حساب عميل',
    catSetLimit: 'عندما يطلب تحديد سقف رصيد',
    catRemoveLimit: 'عندما يطلب إلغاء أو إزالة سقف الحساب',
    catProcess: 'عندما يطلب بدء عملية (دين/سداد/مرتجع) دون تحديد',
    catPrintStatement: 'عندما يطلب طباعة كشف حساب',
    catSendStatement: 'عندما يطلب إرسال كشف حساب عبر واتساب',
    catStatistics: 'عندما يطلب الإحصائيات أو التقارير',
    catLastTransaction: 'عندما يطلب آخر عملية أو آخر تسجيل',
    catSearch: 'عندما يطلب البحث عن حساب',
    catDeleteCustomer: 'عندما يطلب حذف حساب',
    catEditCustomer: 'عندما يطلب تعديل بيانات حساب',
    catRenameCustomer: 'عندما يطلب تغيير اسم حساب موجود',
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
    catBlockAccount: [
      'أوقف الحساب', 'اوقف الحساب', 'أوقف حساب', 'اوقف حساب',
      'إيقاف الحساب', 'إيقاف حساب', 'وقف الحساب', 'وقف حساب',
      'عطل الحساب', 'عطل حساب',
    ],
    catUnblockAccount: [
      'فعل الحساب', 'فعل حساب', 'فعل هذا الحساب',
      'تفعيل الحساب', 'تفعيل حساب',
      'نشط الحساب', 'نشط حساب', 'شغل الحساب', 'شغل حساب',
    ],
    catSetLimit: [
      'حدد سقف', 'حدد السقف', 'حدد الحد الأقصى', 'حدد الحد الاقصى',
      'سقف الحساب', 'سقف حساب', 'حد أقصى', 'حد اقصى',
    ],
    catRemoveLimit: [
      'إلغاء السقف', 'الغاء السقف', 'إلغاء سقف', 'الغاء سقف',
      'إزالة السقف', 'ازالة السقف', 'احذف السقف', 'حذف السقف',
      'إلغاء الحد الأقصى', 'الغاء الحد الاقصى', 'إزالة الحد الأقصى',
      'ازالة الحد الاقصى', 'بدون سقف', 'إلغاء حد الحساب', 'الغاء حد الحساب',
    ],
    catProcess: [
      'عملية', 'أضف عملية', 'اضف عملية', 'سجل عملية', 'عملية جديدة',
    ],
    catPrintStatement: [
      'طباعة كشف', 'اطبع كشف', 'طباعة حساب', 'اطبع حساب',
      'طباعة', 'اطبع', 'print',
    ],
    catSendStatement: [
      'أرسل كشف', 'ارسل كشف', 'إرسال كشف',
      'أرسل حساب', 'ارسل حساب',
      'واتساب كشف', 'واتساب حساب',
      'send statement', 'share statement',
    ],
    catStatistics: [
      'الإحصائيات', 'الاحصائيات', 'احصائيات', 'إحصائيات',
      'التقارير', 'تقارير', 'إجمالي', 'اجمالي',
      'إجمالي الديون', 'اجمالي الديون',
      'statistics', 'reports',
    ],
    catLastTransaction: [
      'آخر عملية', 'اخر عملية', 'آخر تسجيل', 'اخر تسجيل',
      'آخر حركة', 'اخر حركة', 'آخر معاملة', 'اخر معاملة',
      'last transaction', 'last activity',
    ],
    catSearch: [
      'ابحث عن', 'ابحث', 'دور على', 'بحث عن', 'بحث',
      'وين حساب', 'وين', 'أين حساب', 'أين',
      'search for', 'search',
    ],
    catDeleteCustomer: [
      'احذف حساب', 'احذف الحساب', 'حذف حساب', 'حذف الحساب',
      'امسح حساب', 'امسح الحساب', 'مسح حساب', 'مسح الحساب',
      'delete customer', 'delete account',
    ],
    catRenameCustomer: [
      'غير اسم الحساب', 'غيّر اسم الحساب', 'غير اسم حساب', 'غيّر اسم حساب',
      'تغيير اسم الحساب', 'تغيير اسم حساب', 'بدل اسم الحساب', 'بدّل اسم الحساب',
      'استبدل اسم الحساب', 'تعديل اسم الحساب', 'غير اسم العميل', 'تغيير اسم العميل',
    ],
    catEditCustomer: [
      'عدل حساب', 'عدل الحساب', 'تعديل حساب', 'تعديل الحساب',
      'غير الرقم', 'غير رقم', 'غير الاسم', 'غير اسم',
      'تعديل رقم', 'تعديل الاسم',
      'edit customer', 'update customer',
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

// Keywords Service v1: الكلمات المفتاحية القابلة للتعديل (7 فئات)
// Keywords Service v2: إضافة كلمات إدارة الحساب (إيقاف، تفعيل، سقف، عملية)
// Keywords Service v3: إضافة كلمات متقدمة
// - print_statement (طباعة كشف حساب)
// - send_statement (إرسال كشف عبر واتساب)
// - statistics (الإحصائيات والتقارير)
// - last_transaction (آخر عملية)
// - search (البحث عن حساب)
// - delete_customer (حذف حساب)
// - edit_customer (تعديل حساب)
// - المجموع: 18 فئة
