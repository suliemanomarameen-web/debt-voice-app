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

    // ========== نية إضافة حساب ==========
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

    // ========== استخراج الاسم والمبلغ معاً ==========
    final extracted = _extractNameAndAmount(original);
    if (extracted == null) return null;

    final currency = _extractCurrency(t);
    final items = _extractItemsAfterAmount(original);

    return ParsedEntry(
      intent: intent,
      customerName: extracted.name,
      amount: extracted.amount,
      currency: currency,
      accountType: 'customer',
      items: items,
      rawText: original,
      warning: warning,
    );
  }

  // ============================================================
  // استخراج الاسم + المبلغ (الاسم حتى الوصول لرقم)
  // ============================================================
  static _NameAmount? _extractNameAndAmount(String text) {
    // قائمة الكلمات المفتاحية التي تسبق الاسم
    const keywords = [
      'سجل على', 'سجل ل', 'سجل',
      'وصل من', 'وصل ل', 'وصل',
      'دفع من', 'دفع ل', 'دفع',
      'سدد', 'استلمت', 'استلم',
      'مرتجع من', 'مرتجع ل', 'مرتجع',
      'على', 'عليه', 'عليها',
      'record for', 'record',
    ];

    // حاول مع كل كلمة مفتاحية، الأطول أولاً
    final sortedKeywords = List<String>.from(keywords)
      ..sort((a, b) => b.length.compareTo(a.length));

    for (final kw in sortedKeywords) {
      final idx = text.toLowerCase().indexOf(kw.toLowerCase());
      if (idx == -1) continue;

      // ما بعد الكلمة المفتاحية
      final after = text.substring(idx + kw.length).trim();
      if (after.isEmpty) continue;

      // نقسم إلى كلمات
      final words = after.split(RegExp(r'\s+'));

      // اجمع كلمات الاسم حتى نجد رقماً
      final nameParts = <String>[];
      double? amount;
      int amountIndex = -1;

      for (int i = 0; i < words.length; i++) {
        final w = words[i];

        // إزالة علامات الترقيم من نهاية الكلمة
        final cleaned = w.replaceAll(RegExp(r'[،,.!؟?:;]+$'), '');
        if (cleaned.isEmpty) continue;

        // هل هي رقم؟
        final num = _tryParseNumber(cleaned);
        if (num != null) {
          amount = num;
          amountIndex = i;
          break;
        }

        // هل هي كلمة رقمية (ألف، خمس مية، إلخ)؟
        final wordNum = _tryParseWordNumber(cleaned);
        if (wordNum != null) {
          amount = wordNum;
          amountIndex = i;
          break;
        }

        // هل هي كلمة توقف؟
        if (_isStopWord(cleaned)) break;

        // أضفها للاسم
        nameParts.add(cleaned);
      }

      if (nameParts.isEmpty || amount == null) continue;

      final name = _cleanName(nameParts.join(' '));
      if (name.isEmpty) continue;

      return _NameAmount(name, amount);
    }

    return null;
  }

  // ============ محاولة تحويل كلمة إلى رقم ============
  static double? _tryParseNumber(String w) {
    // أرقام عربية → إنجليزية
    final normalized = w
        .replaceAll('٠', '0').replaceAll('١', '1').replaceAll('٢', '2')
        .replaceAll('٣', '3').replaceAll('٤', '4').replaceAll('٥', '5')
        .replaceAll('٦', '6').replaceAll('٧', '7').replaceAll('٨', '8')
        .replaceAll('٩', '9');

    // رقم مباشر؟
    final m = RegExp(r'^(\d+(?:[.,]\d+)?)$').firstMatch(normalized);
    if (m != null) {
      return double.tryParse(m.group(1)!.replaceAll(',', ''));
    }
    return null;
  }

  // ============ كلمات رقمية ============
  static double? _tryParseWordNumber(String w) {
    final lower = w.toLowerCase();
    const map = {
      'ألف': 1000, 'الف': 1000, 'ألفين': 2000, 'الفين': 2000,
      'مليون': 1000000, 'مليونين': 2000000,
      'مائة': 100, 'مئة': 100, 'مية': 100,
      'خمسمية': 500, 'خمسماية': 500,
      'thousand': 1000, 'million': 1000000, 'hundred': 100,
    };
    for (final e in map.entries) {
      if (lower == e.key) return e.value.toDouble();
    }
    return null;
  }

  // ============ كشف نية إضافة حساب ============
  static ParsedEntry? _detectAddAccountIntent(String t, String original) {
    const addVerbs = [
      'أضف', 'اضف', 'أضيف', 'اضيف', 'أضيفي',
      'أنشئ', 'انشئ', 'أنشيء', 'انشيء',
      'سجل حساب', 'افتح حساب', 'افتحي حساب',
      'انشاء حساب', 'إنشاء حساب',
      'create account', 'add account',
    ];

    final hasAddVerb = addVerbs.any((v) => t.contains(v));
    if (!hasAddVerb) return null;

    final hasAccountWord = t.contains('حساب') ||
        t.contains('عميل') ||
        t.contains('مورد') ||
        t.contains('أخرى') ||
        t.contains('اخرى') ||
        t.contains('account') ||
        t.contains('customer') ||
        t.contains('supplier');

    if (!hasAccountWord) return null;

    String accountType = 'customer';
    if (t.contains('مورد') || t.contains('supplier')) {
      accountType = 'supplier';
    } else if (t.contains('أخرى') || t.contains('اخرى') || t.contains('other')) {
      accountType = 'other';
    }

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
    final patterns = [
      RegExp(r'باسم\s+(.+)$'),
      RegExp(r'اسمه\s+(.+)$'),
      RegExp(r'حساب\s+(?:عميل|مورد|أخرى|اخرى|جديد|جديدة)?\s*(.+)$'),
      RegExp(r'(?:عميل|مورد)\s+(?:باسم\s+|اسمه\s+)?(.+)$'),
      RegExp(r'(?:أضف|اضف|أضيف|اضيف|أنشئ|انشئ|سجل|افتح)\s+(.+)$'),
    ];

    for (final pattern in patterns) {
      final m = pattern.firstMatch(text);
      if (m != null) {
        var name = m.group(1)!.trim();

        // اقتطع عند أول رقم
        final digitMatch = RegExp(r'\d').firstMatch(name);
        if (digitMatch != null) {
          name = name.substring(0, digitMatch.start).trim();
        }

        // اقتطع عند أول عملة
        for (final curr in ['ريال', 'دولار', 'درهم', 'سعودي']) {
          final ci = name.indexOf(curr);
          if (ci > 0) name = name.substring(0, ci).trim();
        }

        // إزالة الكلمات المفتاحية العالقة
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
      'باسم', 'اسمه', 'account', 'customer', 'supplier',
    ];
    return bad.contains(name.toLowerCase());
  }

  // ============ تنظيف الاسم ============
  static String _cleanName(String name) {
    var n = name.trim();
    // إزالة علامات الترقيم من البداية والنهاية
    n = n.replaceAll(RegExp(r'^[،,.!؟?:;\s]+'), '');
    n = n.replaceAll(RegExp(r'[،,.!؟?:;\s]+$'), '');

    // إزالة "لـ" من البداية
    if (n.startsWith('لـ')) n = n.substring(2);
    else if (n.startsWith('ل') && n.length > 2) {
      final rest = n.substring(1);
      const badWords = ['وصل', 'دفع', 'سجل', 'من', 'على'];
      if (!badWords.any((w) => rest.startsWith(w))) {
        n = rest;
      }
    }
    return n.trim();
  }

  static bool _isStopWord(String w) {
    const stops = [
      'دين', 'سداد', 'مرتجع',
      'دفع', 'وصل', 'سجل', 'على', 'من', 'إلى',
      'في', 'عن', 'مع', 'و', 'أو', 'ثم',
      'أصناف', 'الأصناف', 'اصناف', 'items',
      'ريال', 'دولار', 'درهم', 'سعودي',
      'yer', 'usd', 'sar', 'aed',
    ];
    return stops.contains(w.toLowerCase());
  }

  static bool _isKeywordOrCurrency(String w) {
    const keywords = [
      'ريال', 'دولار', 'سعودي', 'درهم', 'yer', 'usd', 'sar', 'aed',
      'وصل', 'دفع', 'سجل', 'على', 'من', 'إلى', 'عليه', 'عليها',
      'و', 'أو', 'ثم', 'في',
    ];
    return keywords.any((k) => w.toLowerCase() == k);
  }

  // ============ العملة ============
  static String _extractCurrency(String t) {
    if (t.contains('دولار') || t.contains('dollar')) return 'USD';
    if (t.contains('سعودي') || t.contains('sar')) return 'SAR';
    if (t.contains('درهم') || t.contains('aed')) return 'AED';
    return 'YER';
  }

  // ============ الأصناف: كل ما بعد المبلغ والعملة ============
  static String _extractItemsAfterAmount(String text) {
    // ابحث عن أول رقم في النص
    final digitMatch = RegExp(r'\d+').firstMatch(text);
    if (digitMatch == null) return '';

    // ما بعد الرقم
    var after = text.substring(digitMatch.end).trim();

    // احذف العملة من البداية إن وُجدت
    after = after.replaceFirst(
        RegExp(r'^(?:ريال|دولار|درهم|سعودي|riyal|dollar|sar|aed|yer)\s*'),
        '');

    // احذف "أصناف" أو "الأصناف" إن وُجدت
    after = after.replaceFirst(
        RegExp(r'^(?:أصناف|الأصناف|اصناف|items)[:\s]*'),
        '');

    // احذف علامات الترقيم
    after = after.replaceAll(RegExp(r'^[،,.!؟?:;\s]+'), '');

    return after.trim();
  }
}

class _NameAmount {
  final String name;
  final double amount;
  _NameAmount(this.name, this.amount);
}
