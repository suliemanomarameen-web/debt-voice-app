import 'package:flutter/foundation.dart';
import '../config/app_settings.dart';
import '../db/database_helper.dart';
import '../models/customer.dart';
import '../models/voice_session.dart';
import '../services/accountant_service.dart';
import '../services/code_service.dart';
import '../services/logger_service.dart';
import '../services/parser_service.dart';
import '../services/settings_service.dart';
import '../handlers/transaction_handler.dart';
import '../services/voice_prompts_service.dart';

/// 🆕 نوع الخطوة التالية في الحوار
enum ConversationStep {
  /// اسأل المستخدم سؤالًا وابدأ التسجيل تلقائيًا
  askQuestion,

  /// اعرض قائمة مرشحين (حسابات مشابهة) أو "أضف جديد"
  showCandidates,

  /// الجلسة اكتملت وحُفظت
  saved,

  /// فشلت الجلسة (تجاوز المحاولات أو خطأ)
  failed,
}

/// 🆕 نتيجة كل خطوة من خطوات الحوار
class VoiceConversationResult {
  final ConversationStep step;

  /// النص الذي يُعرض في الواجهة (سؤال أو رسالة)
  final String? prompt;

  /// النص الذي يُقرأ بصوت (TTS)
  final String? ttsMessage;

  /// هل تبدأ الواجهة التسجيل تلقائيًا الآن؟
  final bool startListening;

  /// الحسابات المرشحة (عند showCandidates)
  final List<Customer>? candidates;

  /// الحساب المختار (عند saved)
  final Customer? matchedCustomer;

  /// رسالة الخطأ (عند failed)
  final String? errorMessage;

  VoiceConversationResult({
    required this.step,
    this.prompt,
    this.ttsMessage,
    this.startListening = false,
    this.candidates,
    this.matchedCustomer,
    this.errorMessage,
  });

  bool get isTerminal =>
      step == ConversationStep.saved || step == ConversationStep.failed;

  @override
  String toString() =>
      'VoiceConversationResult(step=$step, prompt=$prompt, candidates=${candidates?.length}, error=$errorMessage)';
}

/// 🆕 خدمة الحوار الصوتي التفاعلي
///
/// تستخدمها الأماكن الثلاثة:
/// - زر الإشعار الدائم
/// - الزر العائم
/// - شاشة VoiceScreen
///
/// المنطق الموحد:
/// 1. `startSession(source)` — ابدأ جلسة
/// 2. `processText(text)` — أرسل النص، واحصل على نتيجة
/// 3. النتيجة تخبرك بما تفعله (اسأل / اعرض مرشحين / محفوظ / فشل)
/// 4. `cancelSession()` — عند الانتهاء
class VoiceConversationService {
  static VoiceSession? _session;
  static List<Customer> _lastCandidates = [];

  // ═══════════════════════════════════════════════════════════
  // إدارة الجلسة
  // ═══════════════════════════════════════════════════════════

  /// ابدأ جلسة جديدة
  static VoiceSession startSession({String source = 'voice_screen'}) {
    _session = VoiceSession(source: source);
    _lastCandidates = [];
    debugPrint('🎤 [VoiceConv] Session started (source=$source)');
    return _session!;
  }

  static VoiceSession? get currentSession => _session;
  static bool get hasActiveSession => _session != null;
  static List<Customer> get lastCandidates =>
      List<Customer>.unmodifiable(_lastCandidates);

  /// ألغِ الجلسة (مسح كل شيء)
  static void cancelSession() {
    _session = null;
    _lastCandidates = [];
    debugPrint('🎤 [VoiceConv] Session cancelled');
  }

  // ═══════════════════════════════════════════════════════════
  // المعالجة الرئيسية
  // ═══════════════════════════════════════════════════════════

