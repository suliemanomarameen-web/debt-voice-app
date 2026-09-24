class ParsedEntry {
  final String customerName;
  final double amount;
  final String currency;
  final String type;        // 'debt' أو 'payment'
  final String items;       // الأصناف
  final String rawText;

  ParsedEntry({
    required this.customerName,
    required this.amount,
    required this.currency,
    required this.type,
    required this.items,
    required this.rawText,
  });
}

class ParserService {
  /// كلمات مفتاحية للسداد (إن وُجدت، العملية سداد)
  static const List<String> paymentKeywords = [
    'وصل', 'دفع', 'سدد', 'سداد', 'استلم', 'أعطى', 'أعطاني',
    'paid', 'payment', 'received',
  ];

  /// كلمات مفتاحية للأصناف
  static const List<String> itemsKeywords = [
    'أصناف', 'اصناف', 'بضاعة', 'بضاعه', 'منتجات', 'منتجع',
  ];

  /// عملات معروفة
  static const Map<String, String> currencyMap = {
    'ريال': 'YER', 'ريال يمني': 'YER', 'يمني': 'YER',
    'دولار': 'USD', 'دولار أمريكي': 'USD',
    'سعودي': 'SAR', 'ريال سعودي': 'SAR',
    'درهم': 'AED', 'إماراتي': 'AED',
    'ريال عماني': 'OMR',
    'دينار': 'KWD',
    'جنيه': 'EGP',
    'يورو': 'EUR',
    'riyal': 'YER', 'dollar': 'USD', 'sar': 'SAR', 'aed': 'AED',
  };

  /// الكلمات الرقمية العربية
  static const Map<String, double> wordNumbers = {
    'ألف': 1000, 'الف': 1000, 'ألفان': 2000, 'ألفين': 2000,
    'ثلاث': 3, 'أربع': 4, 'خمس': 5, 'ست': 6, 'سبع': 7, 'ثمان': 8, 'تسع': 9, 'عشر': 10,
    'عشرين': 20, 'ثلاثين': 30, 'أربعين': 40, 'خمسين': 50, 'ستين': 60,
    'سبعين': 70, 'ثمانين': 80, 'تسعين': 90,
    'مائة': 100, 'مئة': 100, 'مية': 100,
    'مليون': 1000000, 'مليونين': 2000000,
  };

  /// ================= المحلل الرئيسي =================
  static ParsedEntry? parse(String text) {
    final original = text.trim();
    if (original.isEmpty) return null;

    // 1) تحديد النوع (دين أم سداد)
    String type = 'debt';
    final lower = original.toLowerCase();
    for (final kw in paymentKeywords) {
      if (lower.contains(kw.toLowerCase())) {
        type = 'payment';
        break;
      }
    }

    // 2) استخراج المبلغ
    final amount = _extractAmount(original);
    if (amount == null || amount <= 0) return null;

    // 3) استخراج الاسم
    final name = _extractName(original);
    if (name == null || name.isEmpty) return null;

    // 4) استخراج العملة
    final currency = _extractCurrency(original);

    // 5) استخراج الأصناف
    final items = _extractItems(original);

    return ParsedEntry(
      customerName: name,
      amount: amount,
      currency: currency,
      type: type,
      items: items,
      rawText: original,
    );
  }

  /// ============ استخراج المبلغ ============
  static double? _extractAmount(String text) {
    // أولاً: أرقام عربية → إنجليزية
    String normalized = _normalizeDigits(text);

    // ابحث عن أرقام مباشرة
    final m = RegExp(r'(\d+(?:[.,]\d+)?)').firstMatch(normalized);
    if (m != null) {
      final amount = double.tryParse(m.group(1)!.replaceAll(',', ''));
      if (amount != null && amount > 0) return amount;
    }

    // ثانياً: أرقام مكتوبة بكلمات
    for (final entry in wordNumbers.entries) {
      if (normalized.contains(entry.key)) {
        // ابحث عن رقم قبل الكلمة (مثل "خمس ألف" = 5000)
        final idx = normalized.indexOf(entry.key);
        final before = normalized.substring(0, idx).trim();
        final lastNum = RegExp(r'(\d+)\s*$').firstMatch(before);
        if (lastNum != null) {
          final base = double.tryParse(lastNum.group(1)!) ?? 1;
          return base * entry.value;
        }
        return entry.value;
      }
    }

    return null;
  }

