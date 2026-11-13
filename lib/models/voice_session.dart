import '../services/parser_service.dart';

/// نموذج جلسة الحوار الصوتي
///
/// يمثّل حالة محادثة واحدة بين التطبيق والمستخدم.
/// يستخدمه `VoiceConversationService` لإدارة:
/// - الحقول المجمّعة (intent, customerName, amount, items)
/// - عدد المحاولات لكل حقل
/// - ما ننتظره من المستخدم الآن (expectingField)
/// - النصوص المدخلة (للسجل)
///
/// دورة الحياة:
/// 1. `VoiceSession()` جديد → فارغ
/// 2. `merge(partial)` عند كل إدخال صوتي
/// 3. `isComplete` يصبح true بعد اكتمال الحقول الأساسية
/// 4. `markCompleted()` → الجلسة تنتهي
class VoiceSession {
  /// النية: 'debt' | 'payment' | 'return' | 'add_account' | null
  String? intent;

  /// اسم الحساب (كما استخرجه التحليل)
  String? customerName;

  /// المبلغ
  double? amount;

  /// الأصناف / البيان
  String? items;

  /// العملة
  String currency;

  /// نطاق تاريخ كشف الحساب عند طلب الطباعة
  DateTime? fromDate;
  DateTime? toDate;

  /// نوع الحساب
  String accountType;

  /// عدد المحاولات الإجمالي
  int totalAttempts;

  /// عدد المحاولات لكل حقل (intent, customerName, amount, items)
  Map<String, int> fieldAttempts;

  /// الحقل الذي ننتظر إجابته الآن
  /// - null = لا ننتظر شيئًا (نستمع لجملة كاملة)
  /// - 'intent' / 'customerName' / 'amount' / 'items'
  String? expectingField;

  /// آخر سؤال طُرح على المستخدم (نصه)
  String? lastPrompt;

  /// كل النصوص التي قالها المستخدم
  final List<String> collectedTexts;

  /// الحساب المطابق (بعد البحث في قاعدة البيانات)
  /// يُملأ عند العثور على العميل
  Map<String, dynamic>? matchedCustomer;

  /// المصدر: 'overlay' | 'notification' | 'voice_screen'
  final String source;

  /// وقت بدء الجلسة
  final DateTime startedAt;

  /// هل الجلسة مكتملة (تم الحفظ)؟
  bool _isCompleted;

  VoiceSession({
    this.intent,
    this.customerName,
    this.amount,
    this.items,
    this.currency = 'YER',
    this.fromDate,
    this.toDate,
    this.accountType = 'customer',
    this.totalAttempts = 0,
    Map<String, int>? fieldAttempts,
    this.expectingField,
    this.lastPrompt,
    List<String>? collectedTexts,
    this.matchedCustomer,
    this.source = 'voice_screen',
    DateTime? startedAt,
    bool isCompleted = false,
  })  : fieldAttempts = fieldAttempts ??
            {'intent': 0, 'customerName': 0, 'amount': 0, 'items': 0},
        collectedTexts = collectedTexts ?? [],
        startedAt = startedAt ?? DateTime.now(),
        _isCompleted = isCompleted;

  // ═══════════════════════════════════════════════════════════
  // الحالة
  // ═══════════════════════════════════════════════════════════

  bool get isCompleted => _isCompleted;

  bool get hasIntent => intent != null;

  bool get hasCustomer =>
      customerName != null && customerName!.trim().isNotEmpty;

  bool get hasAmount => amount != null && amount! > 0;

  bool get hasItems => items != null && items!.trim().isNotEmpty;

  bool get isAddAccount => intent == 'add_account';

  /// هل الجملة كاملة (كل الحقول الأساسية موجودة)؟
  bool get isComplete =>
      hasIntent && !isAddAccount && hasCustomer && hasAmount;

  /// هل نحن في وضع "ننتظر إجابة"؟
  bool get isAwaitingAnswer => expectingField != null;

  // ═══════════════════════════════════════════════════════════
  // الحقول الناقصة
  // ═══════════════════════════════════════════════════════════

  /// الحقول الناقصة الأساسية (بترتيب الأولوية)
  List<String> get missingFields {
    final missing = <String>[];
    if (!hasIntent) missing.add('intent');
    if (!hasCustomer) missing.add('customerName');
    if (!hasAmount) missing.add('amount');
    return missing;
  }

