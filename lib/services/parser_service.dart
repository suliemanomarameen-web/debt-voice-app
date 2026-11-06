import 'keywords_service.dart';
import 'voice_prompts_service.dart';

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

/// 🆕 نتيجة التحليل الجزئي — قد تحتوي على حقول فارغة
///
/// تُستخدم في الحوار التفاعلي:
/// - `isComplete = true` → الجملة كاملة، يمكن الحفظ مباشرة
/// - `isComplete = false` → اسأل عن `missingFields`
class ParsedPartial {
  final String? intent; // 'debt' | 'payment' | 'return' | 'add_account' | null
  final String? customerName; // null إذا لم يُعرف
  final double? amount; // null إذا لم يُعرف
  final String? items; // null إذا لم يُعرف (اختياري)
  final String currency;
  final String accountType;
  final String rawText;

  ParsedPartial({
    this.intent,
    this.customerName,
    this.amount,
    this.items,
    this.currency = 'YER',
    this.accountType = 'customer',
    required this.rawText,
  });

  /// هل الجملة كاملة (يمكن الحفظ بدون أسئلة)؟
  ///
  /// نعتبر البيان اختياريًا — لا يدخل في `isComplete`.
  bool get isComplete =>
      intent != null &&
      intent != 'add_account' &&
      customerName != null &&
      customerName!.trim().isNotEmpty &&
      amount != null &&
      amount! > 0;

  bool get hasCustomer =>
      customerName != null && customerName!.trim().isNotEmpty;

  bool get hasAmount => amount != null && amount! > 0;

  bool get hasIntent => intent != null;

  bool get hasItems => items != null && items!.trim().isNotEmpty;

  bool get isAddAccount => intent == 'add_account';

  /// الحقول المفقودة (بترتيب الأولوية)
  List<String> get missingFields {
    final missing = <String>[];
    if (intent == null) missing.add('intent');
    if (!hasCustomer) missing.add('customerName');
    if (!hasAmount) missing.add('amount');
    return missing;
  }

  /// أول حقل مفقود (للسؤال التالي)
  String? get firstMissingField =>
      missingFields.isEmpty ? null : missingFields.first;

  /// دمج نتيجة جديدة مع الحالية — الحقول الجديدة تطغى على القديمة
  ParsedPartial merge(ParsedPartial newer) {
    return ParsedPartial(
      intent: newer.intent ?? intent,
      customerName: newer.hasCustomer ? newer.customerName : customerName,
      amount: newer.hasAmount ? newer.amount : amount,
      items: newer.items != null ? newer.items : items,
      currency: newer.currency != 'YER' ? newer.currency : currency,
      accountType: newer.accountType != 'customer'
          ? newer.accountType
          : accountType,
      rawText: '${rawText.trim()} ${newer.rawText.trim()}'.trim(),
    );
  }

  /// للعرض في الملخص
  String get summary {
    final parts = <String>[];
    if (intent != null) {
      final label = {
        'debt': 'دين',
        'payment': 'سداد',
        'return': 'مرتجع',
        'add_account': 'إنشاء حساب',
      }[intent];
      if (label != null) parts.add(label);
    }
    if (hasAmount) {
      parts.add('${amount!.toStringAsFixed(0)} $currency');
    }
    if (hasCustomer) {
      parts.add('على $customerName');
    }
    if (hasItems) {
      parts.add('($items)');
    }
    return parts.isEmpty ? '(لا شيء)' : parts.join(' ');
  }

  @override
  String toString() =>
      'ParsedPartial(intent=$intent, customer=$customerName, amount=$amount, items=$items)';
}

