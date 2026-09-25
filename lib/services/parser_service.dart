class ParsedEntry {
  final String intent;
  final String customerName;
  final double amount;
  final String currency;
  final String accountType;
  final String items;
  final String rawText;
  final String? warning;

  ParsedEntry({
    required this.intent,
    required this.customerName,
    required this.amount,
    required this.currency,
    required this.accountType,
    required this.items,
    required this.rawText,
    this.warning,
  });
}

class ParserService {
  static ParsedEntry? parse(String text) {
    final original = text.trim();
    if (original.isEmpty) return null;
    final t = original.toLowerCase();

    // ========== نية إضافة حساب (موسّعة) ==========
    final addAccountMatch = _detectAddAccountIntent(t, original);
    if (addAccountMatch != null) return addAccountMatch;

    // ========== تحديد نوع المعاملة ==========
    String intent = 'debt';
    String? warning;

    if (t.contains('مرتجع') || t.contains('رجع')) {
      intent = 'return';
    } else if (t.contains('سجل') || t.contains('دين') ||
               t.contains('عليه') || t.contains('عليها')) {
      intent = 'debt';
    } else if (t.contains('دفع') && !t.contains('دفع ل')) {
      intent = 'payment';
    } else if (t.contains('وصل من') || t.contains('وصلني') ||
               t.contains('استلمت') || t.contains('استلم')) {
      intent = 'payment';
    } else if (t.contains('وصل')) {
      intent = 'payment';
      if (t.contains('وصل ل')) {
        warning = '⚠️ "وصل لـ" غامضة. استخدم "دفع محمد 500" للسداد '
            'أو "سجل على محمد 500" للدين.';
      }
    } else if (t.contains('سدد') || t.contains('سداد') ||
               t.contains('paid') || t.contains('payment')) {
      intent = 'payment';
    }

    final amount = _extractAmount(t);
    if (amount == null) return null;

    final name = _extractName(original);
    if (name == null) return null;

    final currency = _extractCurrency(t);
    final items = _extractItems(original);

    return ParsedEntry(
      intent: intent,
      customerName: name,
      amount: amount,
      currency: currency,
      accountType: 'customer',
      items: items,
      rawText: original,
      warning: warning,
    );
  }

  // ============ كشف نية إضافة حساب ============
  static ParsedEntry? _detectAddAccountIntent(String t, String original) {
    // قائمة الأفعال التي تعني "إضافة/إنشاء"
    const addVerbs = [
      'أضف', 'اضف', 'أضيف', 'اضيف', 'أضيفي',
      'أنشئ', 'انشئ', 'أنشيء', 'انشيء',
      'سجل', 'افتح', 'افتحي', 'انشاء', 'إنشاء',
      'create', 'add', 'new',
    ];

    // هل الجملة تحتوي على فعل إضافة؟
    final hasAddVerb = addVerbs.any((v) => t.contains(v));
    if (!hasAddVerb) return null;

    // هل تحتوي على كلمة "حساب" أو نوع حساب (عميل/مورد)؟
    final hasAccountWord = t.contains('حساب') ||
        t.contains('عميل') ||
        t.contains('مورد') ||
        t.contains('أخرى') ||
        t.contains('اخرى') ||
        t.contains('account') ||
        t.contains('customer') ||
        t.contains('supplier');

    if (!hasAccountWord) return null;

    // تحديد نوع الحساب
    String accountType = 'customer';
    if (t.contains('مورد') || t.contains('supplier')) {
      accountType = 'supplier';
    } else if (t.contains('أخرى') || t.contains('اخرى') || t.contains('other')) {
      accountType = 'other';
    }

    // استخراج الاسم
    final name = _extractAccountName(original);
    if (name == null || name.isEmpty) return null;

    return ParsedEntry(
      intent: 'add_account',
      customerName: name,
      amount: 0,
      currency: 'YER',
      accountType: accountType,
      items: '',
      rawText: original,
    );
  }

  // ============ استخراج اسم الحساب الجديد ============
  static String? _extractAccountName(String text) {
    // صيغ متعددة:
    // 1) "أضف حساب عميل باسم محمد"
    // 2) "أضف حساب باسم محمد"
    // 3) "أنشئ حساب عميل محمد"
    // 4) "أضف عميل محمد"
    // 5) "أضف مورد أحمد"

    final patterns = [
      // "باسم X" — الأوضح
      RegExp(r'باسم\s+([\u0600-\u06FFa-zA-Z][\u0600-\u06FFa-zA-Z\s]{0,30})$'),
      // "اسمه X"
      RegExp(r'اسمه\s+([\u0600-\u06FFa-zA-Z][\u0600-\u06FFa-zA-Z\s]{0,30})$'),
      // "حساب عميل X" / "حساب مورد X" / "حساب X"
      RegExp(r'حساب\s+(?:عميل|مورد|أخرى|اخرى|جديد|جديدة)?\s*([\u0600-\u06FFa-zA-Z][\u0600-\u06FFa-zA-Z\s]{0,30})$'),
      // "عميل X" / "مورد X"
      RegExp(r'(?:عميل|مورد)\s+(?:باسم\s+|اسمه\s+)?([\u0600-\u06FFa-zA-Z][\u0600-\u06FFa-zA-Z\s]{0,30})$'),
      // "أضف X" (آخر كلمة)
      RegExp(r'(?:أضف|اضف|أضيف|اضيف|أنشئ|انشئ|سجل|افتح)\s+([\u0600-\u06FFa-zA-Z][\u0600-\u06FFa-zA-Z\s]{0,30})$'),
    ];

    for (final pattern in patterns) {
      final m = pattern.firstMatch(text);
      if (m != null) {
        var name = m.group(1)!.trim();
        // إزالة كلمات مفتاحية عالقة
        name = name.replaceAll(RegExp(
            r'^(?:حساب|عميل|مورد|جديد|جديدة|أخرى|اخرى|باسم|اسمه)\s+'),
            '');
        name = name.trim();
        if (name.isNotEmpty && !_isBadName(name)) {
          return name;
        }
      }
    }

    return null;
  }