  /// معالجة نص جديد من المستخدم
  ///
  /// يُرجع `VoiceConversationResult` يخبر الواجهة بما تفعله.
  static Future<VoiceConversationResult> processText(
    String text, {
    String? expecting,
  }) async {
    if (_session == null) startSession();
    final session = _session!;

    if (session.isCompleted) {
      return _fail('الجلسة منتهية بالفعل');
    }

    // ═══════════════════════════════════════════════════════
    // 1. زيادة محاولة الحقل السابق
    // ═══════════════════════════════════════════════════════
    final prevExpecting = session.expectingField ?? expecting;
    if (prevExpecting != null) {
      session.incrementAttempt(prevExpecting);
      final maxRounds = SettingsService.getInt(
        AppSettings.voiceMaxConversationRounds,
        defaultValue: 3,
      );
      if (session.attemptsFor(prevExpecting) >= maxRounds) {
        debugPrint('🎤 [VoiceConv] Max attempts for $prevExpecting');
        return _failAfterMaxAttempts();
      }
    }

    // ═══════════════════════════════════════════════════════
    // 2. تحليل النص
    // ═══════════════════════════════════════════════════════
    final partial = ParserService.parsePartial(
      text,
      expecting: prevExpecting,
    );
    session.merge(partial);
    session.expectingField = null;

    debugPrint('🎤 [VoiceConv] After merge: ${session.summary}');

    // ═══════════════════════════════════════════════════════
    // 3. فحص الحقول الناقصة
    // ═══════════════════════════════════════════════════════

    if (!session.hasIntent) {
      return _askForField(session, 'intent');
    }

    if (session.isAddAccount && !session.hasCustomer) {
      return _askForField(session, 'customerName');
    }

    if (!session.hasCustomer) {
      return _askForField(session, 'customerName');
    }

    if (!session.hasAmount) {
      return _askForField(session, 'amount');
    }

    // ═══════════════════════════════════════════════════════
    // 4. البحث عن العميل
    // ═══════════════════════════════════════════════════════
    final found = await _findCustomerWithCandidates(session.customerName!);

    if (found.$1 == null) {
      return _handleUnknownCustomer(session, found.$2);
    }

    final customer = found.$1!;
    session.matchedCustomer = _customerToMap(customer);

    // ═══════════════════════════════════════════════════════
    // 5. هل نسأل عن البيان؟
    // ═══════════════════════════════════════════════════════
    final askItems = SettingsService.getBool(
      AppSettings.voiceAlwaysAskForItems,
      defaultValue: false,
    );

    if (askItems && session.items == null) {
      return _askForField(session, 'items');
    }

    // ═══════════════════════════════════════════════════════
    // 6. اكتمل → احفظ
    // ═══════════════════════════════════════════════════════
    return _saveTransaction(session, customer);
  }

  // ═══════════════════════════════════════════════════════════
  // اختيار مرشح من القائمة
  // ═══════════════════════════════════════════════════════════

  static Future<VoiceConversationResult> selectCandidate(int index) async {
    if (_session == null) return _fail('لا توجد جلسة نشطة');

    if (index < 0 || index >= _lastCandidates.length) {
      return _fail('اختيار غير صالح');
    }

    final chosen = _lastCandidates[index];
    _session!.matchedCustomer = _customerToMap(chosen);
    _session!.customerName = chosen.name;
    _lastCandidates = [];
    _session!.expectingField = null;
    _session!.resetAttemptsFor('customerName');

    debugPrint('🎤 [VoiceConv] Candidate selected: ${chosen.name}');

    // هل نسأل عن البيان؟
    final askItems = SettingsService.getBool(
      AppSettings.voiceAlwaysAskForItems,
      defaultValue: false,
    );

    if (askItems && _session!.items == null) {
      return _askForField(_session!, 'items');
    }

    return _saveTransaction(_session!, chosen);
  }

  // ═══════════════════════════════════════════════════════════
  // إضافة حساب جديد
  // ═══════════════════════════════════════════════════════════