class ParserService {
  /// حذف التشكيل من النص (للتحليل فقط)
  static String _stripTashkeel(String text) {
    return text
        .replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '')
        .replaceAll('\u0640', '');
  }

  /// كلمات التوقف — لا تُعتبر جزءًا من اسم الحساب
  static const List<String> _stopWords = [
    'دين', 'سداد', 'مرتجع', 'دفع', 'وصل', 'سجل', 'استلم',
    'ريال', 'دولار', 'درهم', 'سعودي',
    'yer', 'usd', 'sar', 'aed',
    'أصناف', 'اصناف', 'الأصناف', 'الاصناف',
    'items', 'for', 'from', 'on',
    'على', 'من', 'إلى', 'الى', 'في', 'عن', 'مع',
    'لـ', 'ل', 'من',
    'ريال', 'صنف', 'بيان', 'البيان',
  ];

  // ═══════════════════════════════════════════════════════════
  // التحليل الكامل (النسخة القديمة — للتوافق)
  // ═══════════════════════════════════════════════════════════
  static ParsedEntry? parse(String text) {
    final original = text.trim();
    if (original.isEmpty) return null;

    final clean = _stripTashkeel(original);
    final t = clean.toLowerCase();

    // ========== نية إضافة حساب ==========
    final addAccountMatch = _detectAddAccountIntent(t, clean);
    if (addAccountMatch != null) return addAccountMatch;

    // ========== تحديد نوع المعاملة ==========
    String intent = 'debt';
    String? warning;

    final returnKeywords = KeywordsService.get(KeywordsService.catReturn);
    final debtKeywords = KeywordsService.get(KeywordsService.catDebt);
    final paymentKeywords = KeywordsService.get(KeywordsService.catPayment);

    if (_containsAny(t, returnKeywords)) {
      intent = 'return';
    } else if (_containsAny(t, debtKeywords)) {
      intent = 'debt';
    } else if (_containsAny(t, ['دفع']) && !t.contains('دفع ل')) {
      intent = 'payment';
    } else if (_containsAny(t, ['وصل من', 'وصلني', 'استلمت', 'استلم'])) {
      intent = 'payment';
    } else if (_containsAny(t, ['وصل'])) {
      intent = 'payment';
      if (t.contains('وصل ل')) {
        warning = '⚠️ "وصل لـ" غامضة. استخدم "دفع محمد 500" للسداد '
            'أو "سجل على محمد 500" للدين.';
      }
    } else if (_containsAny(t, paymentKeywords)) {
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
  // 🆕 التحليل الجزئي (للحوار التفاعلي)
  // ═══════════════════════════════════════════════════════════

  /// تحليل جزئي — يستخرج ما يمكن استخراجه، ويعيد null للباقي
  ///
  /// [expecting] يمكن أن يكون:
  /// - `'intent'` → المستخدم يجيب على "دين أم سداد؟"
  /// - `'customerName'` → المستخدم يجيب على "على من أسجل؟"
  /// - `'amount'` → المستخدم يجيب على "كم المبلغ؟"
  /// - `'items'` → المستخدم يجيب على "ما البيان؟"
  /// - `null` → تحليل كامل جزئي
  static ParsedPartial parsePartial(String text, {String? expecting}) {
    final original = text.trim();
    if (original.isEmpty) return ParsedPartial(rawText: '');

    final clean = _stripTashkeel(original);
    final t = clean.toLowerCase();

    // ═══════════════════════════════════════════════════════════
    // ردود سياقية (المستخدم يجيب على سؤال محدد)
    // ═══════════════════════════════════════════════════════════

    if (expecting == 'amount') {
      final amount = _extractAmountOnly(original);
      return ParsedPartial(
        amount: amount,
        currency: _extractCurrency(t),
        rawText: original,
      );
    }

    if (expecting == 'customerName') {
      final name = _extractNameFromAnswer(clean);
      return ParsedPartial(
        customerName: name,
        rawText: original,
      );
    }

    if (expecting == 'items') {
      // تحقق من كلمة التخطي
      final skipWord =
          VoicePromptsService.getPrompt(VoicePromptsService.pSkipItemsWord);
      final normalizedT = _normalizeForCompare(t);
      final normalizedSkip = _normalizeForCompare(skipWord);

      final isSkip = normalizedT.contains(normalizedSkip) ||
          normalizedT.contains('بدون') ||
          normalizedT.contains('تخطي') ||
          normalizedT.contains('تخطى') ||
          normalizedT.contains('احفظ') ||
          normalizedT.contains('حفظ') ||
          normalizedT.contains('لا شيء') ||
          normalizedT.contains('لاشيء');

      return ParsedPartial(
        items: isSkip ? '' : clean.trim(),
        rawText: original,
      );
    }

    if (expecting == 'intent') {
      final intent = _detectIntent(t);
      return ParsedPartial(intent: intent, rawText: original);
    }

    // ═══════════════════════════════════════════════════════════
    // تحليل كامل جزئي
    // ═══════════════════════════════════════════════════════════

    // 1. النية
    String? intent = _detectIntent(t);

    // فحص إضافة الحساب
    if (intent == null && _isAddAccount(t)) {
      intent = 'add_account';
    }

    // 2. المبلغ
    final amount = _extractAmountOnly(original);

    // 3. اسم الحساب
    String? customerName = _extractNamePartial(clean);

    // 4. الأصناف
    String? items = _extractItemsPartial(clean, amount);

    return ParsedPartial(
      intent: intent,
      customerName: customerName,
      amount: amount,
      items: items,
      currency: _extractCurrency(t),
      rawText: original,
    );
  }

  // ═══════════════════════════════════════════════════════════
  // كشف النية
  // ═══════════════════════════════════════════════════════════

  static String? _detectIntent(String t) {
    final returnKeywords = KeywordsService.get(KeywordsService.catReturn);
    final debtKeywords = KeywordsService.get(KeywordsService.catDebt);
    final paymentKeywords = KeywordsService.get(KeywordsService.catPayment);

    // الأولوية: مرتجع → دين → سداد

    if (_containsAny(t, returnKeywords)) return 'return';

    if (_containsAny(t, debtKeywords)) return 'debt';

    if (_containsAny(t, paymentKeywords)) return 'payment';

    return null;
  }

  static bool _isAddAccount(String t) {
    final addAccountKeywords =
        KeywordsService.get(KeywordsService.catAddAccount);
    final hasVerb = _containsAny(t, addAccountKeywords);
    if (!hasVerb) return false;

    const accountWords = [
      'حساب', 'عميل', 'مورد', 'أخرى', 'اخرى',
      'account', 'customer', 'supplier',
    ];
    return accountWords.any((w) => t.contains(w));
  }

  // ═══════════════════════════════════════════════════════════
  // استخراج المبلغ
  // ═══════════════════════════════════════════════════════════

  static double? _extractAmountOnly(String text) {
    // 1. جرّب الأرقام
    final digitMatch = _findFirstNumber(text);
    if (digitMatch != null) return digitMatch;

    // 2. جرّب الأرقام المكتوبة
    final words = text.split(RegExp(r'\s+'));
    for (final w in words) {
      final cleaned = w.replaceAll(RegExp(r'[،,.!؟?:;]+$'), '').trim();
      final wordNum = _tryParseWordNumber(cleaned);
      if (wordNum != null) return wordNum;
    }

    return null;
  }

  static double? _findFirstNumber(String text) {
    // الأرقام العربية
    final normalized = text
        .replaceAll('٠', '0')
        .replaceAll('١', '1')
        .replaceAll('٢', '2')
        .replaceAll('٣', '3')
        .replaceAll('٤', '4')
        .replaceAll('٥', '5')
        .replaceAll('٦', '6')
        .replaceAll('٧', '7')
        .replaceAll('٨', '8')
        .replaceAll('٩', '9');

    // الرقم قد يكون "500" أو "500.5" أو "500,5"
    final m = RegExp(r'\d+(?:[.,]\d+)?').firstMatch(normalized);
    if (m != null) {
      return double.tryParse(m.group(0)!.replaceAll(',', '.'));
    }
    return null;
  }

  static double? _tryParseWordNumber(String w) {
    final lower = w.toLowerCase();

    // الأرقام الأساسية
    const map = {
      'صفر': 0, 'واحد': 1, 'واحدة': 1, 'اثنين': 2, 'اثنان': 2, 'اثنتين': 2,
      'ثلاثة': 3, 'ثلاث': 3, 'أربعة': 4, 'اربعة': 4, 'أربع': 4,
      'خمسة': 5, 'خمس': 5, 'ستة': 6, 'ست': 6, 'سبعة': 7, 'سبع': 7,
      'ثمانية': 8, 'ثماني': 8, 'تسعة': 9, 'تسع': 9, 'عشرة': 10, 'عشر': 10,
      'عشرين': 20, 'عشرون': 20,
      'ثلاثين': 30, 'ثلاثون': 30,
      'أربعين': 40, 'اربعين': 40, 'أربعون': 40,
      'خمسين': 50, 'خمسون': 50,
      'ستين': 60, 'ستون': 60,
      'سبعين': 70, 'سبعون': 70,
      'ثمانين': 80, 'ثمانون': 80,
      'تسعين': 90, 'تسعون': 90,
      'مية': 100, 'مئة': 100, 'مائة': 100,
      'مئتين': 200, 'مئتان': 200, 'ميتين': 200,
      'خمسمية': 500, 'خمسمائة': 500, 'خمسماية': 500,
      'ألف': 1000, 'الف': 1000, 'ألفين': 2000, 'الفين': 2000,
      'مليون': 1000000, 'مليونين': 2000000,
      'thousand': 1000, 'million': 1000000, 'hundred': 100,
    };

    if (map.containsKey(lower)) {
      return map[lower]!.toDouble();
    }

    // معالجة "خمسماية" (بدون همزة)
    if (lower.startsWith('خمس') && (lower.contains('مية') || lower.contains('ماية'))) {
      return 500;
    }

    return null;
  }

  // ═══════════════════════════════════════════════════════════
  // استخراج اسم الحساب
  // ═══════════════════════════════════════════════════════════

  /// استخراج اسم من رد مباشر (بعد "على من أسجل؟")
  ///
  /// المستخدم قد يقول: "محمد" / "محمد علي" / "على محمد" / "محمد 500"
  static String? _extractNameFromAnswer(String text) {
    String clean = text.trim();
    if (clean.isEmpty) return null;

    // إذا كان رقمًا فقط → ليس اسمًا
    if (_findFirstNumber(clean) != null &&
        !RegExp(r'[a-zA-Z\u0600-\u06FF]').hasMatch(clean.replaceAll(RegExp(r'\d'), ''))) {
      return null;
    }

    // احذف كلمات التوقف من البداية
    final words = clean.split(RegExp(r'\s+'));
    final nameWords = <String>[];

    for (final w in words) {
      final cleaned = w.replaceAll(RegExp(r'[،,.!؟?:;]+$'), '').trim();
      if (cleaned.isEmpty) continue;

      // إذا وصلنا إلى رقم → توقف
      if (_findFirstNumber(cleaned) != null) break;

      // إذا كانت كلمة توقف في البداية → تجاهلها
      if (nameWords.isEmpty && _isStopWord(cleaned)) continue;

      nameWords.add(cleaned);
    }

    if (nameWords.isEmpty) return null;

    final name = nameWords.join(' ').trim();
    return name.isEmpty ? null : name;
  }

  /// استخراج اسم من جملة كاملة (تحليل جزئي)
  ///
  /// "سجل على محمد 500" → "محمد"
  /// "سجل على" → null
  /// "سجل" → null
  static String? _extractNamePartial(String text) {
    String clean = text.trim();
    if (clean.isEmpty) return null;

    // ابحث عن كل الكلمات المفتاحية (أطول أولًا)
    final allKeywords = <String>{
      ...KeywordsService.get(KeywordsService.catDebt),
      ...KeywordsService.get(KeywordsService.catPayment),
      ...KeywordsService.get(KeywordsService.catReturn),
    }.toList()
      ..sort((a, b) => b.length.compareTo(a.length));

    for (final kw in allKeywords) {
      final idx = clean.toLowerCase().indexOf(kw.toLowerCase());
      if (idx == -1) continue;

      final after = clean.substring(idx + kw.length).trim();
      if (after.isEmpty) continue;

      final words = after.split(RegExp(r'\s+'));
      final nameWords = <String>[];

      for (final w in words) {
        final cleaned = w.replaceAll(RegExp(r'[،,.!؟?:;]+$'), '').trim();
        if (cleaned.isEmpty) continue;

        // توقف عند أول رقم
        if (_findFirstNumber(cleaned) != null) break;

        // توقف عند كلمة توقف
        if (_isStopWord(cleaned)) break;

        nameWords.add(cleaned);
      }

      if (nameWords.isNotEmpty) {
        return nameWords.join(' ').trim();
      }
    }

    return null;
  }

  // ═══════════════════════════════════════════════════════════
  // استخراج الأصناف
  // ═══════════════════════════════════════════════════════════

  static String? _extractItemsPartial(String text, double? amount) {
    if (amount == null) return null;

    // ابحث عن أول رقم في النص
    final normalized = text
        .replaceAll('٠', '0')
        .replaceAll('١', '1')
        .replaceAll('٢', '2')
        .replaceAll('٣', '3')
        .replaceAll('٤', '4')
        .replaceAll('٥', '5')
        .replaceAll('٦', '6')
        .replaceAll('٧', '7')
        .replaceAll('٨', '8')
        .replaceAll('٩', '9');

    final digitMatch = RegExp(r'\d+(?:[.,]\d+)?').firstMatch(normalized);
    if (digitMatch == null) return null;

    var after = text.substring(
      _originalIndexForDigit(text, normalized, digitMatch.end),
    ).trim();

    // احذف كلمة العملة
    after = after.replaceFirst(
        RegExp(r'^(?:ريال|دولار|درهم|سعودي|riyal|dollar|sar|aed|yer)\s*'),
        '');

    // احذف كلمة "أصناف"
    after = after.replaceFirst(
        RegExp(r'^(?:أصناف|الأصناف|اصناف|items)[:\s]*'),
        '');

    // احذف علامات الترقيم من البداية
    after = after.replaceAll(RegExp(r'^[،,.!؟?:;\s]+'), '');

    return after.isEmpty ? null : after.trim();
  }

  /// إذا قمنا بتطبيع الأرقام العربية إلى إنجليزية، نحتاج تحويل الموضع
  /// لكن بما أن التطبيع يحافظ على الطول (كل حرف عربي = حرف إنجليزي)، الموضع نفسه
  static int _originalIndexForDigit(
      String original, String normalized, int normalizedIndex) {
    // التطبيع لا يغيّر الطول لأن كل استبدال حرف بحرف
    return normalizedIndex;
  }

  // ═══════════════════════════════════════════════════════════
  // النسخة القديمة — استخراج الاسم والمبلغ معًا
  // ═══════════════════════════════════════════════════════════

  static _NameAmount? _extractNameAndAmount(String text) {
    final debtKw = KeywordsService.get(KeywordsService.catDebt);
    final paymentKw = KeywordsService.get(KeywordsService.catPayment);
    final returnKw = KeywordsService.get(KeywordsService.catReturn);

    final keywords = <String>{
      ...debtKw,
      ...paymentKw,
      ...returnKw,
      'على', 'عليه', 'عليها',
    }.toList();

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

  // ═══════════════════════════════════════════════════════════
  // أدوات مشتركة
  // ═══════════════════════════════════════════════════════════

  static bool _isStopWord(String w) {
    final lower = w.toLowerCase().trim();
    if (lower.isEmpty) return true;
    return _stopWords.contains(lower);
  }

  static bool _containsAny(String text, List<String> keywords) {
    for (final kw in keywords) {
      if (kw.isEmpty) continue;
      if (text.contains(kw.toLowerCase())) return true;
    }
    return false;
  }

  static String _normalizeForCompare(String text) {
    return text
        .replaceAll(RegExp(r'[أإآ]'), 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي')
        .replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '')
        .toLowerCase()
        .trim();
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

  static ParsedEntry? _detectAddAccountIntent(String t, String original) {
    final addAccountKeywords =
        KeywordsService.get(KeywordsService.catAddAccount);

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
}

class _NameAmount {
  final String name;
  final double amount;
  _NameAmount(this.name, this.amount);
}

// Parser Service v1: التحليل الأساسي (نية + اسم + مبلغ + أصناف)
// Parser Service v2: تحليل جزئي (parsePartial) للحوار التفاعلي
// - ParsedPartial: نموذج نتيجة جزئية مع missingFields
// - parsePartial(text, {expecting}): يدعم سياقات مختلفة (intent/customerName/amount/items)
// - _extractNameFromAnswer: لاستخراج اسم من رد مباشر
// - _extractAmountOnly: لاستخراج رقم من أي نص
// - merge(): لدمج نتائج متعددة