  /// ============ استخراج الاسم ============
  static String? _extractName(String text) {
    // نبحث عن نمط: (سجل|على|ل|دفع|وصل) (اسم)
    final patterns = [
      RegExp(r'على\s+([\u0600-\u06FF]+(?:\s+[\u0600-\u06FF]+)?)'),
      RegExp(r'ل\s+([\u0600-\u06FF]+)'),
      RegExp(r'لـ\s+([\u0600-\u06FF]+)'),
      RegExp(r'سجل\s+([\u0600-\u06FF]+)'),
      RegExp(r'دفع\s+([\u0600-\u06FF]+)'),
      RegExp(r'وصل\s+([\u0600-\u06FF]+)'),
    ];

    for (final p in patterns) {
      final m = p.firstMatch(text);
      if (m != null) {
        var name = m.group(1)!.trim();
        // احذف الكلمات الزائدة
        name = name.split(' ').where((w) =>
          !_isKeyword(w) && !_isCurrencyWord(w)
        ).join(' ');
        if (name.isNotEmpty) return name;
      }
    }

    // احتياطي: أول كلمة عربية بعد إزالة الكلمات المفتاحية
    final words = text.split(RegExp(r'\s+'));
    for (final w in words) {
      final clean = w.replaceAll(RegExp(r'[^\u0600-\u06FF]'), '');
      if (clean.isNotEmpty && !_isKeyword(clean) && !_isCurrencyWord(clean)) {
        return clean;
      }
    }

    return null;
  }

  /// ============ استخراج العملة ============
  static String _extractCurrency(String text) {
    for (final entry in currencyMap.entries) {
      if (text.contains(entry.key)) return entry.value;
    }
    return 'YER';
  }

  /// ============ استخراج الأصناف ============
  static String _extractItems(String text) {
    // 1) إذا فيه كلمة "أصناف:" أو "بضاعة:"
    for (final kw in itemsKeywords) {
      final idx = text.indexOf(kw);
      if (idx >= 0) {
        var items = text.substring(idx + kw.length).trim();
        items = items.replaceAll(RegExp(r'^[:\s،,]+'), '');
        if (items.isNotEmpty) return items;
      }
    }

    // 2) احتياطي: ما بعد المبلغ والعملة
    final normalized = _normalizeDigits(text);
    final m = RegExp(
      r'\d+(?:[.,]\d+)?\s*(?:ريال|دولار|سعودي|درهم|يمني|يورو|دينار|جنيه|riyal|dollar|sar|aed)?\s+(.+)',
      caseSensitive: false,
    ).firstMatch(normalized);

    if (m != null) {
      var items = m.group(1)!.trim();
      // احذف الكلمات المفتاحية إن وُجدت
      for (final kw in [...paymentKeywords, ...itemsKeywords]) {
        items = items.replaceFirst(kw, '').trim();
      }
      items = items.replaceAll(RegExp(r'^[:\s،,]+'), '');
      if (items.isNotEmpty && items.length < 200) return items;
    }

    return '';
  }

  /// ============ أدوات مساعدة ============
  static String _normalizeDigits(String s) => s
      .replaceAll('٠', '0').replaceAll('١', '1').replaceAll('٢', '2')
      .replaceAll('٣', '3').replaceAll('٤', '4').replaceAll('٥', '5')
      .replaceAll('٦', '6').replaceAll('٧', '7').replaceAll('٨', '8')
      .replaceAll('٩', '9');

  static bool _isKeyword(String w) =>
      paymentKeywords.any((k) => k == w) ||
      itemsKeywords.any((k) => k == w) ||
      ['سجل', 'على', 'عليه', 'ل', 'لـ'].contains(w);

  static bool _isCurrencyWord(String w) =>
      currencyMap.keys.any((k) => k == w);
}