  static bool _isBadName(String name) {
    const bad = [
      'حساب', 'عميل', 'مورد', 'جديد', 'جديدة', 'أخرى', 'اخرى',
      'باسم', 'اسمه', 'جديد', 'account', 'customer', 'supplier',
    ];
    return bad.contains(name.toLowerCase());
  }

  // ============ تنظيف الاسم ============
  static String _cleanName(String name) {
    var n = name.trim();
    if (n.startsWith('لـ')) n = n.substring(2);
    else if (n.startsWith('ل') && n.length > 1) {
      final rest = n.substring(1);
      const badWords = ['وصل', 'دفع', 'سجل', 'من', 'على'];
      if (!badWords.any((w) => rest.startsWith(w))) {
        n = rest;
      }
    }
    return n.trim();
  }

  // ============ أدوات مساعدة ============
  static String _normalizeDigits(String s) => s
      .replaceAll('٠', '0').replaceAll('١', '1').replaceAll('٢', '2')
      .replaceAll('٣', '3').replaceAll('٤', '4').replaceAll('٥', '5')
      .replaceAll('٦', '6').replaceAll('٧', '7').replaceAll('٨', '8')
      .replaceAll('٩', '9');

  static double? _extractAmount(String t) {
    final normalized = _normalizeDigits(t);
    final m = RegExp(r'(\d+(?:[.,]\d+)?)').firstMatch(normalized);
    if (m != null) {
      final val = double.tryParse(m.group(1)!.replaceAll(',', ''));
      if (val != null) return val;
    }

    final wordMap = {
      'ألف': 1000, 'الف': 1000, 'ألفين': 2000, 'الفين': 2000,
      'مليون': 1000000, 'مليونين': 2000000,
      'مائة': 100, 'مئة': 100, 'مية': 100,
      'خمسمية': 500, 'خمس مية': 500,
      'thousand': 1000, 'million': 1000000, 'hundred': 100,
    };
    for (final e in wordMap.entries) {
      if (t.contains(e.key)) return e.value.toDouble();
    }
    return null;
  }

  static String? _extractName(String text) {
    final patterns = [
      RegExp(
          r'(?:سجل على|سجل ل|سجل|وصل من|وصل ل|وصل|دفع من|دفع ل|دفع|سدد|استلم|استلمت|مرتجع من|مرتجع ل|مرتجع|record for|record)\s+([\u0600-\u06FFa-zA-Z]+)',
          caseSensitive: false),
      RegExp(
          r'(?:على|عليه|عليها)\s+([\u0600-\u06FFa-zA-Z]+)',
          caseSensitive: false),
    ];

    for (final pattern in patterns) {
      final m = pattern.firstMatch(text);
      if (m != null) {
        final candidate = m.group(1)!;
        final cleaned = _cleanName(candidate);
        if (cleaned.isNotEmpty && !_isKeywordOrCurrency(cleaned)) {
          return cleaned;
        }
      }
    }

    final first = RegExp(r'^([\u0600-\u06FFa-zA-Z]+)').firstMatch(text);
    return first != null ? _cleanName(first.group(1)!) : null;
  }

  static bool _isKeywordOrCurrency(String w) {
    const keywords = [
      'ريال', 'دولار', 'سعودي', 'درهم', 'yer', 'usd', 'sar', 'aed',
      'وصل', 'دفع', 'سجل', 'على', 'من', 'إلى', 'عليه', 'عليها',
      'و', 'أو', 'ثم', 'في',
    ];
    return keywords.any((k) => w.toLowerCase() == k);
  }

  static String _extractCurrency(String t) {
    if (t.contains('دولار') || t.contains('dollar')) return 'USD';
    if (t.contains('سعودي') || t.contains('sar')) return 'SAR';
    if (t.contains('درهم') || t.contains('aed')) return 'AED';
    return 'YER';
  }

  static String _extractItems(String text) {
    final itemMatch = RegExp(
      r'(?:أصناف|الأصناف|اصناف|items)[:\s]+(.+)',
      caseSensitive: false,
    ).firstMatch(text);
    if (itemMatch != null) return itemMatch.group(1)!.trim();

    final afterAmount = RegExp(
      r'\d+(?:[.,]\d+)?\s*(?:ريال|دولار|سعودي|درهم|riyal|dollar|sar|aed|yer)?\s+(.+)',
      caseSensitive: false,
    ).firstMatch(text);
    if (afterAmount != null) {
      var items = afterAmount.group(1)!.trim();
      items = items.replaceFirst(
          RegExp(r'^(?:أصناف|الأصناف|اصناف|items)[:\s]+',
              caseSensitive: false), '');
      return items;
    }
    return '';
  }
}
