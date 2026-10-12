import 'keywords_service.dart';

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
  /// حذف التشكيل من النص (للتحليل فقط)
  static String _stripTashkeel(String text) {
    return text
        .replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '')
        .replaceAll('\u0640', '');
  }

  static ParsedEntry? parse(String text) {
    final original = text.trim();
    if (original.isEmpty) return null;

    // نظّف النص من التشكيل للتحليل
    final clean = _stripTashkeel(original);
    final t = clean.toLowerCase();

    // ========== نية إضافة حساب ==========
    final addAccountMatch = _detectAddAccountIntent(t, clean);
    if (addAccountMatch != null) return addAccountMatch;

    // ========== تحديد نوع المعاملة ==========
    String intent = 'debt';
    String? warning;

    // 🆕 نستخدم KeywordsService بدلاً من const
    final returnKeywords = KeywordsService.get(KeywordsService.catReturn);
    final debtKeywords = KeywordsService.get(KeywordsService.catDebt);
    final paymentKeywords = KeywordsService.get(KeywordsService.catPayment);

    // فحص المرتجع أولاً (لأنه خاص)
    if (_containsAny(t, returnKeywords)) {
      intent = 'return';
    }
    // فحص الدين
    else if (_containsAny(t, debtKeywords)) {
      intent = 'debt';
    }
    // فحص السداد (مع استثناء "دفع لـ")
    else if (_containsAny(t, ['دفع']) && !t.contains('دفع ل')) {
      intent = 'payment';
    }
    // فحص "وصل من" و "استلمت"
    else if (_containsAny(t, ['وصل من', 'وصلني', 'استلمت', 'استلم'])) {
      intent = 'payment';
    }
    // فحص "وصل" (مع تحذير)
    else if (_containsAny(t, ['وصل'])) {
      intent = 'payment';
      if (t.contains('وصل ل')) {
        warning = '⚠️ "وصل لـ" غامضة. استخدم "دفع محمد 500" للسداد '
            'أو "سجل على محمد 500" للدين.';
      }
    }
    // فحص بقية كلمات السداد
    else if (_containsAny(t, paymentKeywords)) {
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

  // ═══════════════════════════════════════════════════════════
  // 🆕 أدوات مساعدة للبحث في قوائم الكلمات
  // ═══════════════════════════════════════════════════════════
  static bool _containsAny(String text, List<String> keywords) {
    for (final kw in keywords) {
      if (text.contains(kw.toLowerCase())) return true;
    }
    return false;
  }

  // ============================================================
  // استخراج الاسم + المبلغ
  // ============================================================
  static _NameAmount? _extractNameAndAmount(String text) {
    // 🆕 نستخدم كلمات KeywordsService
    final debtKw = KeywordsService.get(KeywordsService.catDebt);
    final paymentKw = KeywordsService.get(KeywordsService.catPayment);
    final returnKw = KeywordsService.get(KeywordsService.catReturn);

    // دمج كل الكلمات (مع كلمات إضافية)
    final keywords = <String>{
      ...debtKw,
      ...paymentKw,
      ...returnKw,
      'على', 'عليه', 'عليها',
    }.toList();

    // ترتيب من الأطول للأقصر (لتجنب "سجل" قبل "سجل على")
    keywords.sort((a, b) => b.length.compareTo(a.length));

    for (final kw in keywords) {
      final idx = text.toLowerCase().indexOf(kw.toLowerCase());
      if (idx == -1) continue;

      final after = text.substring(idx + kw.length).trim();
      if (after.isEmpty) continue;

      final words = after.split(RegExp(r'\s+'));

      final nameParts = <String>[];
      double? amount;

      for (final w in words) {
        final cleaned = w.replaceAll(RegExp(r'[،,.!؟?:;]+$'), '');
        if (cleaned.isEmpty) continue;

        final num = _tryParseNumber(cleaned);
        if (num != null) {
          amount = num;
          break;
        }

        final wordNum = _tryParseWordNumber(cleaned);
        if (wordNum != null) {
          amount = wordNum;
          break;
        }

        if (_isStopWord(cleaned)) break;

        nameParts.add(cleaned);
      }

      if (nameParts.isEmpty || amount == null) continue;

      final name = _cleanName(nameParts.join(' '));
      if (name.isEmpty) continue;

      return _NameAmount(name, amount);
    }

    return null;
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

  static ParsedEntry? _detectAddAccountIntent(String t, String original) {
    // 🆕 نستخدم KeywordsService
    final addAccountKeywords =
        KeywordsService.get(KeywordsService.catAddAccount);

    // فحص فعلي: هل يحتوي على فعل إضافة + كلمة "حساب" أو "عميل"؟
    const hasAccountWords = [
      'حساب', 'عميل', 'مورد', 'أخرى', 'اخرى',
      'account', 'customer', 'supplier',
    ];

    final hasAddVerb = _containsAny(t, addAccountKeywords);
    if (!hasAddVerb) return null;

    final hasAccountWord = hasAccountWords.any((w) => t.contains(w));
    if (!hasAccountWord) return null;

    String accountType = 'customer';
    if (t.contains('مورد') || t.contains('supplier')) {
      accountType = 'supplier';
    } else if (t.contains('أخرى') ||
        t.contains('اخرى') ||
        t.contains('other')) {
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

        final digitMatch = RegExp(r'\d').firstMatch(name);
        if (digitMatch != null) {
          name = name.substring(0, digitMatch.start).trim();
        }

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

  static String _cleanName(String name) {
    var n = name.trim();
    n = n.replaceAll(RegExp(r'^[،,.!؟?:;\s]+'), '');
    n = n.replaceAll(RegExp(r'[،,.!؟?:;\s]+$'), '');

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

  static String _extractCurrency(String t) {
    if (t.contains('دولار') || t.contains('dollar')) return 'USD';
    if (t.contains('سعودي') || t.contains('sar')) return 'SAR';
    if (t.contains('درهم') || t.contains('aed')) return 'AED';
    return 'YER';
  }

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
