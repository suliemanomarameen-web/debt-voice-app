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
  /// حذف التشكيل العربي من النص
  /// مثال: "سَجَّلَ عَلَى مُحَمَّد" → "سجل على محمد"
  static String stripTashkeel(String text) {
    // نطاق التشكيل العربي: U+064B إلى U+065F + U+0670
    return text
        .replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '')
        .replaceAll('\u0640', ''); // تطويل
  }

  static ParsedEntry? parse(String text) {
    final original = text.trim();
    if (original.isEmpty) return null;

    // ⚠️ المفتاح: نحذف التشكيل من النص للتحليل
    final clean = stripTashkeel(original);
    final t = clean.toLowerCase();

    // ========== نية إضافة حساب ==========
    final addAccountMatch = _detectAddAccountIntent(t, clean);
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

    // ========== استخراج الاسم والمبلغ ==========
    final extracted = _extractNameAndAmount(clean);
    if (extracted == null) return null;

    final currency = _extractCurrency(t);
    final items = _extractItemsAfterAmount(clean);

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
  // استخراج الاسم + المبلغ
  // ============================================================
  static _NameAmount? _extractNameAndAmount(String text) {
    // الكلمات المفتاحية (بدون تشكيل)
    const keywords = [
      'سجل على', 'سجل ل', 'سجل',
      'وصل من', 'وصل ل', 'وصل',
      'دفع من', 'دفع ل', 'دفع',
      'سدد', 'استلمت', 'استلم',
      'مرتجع من', 'مرتجع ل', 'مرتجع',
      'على', 'عليه', 'عليها',
    ];

    // الأطول أولاً
    final sorted = List<String>.from(keywords)
      ..sort((a, b) => b.length.compareTo(a.length));

    int bestStart = -1;
    int bestLen = 0;

    for (final kw in sorted) {
      final idx = text.toLowerCase().indexOf(kw.toLowerCase());
      if (idx != -1) {
        bestStart = idx;
        bestLen = kw.length;
        break;
      }
    }

    if (bestStart == -1) return null;

    final after = text.substring(bestStart + bestLen).trim();
    if (after.isEmpty) return null;

    final words = after.split(RegExp(r'\s+'));

    final nameParts = <String>[];
    double? amount;

    for (final raw in words) {
      final w = raw.replaceAll(RegExp(r'[،,.!؟?:;]+$'), '');
      if (w.isEmpty) continue;

      // هل هي رقم؟
      final num = _tryParseNumber(w);
      if (num != null) {
        amount = num;
        break;
      }

      // هل هي كلمة رقمية؟
      final wordNum = _tryParseWordNumber(w);
      if (wordNum != null) {
        amount = wordNum;
        break;
      }

      // هل هي كلمة توقف؟
      if (_isStopWord(w)) break;

      nameParts.add(w);
    }

    if (nameParts.isEmpty || amount == null) return null;

    final name = nameParts.join(' ').trim();
    if (name.isEmpty) return null;

    return _NameAmount(name, amount);
  }

  static double? _tryParseNumber(String w) {
    final normalized = w
        .replaceAll('٠', '0').replaceAll('١', '1').replaceAll('٢', '2')
        .replaceAll('٣', '3').replaceAll('٤', '4').replaceAll('٥', '5')
        .replaceAll('٦', '6').replaceAll('٧', '7').replaceAll('٨', '8')
        .replaceAll('٩', '9');

    final m = RegExp(r'^(\d+(?:[.,]\d+)?)$').firstMatch(normalized);
    if (m != null) {
      return double.tryParse(m.group(1)!.replaceAll(',', ''));
    }
    return null;
  }

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
      'أضف', 'اضف', 'أضيف', 'اضيف',
      'أنشئ', 'انشئ',
      'سجل حساب', 'افتح حساب',
      'انشاء حساب', 'إنشاء حساب',
    ];

    final hasAddVerb = addVerbs.any((v) => t.contains(v));
    if (!hasAddVerb) return null;

    final hasAccountWord = t.contains('حساب') ||
        t.contains('عميل') ||
        t.contains('مورد') ||
        t.contains('أخرى') ||
        t.contains('اخرى');

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

  // ============ كلمات توقف ============
  static bool _isStopWord(String w) {
    const stops = [
      'دين', 'سداد', 'مرتجع', 'دفع', 'وصل', 'سجل',
      'استلم', 'استلمت', 'سدد',
      'على', 'من', 'إلى', 'في', 'عن', 'مع', 'و', 'أو', 'ثم',
      'عليه', 'عليها', 'له', 'لها',
      'أصناف', 'الأصناف', 'اصناف', 'items',
      'ريال', 'دولار', 'درهم', 'سعودي',
      'yer', 'usd', 'sar', 'aed',
    ];
    return stops.contains(w.toLowerCase());
  }

  static String _extractCurrency(String t) {
    if (t.contains('دولار') || t.contains('dollar')) return 'USD';
    if (t.contains('سعودي') || t.contains('sar')) return 'SAR';
    if (t.contains('درهم') || t.contains('aed')) return 'AED';
    return 'YER';
  }

  // ============ استخراج الأصناف ============
  static String _extractItemsAfterAmount(String text) {
    final digitMatch = RegExp(r'\d+').firstMatch(text);
    if (digitMatch == null) return '';

    var after = text.substring(digitMatch.end).trim();

    after = after.replaceFirst(
        RegExp(r'^(?:ريال|دولار|درهم|سعودي|riyal|dollar|sar|aed|yer)\s*'),
        '');

    after = after.replaceFirst(
        RegExp(r'^(?:أصناف|الأصناف|اصناف|items)[:\s]*'),
        '');

    after = after.replaceAll(RegExp(r'^[،,.!؟?:;\s]+'), '');

    return after.trim();
  }
}

class _NameAmount {
  final String name;
  final double amount;
  _NameAmount(this.name, this.amount);
}