  /// أول حقل ناقص
  String? get firstMissingField =>
      missingFields.isEmpty ? null : missingFields.first;

  // ═══════════════════════════════════════════════════════════
  // محاولات الحقل
  // ═══════════════════════════════════════════════════════════

  int attemptsFor(String field) => fieldAttempts[field] ?? 0;

  void incrementAttempt(String field) {
    fieldAttempts[field] = (fieldAttempts[field] ?? 0) + 1;
    totalAttempts++;
  }

  void resetAttemptsFor(String field) {
    fieldAttempts[field] = 0;
  }

  void resetAllAttempts() {
    for (final key in fieldAttempts.keys.toList()) {
      fieldAttempts[key] = 0;
    }
    totalAttempts = 0;
  }

  // ═══════════════════════════════════════════════════════════
  // الدمج
  // ═══════════════════════════════════════════════════════════

  /// دمج نتيجة تحليل جزئي جديدة مع الحالة الحالية
  ///
  /// القاعدة: الحقل الجديد يطغى على القديم فقط إذا كان غير فارغ.
  void merge(ParsedPartial partial) {
    if (partial.hasIntent) {
      intent = partial.intent;
      resetAttemptsFor('intent');
    }
    if (partial.hasCustomer) {
      customerName = partial.customerName;
      resetAttemptsFor('customerName');
    }
    if (partial.hasAmount) {
      amount = partial.amount;
      resetAttemptsFor('amount');
    }
    if (partial.items != null) {
      items = partial.items;
      resetAttemptsFor('items');
    }
    if (partial.currency != 'YER') {
      currency = partial.currency;
    }
    if (partial.fromDate != null) fromDate = partial.fromDate;
    if (partial.toDate != null) toDate = partial.toDate;
    if (partial.accountType != 'customer') {
      accountType = partial.accountType;
    }
    collectedTexts.add(partial.rawText);
  }

  /// تحويل الجلسة الحالية إلى `ParsedPartial` (للاستخدام في الدمج)
  ParsedPartial toPartial() {
    return ParsedPartial(
      intent: intent,
      customerName: customerName,
      amount: amount,
      items: items,
      currency: currency,
      fromDate: fromDate,
      toDate: toDate,
      accountType: accountType,
      rawText: collectedTexts.isEmpty ? '' : collectedTexts.last,
    );
  }

  // ═══════════════════════════════════════════════════════════
  // الإكمال
  // ═══════════════════════════════════════════════════════════

  void markCompleted() {
    _isCompleted = true;
  }

  void markIncomplete() {
    _isCompleted = false;
  }

  // ═══════════════════════════════════════════════════════════
  // الاستنساخ (للاختبارات)
  // ═══════════════════════════════════════════════════════════

  VoiceSession clone() {
    return VoiceSession(
      intent: intent,
      customerName: customerName,
      amount: amount,
      items: items,
      currency: currency,
      fromDate: fromDate,
      toDate: toDate,
      accountType: accountType,
      totalAttempts: totalAttempts,
      fieldAttempts: Map<String, int>.from(fieldAttempts),
      expectingField: expectingField,
      lastPrompt: lastPrompt,
      collectedTexts: List<String>.from(collectedTexts),
      matchedCustomer: matchedCustomer,
      source: source,
      startedAt: startedAt,
      isCompleted: _isCompleted,
    );
  }

  // ═══════════════════════════════════════════════════════════
  // للعرض والتصحيح
  // ═══════════════════════════════════════════════════════════

  /// ملخص الجلسة (للسجل)
  String get summary {
    final parts = <String>[];
    if (hasIntent) {
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
    return parts.isEmpty ? '(جلسة فارغة)' : parts.join(' ');
  }

  @override
  String toString() {
    return 'VoiceSession(source=$source, intent=$intent, '
        'customerName=$customerName, amount=$amount, items=$items, '
        'attempts=$totalAttempts, completed=$_isCompleted)';
  }
}

// VoiceSession v1: نموذج جلسة الحوار الصوتي
// - يخزن الحقول المجمعة (intent, customerName, amount, items)
// - يتتبع عدد المحاولات لكل حقل
// - يدعم merge() لدمج التحليلات الجزئية
// - يدعم toPartial() للتحويل إلى ParsedPartial
// - يخزن النصوص المدخلة والحساب المطابق للسياق
