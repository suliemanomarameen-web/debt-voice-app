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
  final String? intent; // 'debt' | 'payment' | 'return' | 'add_account' | 'statement' | 'block_account' | 'unblock_account' | 'set_limit' | 'process' | 'print_statement' | 'send_statement' | 'statistics' | 'last_transaction' | 'search' | 'delete_customer' | 'edit_customer' | null
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
  bool get isComplete {
    if (intent == null) return false;
    
    // الإحصائيات والبحث لا تحتاج اسم عميل ولا مبلغ
    if (intent == 'statistics' || intent == 'search') return true;

    // باقي النوايا تحتاج اسم عميل
    if (customerName == null || customerName!.trim().isEmpty) return false;

    // الدين، السداد، المرتجع، وتحديد السقف تحتاج مبلغاً
    if (intent == 'debt' || intent == 'payment' || intent == 'return' || intent == 'set_limit') {
      return amount != null && amount! > 0;
    }

    // كشف حساب، إيقاف، تفعيل، طباعة، إرسال، آخر عملية، حذف، تعديل، إضافة حساب
    return true;
  }

  bool get hasCustomer =>
      customerName != null && customerName!.trim().isNotEmpty;

  bool get hasAmount => amount != null && amount! > 0;

  bool get hasIntent => intent != null;

  bool get hasItems => items != null && items!.trim().isNotEmpty;

  bool get isAddAccount => intent == 'add_account';

  /// الحقول المفقودة (بترتيب الأولوية)
  List<String> get missingFields {
    final missing = <String>[];
    if (intent == null) {
      missing.add('intent');
    }
    
    // الإحصائيات والبحث لا تحتاج اسم عميل
    if (intent != 'statistics' && intent != 'search') {
      if (!hasCustomer) missing.add('customerName');
    }

    // الدين، السداد، المرتجع، وتحديد السقف تحتاج مبلغاً
    if (intent == 'debt' || intent == 'payment' || intent == 'return' || intent == 'set_limit') {
      if (!hasAmount) missing.add('amount');
    }

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
        'statement': 'كشف حساب',
        'block_account': 'إيقاف حساب',
        'unblock_account': 'تفعيل حساب',
        'set_limit': 'تحديد سقف',
        'process': 'عملية',
        'print_statement': 'طباعة كشف',
        'send_statement': 'إرسال كشف',
        'statistics': 'إحصائيات',
        'last_transaction': 'آخر عملية',
        'search': 'بحث',
        'delete_customer': 'حذف حساب',
        'edit_customer': 'تعديل حساب',
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
    // 🆕 كلمات النوايا الجديدة
    'كشف', 'حساب', 'رصيد',
    'أوقف', 'اوقف', 'إيقاف', 'ايقاف', 'وقف', 'عطل',
    'فعل', 'تفعيل', 'نشط', 'شغل',
    'حدد', 'سقف', 'الحد', 'الأقصى', 'الاقصى',
    'عملية', 'أضف', 'اضف',
    'طباعة', 'اطبع', 'أرسل', 'ارسل', 'إرسال', 'ارسال', 'واتساب',
    'إحصائيات', 'احصائيات', 'تقارير', 'إجمالي', 'اجمالي',
    'آخر', 'اخر', 'حركة', 'معاملة', 'تسجيل',
    'ابحث', 'بحث', 'دور', 'وين', 'أين', 'اين',
    'احذف', 'حذف', 'امسح', 'مسح',
    'عدل', 'تعديل', 'غير',
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
  /// - `'processType'` → المستخدم يجيب على "دين أم سداد أم مرتجع؟" بعد "عملية"
  /// - `'intentForCustomer'` → المستخدم يجيب على "ماذا تريد للحساب؟"
  /// - `'limitAmount'` → المستخدم يجيب على "كم السقف؟"
  static ParsedPartial parsePartial(String text, {String? expecting}) {
    final original = text.trim();
    if (original.isEmpty) return ParsedPartial(rawText: '');

    final clean = _stripTashkeel(original);
    final t = clean.toLowerCase();

    if (expecting == 'amount' || expecting == 'limitAmount') {
      return ParsedPartial(
        amount: _extractAmountOnly(original),
        currency: _extractCurrency(t),
        rawText: original,
      );
    }

    if (expecting == 'renameTo') {
      return ParsedPartial(items: clean.trim(), rawText: original);
    }

    if (expecting == 'customerName') {
      return ParsedPartial(
        customerName: _extractNameFromAnswer(clean),
        amount: _extractAmountOnly(original),
        rawText: original,
      );
    }

    if (expecting == 'items') {
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
      return ParsedPartial(
        intent: _detectIntent(t),
        amount: _extractAmountOnly(original),
        rawText: original,
      );
    }

    if (expecting == 'processType') {
      if (_containsAny(t, KeywordsService.get(KeywordsService.catDebt))) {
        return ParsedPartial(intent: 'debt', rawText: original);
      }
      if (_containsAny(t, KeywordsService.get(KeywordsService.catPayment))) {
        return ParsedPartial(intent: 'payment', rawText: original);
      }
      if (_containsAny(t, KeywordsService.get(KeywordsService.catReturn))) {
        return ParsedPartial(intent: 'return', rawText: original);
      }
      return ParsedPartial(rawText: original);
    }

    if (expecting == 'intentForCustomer') {
      return ParsedPartial(intent: _detectIntent(t), rawText: original);
    }

    String? intent = _detectIntent(t);
    if (intent == null && _isAddAccount(t)) {
      intent = 'add_account';
    }

    final amount = _extractAmountOnly(original);
    String? customerName;
    String? items;

    if (intent == 'add_account') {
      customerName = _extractAccountName(original);
    } else if (intent == 'rename_customer') {
      final renameMatch = RegExp(r'(?:إلى|الى)\s+(.+)$'