  static Future<VoiceConversationResult> addNewCustomer() async {
    if (_session == null) return _fail('لا توجد جلسة نشطة');

    final name = _session!.customerName;
    if (name == null || name.trim().isEmpty) {
      return _fail('اسم الحساب غير معروف');
    }

    try {
      final db = DatabaseHelper.instance;
      final accountant = await AccountantService.getAccountantName();
      final now = DateTime.now().toIso8601String();

      final customerId = await db.insertCustomer(Customer(
        name: name.trim(),
        accountType: _session!.accountType,
        createdBy: accountant,
        updatedBy: accountant,
        updatedAt: now,
        createdAt: now,
      ));

      final newCustomer = await db.getCustomer(customerId);
      if (newCustomer == null) return _fail('فشل إنشاء الحساب');

      await LoggerService.logCustomerAdded(
        newCustomer.name,
        accountant: accountant,
      );

      _session!.matchedCustomer = _customerToMap(newCustomer);
      _lastCandidates = [];
      _session!.expectingField = null;

      debugPrint('🎤 [VoiceConv] New customer created: ${newCustomer.name}');

      // هل نسأل عن البيان؟
      final askItems = SettingsService.getBool(
        AppSettings.voiceAlwaysAskForItems,
        defaultValue: false,
      );

      if (askItems && _session!.items == null) {
        return _askForField(_session!, 'items');
      }

      return _saveTransaction(_session!, newCustomer);
    } catch (e) {
      debugPrint('❌ [VoiceConv] addNewCustomer: $e');
      return _fail('خطأ في إنشاء الحساب: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // الحفظ
  // ═══════════════════════════════════════════════════════════

  static Future<VoiceConversationResult> _saveTransaction(
    VoiceSession session,
    Customer customer,
  ) async {
    try {
      final db = DatabaseHelper.instance;

      final fakeParsed = _FakeParsed(
        intent: session.intent!,
        amount: session.amount!,
        currency: session.currency,
        items: session.items ?? '',
      );

      final ok = await TransactionHandler.save(
        customer: customer,
        parsed: fakeParsed,
        db: db,
        source: session.source,
        audioPath: null,
      );

      if (!ok) {
        return _fail('فشل حفظ العملية');
      }

      session.markCompleted();

      debugPrint('🎤 [VoiceConv] Transaction saved for ${customer.name}');

      return VoiceConversationResult(
        step: ConversationStep.saved,
        matchedCustomer: customer,
        ttsMessage: VoicePromptsService.getResponse(
          VoicePromptsService.rSavedSuccess,
        ),
      );
    } catch (e) {
      debugPrint('❌ [VoiceConv] save: $e');
      return _fail('فشل الحفظ: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // البحث عن العميل
  // ═══════════════════════════════════════════════════════════

  /// يُرجع tuple: (الحساب المطابق، المرشحين)
  ///
  /// - إذا وُجد حساب واحد → (customer, [])
  /// - إذا وُجد أكثر من حساب → (null, [top 5])
  /// - إذا لم يوجد → (null, [])
  static Future<(Customer?, List<Customer>)> _findCustomerWithCandidates(
    String name,
  ) async {
    final db = DatabaseHelper.instance;

    // 1. البحث الدقيق (مع تطبيع v16)
    final exact = await db.findExactCustomer(name);
    if (exact != null) {
      return (exact, <Customer>[]);
    }

    // 2. البحث الجزئي
    final partial = await db.findCustomersContaining(name);
    if (partial.length == 1) {
      return (partial.first, <Customer>[]);
    }
    if (partial.length > 1) {
      return (null, partial.take(5).toList());
    }

    return (null, <Customer>[]);
  }

  static VoiceConversationResult _handleUnknownCustomer(
    VoiceSession session,
    List<Customer> candidates,
  ) {
    _lastCandidates = candidates;

    final name = session.customerName ?? '';

    final prompt = VoicePromptsService.getPrompt(
      VoicePromptsService.pAskCustomerAmbiguous,
      vars: {'name': name},
    );

    final ttsMessage = VoicePromptsService.getResponse(
      VoicePromptsService.rNoAccount,
      vars: {'name': name},
    );

    return VoiceConversationResult(
      step: ConversationStep.showCandidates,
      prompt: prompt,
      ttsMessage: ttsMessage,
      candidates: candidates,
      startListening: false,
    );
  }

  // ═══════════════════════════════════════════════════════════
  // السؤال عن حقل
  // ═══════════════════════════════════════════════════════════

  static VoiceConversationResult _askForField(
    VoiceSession session,
    String field,
  ) {
    session.expectingField = field;

    String prompt;
    switch (field) {
      case 'intent':
        prompt = VoicePromptsService.getPrompt(
          VoicePromptsService.pAskIntent,
        );
        break;

      case 'customerName':
        if (session.intent == 'payment') {
          prompt = VoicePromptsService.getPrompt(
            VoicePromptsService.pAskCustomerPayment,
          );
        } else if (session.intent == 'return') {
          prompt = VoicePromptsService.getPrompt(
            VoicePromptsService.pAskCustomerReturn,
          );
        } else if (session.intent == 'debt') {
          prompt = VoicePromptsService.getPrompt(
            VoicePromptsService.pAskCustomerDebt,
          );
        } else {
          prompt = VoicePromptsService.getPrompt(
            VoicePromptsService.pAskCustomerUnknown,
          );
        }
        break;

      case 'amount':
        prompt = VoicePromptsService.getPrompt(
          VoicePromptsService.pAskAmount,
        );
        break;

      case 'items':
        prompt = VoicePromptsService.getPrompt(
          VoicePromptsService.pAskItems,
        );
        break;

      default:
        prompt = 'ماذا تريد؟';
    }

    session.lastPrompt = prompt;
    debugPrint('🎤 [VoiceConv] Asking for $field: "$prompt"');

    return VoiceConversationResult(
      step: ConversationStep.askQuestion,
      prompt: prompt,
      ttsMessage: prompt,
      startListening: true,
    );
  }

  // ═══════════════════════════════════════════════════════════
  // حالات الفشل
  // ═══════════════════════════════════════════════════════════

  static VoiceConversationResult _fail(String error) {
    return VoiceConversationResult(
      step: ConversationStep.failed,
      errorMessage: error,
    );
  }

  static Future<VoiceConversationResult> _failAfterMaxAttempts() async {
    final maxRounds = SettingsService.getInt(
      AppSettings.voiceMaxConversationRounds,
      defaultValue: 3,
    );

    final session = _session;
    if (session != null) {
      try {
        await _saveAsPendingUnclear(session);
      } catch (_) {}
      session.markCompleted();
    }

    final ttsMessage = VoicePromptsService.getResponse(
      VoicePromptsService.rUnknownMax,
      vars: {'max': '$maxRounds'},
    );

    debugPrint('🎤 [VoiceConv] Max attempts reached');

    return VoiceConversationResult(
      step: ConversationStep.failed,
      ttsMessage: ttsMessage,
      errorMessage: 'تجاوز $maxRounds محاولات',
    );
  }

  static Future<void> _saveAsPendingUnclear(VoiceSession session) async {
    await LoggerService.logVoicePending(
      rawText: session.collectedTexts.join(' / '),
      partialParse: {
        'intent': session.intent,
        'amount': session.amount,
        'customerName': session.customerName,
        'items': session.items,
      },
    );
  }

  // ═══════════════════════════════════════════════════════════
  // أدوات
  // ═══════════════════════════════════════════════════════════

  static Map<String, dynamic> _customerToMap(Customer c) {
    return {
      'id': c.id,
      'name': c.name,
      'phone': c.phone,
      'account_type': c.accountType,
    };
  }
}

/// نموذج توافق مع TransactionHandler (يستخدم dynamic)
class _FakeParsed {
  final String intent;
  final double amount;
  final String currency;
  final String items;

  _FakeParsed({
    required this.intent,
    required this.amount,
    required this.currency,
    required this.items,
  });
}

// VoiceConversationService v1: خدمة الحوار الصوتي التفاعلي
// - startSession/cancelSession لإدارة الجلسة
// - processText: المعالجة الرئيسية (يُرجع ConversationStep)
// - selectCandidate/addNewCustomer: للاختيار من المرشحين
// - _askForField: يسأل عن حقل ناقص مع TTS تلقائي
// - _saveTransaction: يستخدم TransactionHandler (توافق كامل)
// - _failAfterMaxAttempts: عند تجاوز المحاولات
// - _findCustomerWithCandidates: يبحث ويجمع المرشحين
