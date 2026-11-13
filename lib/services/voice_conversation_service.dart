import 'package:flutter/foundation.dart';
import '../config/app_settings.dart';
import '../db/database_helper.dart';
import '../models/customer.dart';
import '../models/voice_session.dart';
import '../services/accountant_service.dart';
import '../services/logger_service.dart';
import '../services/parser_service.dart';
import '../services/settings_service.dart';
import '../handlers/transaction_handler.dart';
import '../services/voice_prompts_service.dart';
import '../services/query_service.dart'; // 🆕 لمعالجة الاستعلامات

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

  /// نطاق التاريخ المطلوب لكشف الحساب، إن ذكره المستخدم صوتياً
  final DateTime? fromDate;
  final DateTime? toDate;

  /// رسالة الخطأ (عند failed)
  final String? errorMessage;

  /// 🆕 الشاشة التي يجب فتحها بعد التنفيذ (مثلاً 'stats', 'print', 'search')
  final String? targetScreen;

  VoiceConversationResult({
    required this.step,
    this.prompt,
    this.ttsMessage,
    this.startListening = false,
    this.candidates,
    this.matchedCustomer,
    this.fromDate,
    this.toDate,
    this.errorMessage,
    this.targetScreen,
  });

  bool get isTerminal =>
      step == ConversationStep.saved || step == ConversationStep.failed;

  @override
  String toString() =>
      'VoiceConversationResult(step=$step, prompt=$prompt, candidates=${candidates?.length}, error=$errorMessage, targetScreen=$targetScreen)';
}

/// 🆕 خدمة الحوار الصوتي التفاعلي
class VoiceConversationService {
  static final Map<String, VoiceSession> _sessions = {};
  static final Map<String, List<Customer>> _candidatesBySource = {};

  // ═══════════════════════════════════════════════════════════
  // إدارة الجلسة
  // ═══════════════════════════════════════════════════════════

  /// ابدأ جلسة جديدة
  static VoiceSession startSession({String source = 'voice_screen'}) {
    final session = VoiceSession(source: source);
    _sessions[source] = session;
    _candidatesBySource.remove(source);
    debugPrint('🎤 [VoiceConv] Session started (source=$source)');
    return session;
  }

  static bool _isCurrentSession(VoiceSession session) =>
      identical(_sessions[session.source], session) && !session.isCompleted;

  static VoiceSession? sessionFor(String source) => _sessions[source];
  static bool hasActiveSessionFor(String source) => _sessions.containsKey(source);
  static List<Customer> candidatesFor(String source) => List<Customer>.unmodifiable(_candidatesBySource[source] ?? const []);
  static VoiceSession? get currentSession => sessionFor('voice_screen');
  static bool get hasActiveSession => hasActiveSessionFor('voice_screen');
  static List<Customer> get lastCandidates => candidatesFor('voice_screen');
  static void cancelSession({String source = 'voice_screen'}) {
    _sessions.remove(source);
    _candidatesBySource.remove(source);
    debugPrint('🎤 [VoiceConv] Session cancelled (source=$source)');
  }

  /// التعرّف على أوامر الإلغاء قبل تحليل أي حقل حتى لا تُحفظ كلمة "إلغاء" كبيان.
  static bool isCancelCommand(String text) {
    final normalized = text
        .replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '')
        .replaceAll(RegExp(r'[،,.!؟?:;]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .toLowerCase();
    return RegExp(
      r'^(?:الغاء|إلغاء|الغي|ألغ|الغى|cancel|cancel operation|stop)(?:\s+(?:العملية|عمليه|operation))?$',
    ).hasMatch(normalized);
  }

  /// تطبيع ردود التأكيد الصوتية حتى لا تُرفض بسبب علامات الترقيم أو التشكيل.
  static String _normalizeConfirmationAnswer(String text) {
    return text
        .replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '')
        .replaceAll(RegExp(r'[،,.!؟?:;؛"“”]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .toLowerCase();
  }

  /// قبول إجابات الموافقة الواضحة فقط في تأكيد الإضافة والحذف.
  static bool isAffirmativeConfirmation(String text) {
    final answer = _normalizeConfirmationAnswer(text);
    const exactAnswers = {
      'نعم', 'ايوه', 'أيوه', 'اي', 'أجل', 'اجل', 'أكيد', 'اكيد',
      'موافق', 'تمام', 'yes', 'ok', 'okay',
    };
    if (exactAnswers.contains(answer)) return true;
    return RegExp(
      r'^(?:نعم|ايوه|أيوه|اي|أجل|اجل|أكيد|اكيد|موافق|تمام)\s+(?:أضف|اضف|احذف|احذف الحساب|نفذ|نفّذ|أكمل|اكمل|الحساب|الحذف)$',
    ).hasMatch(answer);
  }

  /// قبول إجابات الرفض الواضحة فقط في تأكيد الإضافة والحذف.
  static bool isNegativeConfirmation(String text) {
    final answer = _normalizeConfirmationAnswer(text);
    const exactAnswers = {
      'لا', 'كلا', 'مش', 'لا تضف', 'لا تضيف', 'غير موافق',
      'no', 'nope',
    };
    return exactAnswers.contains(answer) ||
        RegExp(r'^(?:لا|كلا)\s+(?:تحذف|تحذف الحساب|تضف|تضيف|تنفذ|تكمل)$')
            .hasMatch(answer);
  }

  /// إلغاء الجلسة بالكامل وإرجاع رسالة واضحة دون حفظ أي بيانات.
  static VoiceConversationResult cancelFromVoice({String source = 'voice_screen'}) {
    cancelSession(source: source);
    return VoiceConversationResult(
      step: ConversationStep.failed,
      ttsMessage: 'تم إلغاء العملية',
      errorMessage: 'تم إلغاء العملية',
    );
  }

  static Future<VoiceConversationResult> processText(
    String text, {
    String? expecting,
    String source = 'voice_screen',
  }) async {
    // يجب أن يسبق الإلغاء كل التحليلات، خصوصاً تحليل البيان وتأكيد الحذف.
    if (isCancelCommand(text)) return cancelFromVoice(source: source);

    if (!hasActiveSessionFor(source)) startSession(source: source);
    final session = _sessions[source]!;

    if (session.isCompleted) {
      return _fail('الجلسة منتهية بالفعل');
    }

    // 🆕 1. فحص الاستعلام المباشر (كشف حساب، رصيد، إلخ) إذا لم نكن في منتصف حوار
    if (expecting == null &&
        session.collectedTexts.isEmpty &&
        session.expectingField == null) {
      try {
        if (QueryService.isQuery(text)) {
          final qResult = await QueryService.query(text);
          if (!_isCurrentSession(session)) return _cancelledResult();
          session.markCompleted();
          return VoiceConversationResult(
            step: ConversationStep.saved,
            ttsMessage: qResult.spokenAnswer,
            startListening: false,
          );
        }
      } catch (e) {
        debugPrint('❌ [VoiceConv] Query error: $e');
      }
    }

    final prevExpecting = session.expectingField ?? expecting;
    if (prevExpecting != null) {
      // نسجل المحاولة، لكن لا نرفض الإجابة قبل تحليلها؛ فقد تكون الإجابة
      // الصحيحة هي المحاولة الثالثة.
      session.incrementAttempt(prevExpecting);
    }

    // تأكيد إضافة حساب جديد عندما لا يوجد حساب بالاسم المنطوق.
    if (prevExpecting == 'confirmAddAccount' ||
        prevExpecting == 'confirmDelete') {
      if (isAffirmativeConfirmation(text)) {
        if (prevExpecting == 'confirmAddAccount') {
          return _addNewCustomer(session);
        }
        return _executeDelete(session);
      }

      if (isNegativeConfirmation(text)) {
        cancelSession(source: session.source);
        final message = prevExpecting == 'confirmAddAccount'
            ? 'تم إلغاء إضافة الحساب'
            : 'تم إلغاء الحذف';
        return VoiceConversationResult(
          step: ConversationStep.failed,
          ttsMessage: message,
          errorMessage: message,
        );
      }

      // الصمت أو الإجابة غير الواضحة لا تعني الرفض؛ أعد السؤال حتى 3 مرات.
      final maxRounds = SettingsService.getInt(
        AppSettings.voiceMaxConversationRounds,
        defaultValue: 3,
      );
      if (session.attemptsFor(prevExpecting!) >= maxRounds) {
        return _failAfterMaxAttempts(session);
      }

      final message = prevExpecting == 'confirmAddAccount'
          ? 'هل تريد إضافة الحساب؟ قل نعم أو لا'
          : 'هل أنت متأكد من حذف الحساب؟ قل نعم أو لا';
      session.expectingField = prevExpecting;
      session.lastPrompt = message;
      return VoiceConversationResult(
        step: ConversationStep.askQuestion,
        prompt: message,
        ttsMessage: message,
        startListening: true,
      );
    }

    // 3. تحليل النص
    final partial = ParserService.parsePartial(
      text,
      expecting: prevExpecting,
    );
    session.merge(partial);
    session.expectingField = null;

    // لا نلغي إلا بعد ثلاث إجابات غير مفهومة فعلاً، وليس قبل تحليل الإجابة.
    if (prevExpecting != null &&
        !_hasAnswerForField(session, prevExpecting)) {
      final maxRounds = SettingsService.getInt(
        AppSettings.voiceMaxConversationRounds,
        defaultValue: 3,
      );
      if (session.attemptsFor(prevExpecting) >= maxRounds) {
        return _failAfterMaxAttempts(session);
      }
    }

    debugPrint('🎤 [VoiceConv] After merge: ${session.summary}');

    // ═══════════════════════════════════════════════════════════
    // 4. فحص الحقول الناقصة حسب النية
    // ═══════════════════════════════════════════════════════════

    // أ. إذا لم تكن هناك نية ولكن يوجد اسم عميل (فقط "محمد")
    if (!session.hasIntent && session.hasCustomer) {
      return _askForField(session, 'intentForCustomer');
    }

    if (!session.hasIntent) {
      return _askForField(session, 'intent');
    }

    // ب. عملية عامة (process): اسأل عن النوع
    if (session.intent == 'process') {
      return _askForField(session, 'processType');
    }

    // ج. النوايا التي لا تحتاج اسم عميل (إحصائيات)
    if (session.intent == 'statistics') {
      return _executeStatistics(session);
    }

    // د. البحث يحتاج كلمة بحث فقط
    if (session.intent == 'search') {
      if (prevExpecting == 'searchQuery') {
        return _executeSearch(session, text);
      }
      return _askForField(session, 'searchQuery');
    }

    // هـ. النوايا التي تحتاج اسم عميل فقط
    final needsCustomerOnly = [
      'statement',
      'block_account',
      'unblock_account',
      'remove_limit',
      'print_statement',
      'send_statement',
      'last_transaction',
      'delete_customer',
      'edit_customer',
      'rename_customer',
    ];
    if (needsCustomerOnly.contains(session.intent) && !session.hasCustomer) {
      return _askForField(session, 'customerName');
    }

    // و. تحديد السقف يحتاج اسم ومبلغ
    if (session.intent == 'set_limit') {
      if (!session.hasCustomer) return _askForField(session, 'customerName');
      if (!session.hasAmount) return _askForField(session, 'limitAmount');
    }

    // ز. العمليات المالية تحتاج اسم ومبلغ
    if (['debt', 'payment', 'return'].contains(session.intent)) {
      if (!session.hasCustomer) return _askForField(session, 'customerName');
      if (!session.hasAmount) return _askForField(session, 'amount');
    }

    // ح. إضافة حساب
    if (session.intent == 'add_account' && !session.hasCustomer) {
      return _askForField(session, 'customerName');
    }

    // ═══════════════════════════════════════════════════════════
    // 5. البحث عن العميل (إذا لزم)
    // ═══════════════════════════════════════════════════════════
    Customer? customer;
    if (session.hasCustomer) {
      final found = await _findCustomerWithCandidates(session.customerName!);
      if (!_isCurrentSession(session)) return _cancelledResult();
      if (found.$1 == null) {
        return _handleUnknownCustomer(session, found.$2);
      }
      customer = found.$1!;
      session.matchedCustomer = _customerToMap(customer);
    }

    // ═══════════════════════════════════════════════════════════
    // 6. التنفيذ بناءً على النية
    // ═══════════════════════════════════════════════════════════
    switch (session.intent) {
      case 'statement':
        return _executeStatement(session, customer!);
      case 'block_account':
        return _executeBlock(session, customer!);
      case 'unblock_account':
        return _executeUnblock(session, customer!);
      case 'set_limit':
        return _executeSetLimit(session, customer!);
      case 'remove_limit':
        return _executeRemoveLimit(session, customer!);
      case 'print_statement':
        return _executePrint(session, customer!);
      case 'send_statement':
        return _executeSend(session, customer!);
      case 'last_transaction':
        return _executeLastTransaction(session, customer!);
      case 'delete_customer':
        session.expectingField = 'confirmDelete';
        final msg = VoicePromptsService.getPrompt(
          VoicePromptsService.pConfirmDeleteCustomer,
          vars: {'name': customer!.name},
        );
        return VoiceConversationResult(
          step: ConversationStep.askQuestion,
          prompt: msg,
          ttsMessage: msg,
          startListening: true,
        );
      case 'edit_customer':
        return _executeEdit(session, customer!);
      case 'rename_customer':
        if (session.items == null || session.items!.trim().isEmpty) {
          return _askForField(session, 'renameTo');
        }
        return _executeRename(session, customer!, session.items!.trim());
      case 'debt':
      case 'payment':
      case 'return':
        final askItems = SettingsService.getBool(
          AppSettings.voiceAlwaysAskForItems,
          defaultValue: false,
        );
        if (askItems && session.items == null) {
          return _askForField(session, 'items');
        }
        return _saveTransaction(session, customer!);
      case 'add_account':
        return _addNewCustomer(session);
      default:
        return _fail('نية غير معروفة');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // اختيار مرشح من القائمة
  // ═══════════════════════════════════════════════════════════

  static Future<VoiceConversationResult> selectCandidate(int index, {String source = 'voice_screen'}) async {
    final session = _sessions[source];
    final candidates = _candidatesBySource[source] ?? const <Customer>[];
    if (session == null) return _fail('لا توجد جلسة نشطة');
    if (index < 0 || index >= candidates.length) return _fail('اختيار غير صالح');
    final chosen = candidates[index];
    session.matchedCustomer = _customerToMap(chosen);
    session.customerName = chosen.name;
    _candidatesBySource.remove(source);
    session.expectingField = null;
    session.resetAttemptsFor('customerName');

    // إعادة توجيه التنفيذ حسب النية الحالية
    switch (session.intent) {
      case 'statement': return _executeStatement(session, chosen);
      case 'block_account': return _executeBlock(session, chosen);
      case 'unblock_account': return _executeUnblock(session, chosen);
      case 'set_limit': return _executeSetLimit(session, chosen);
      case 'remove_limit': return _executeRemoveLimit(session, chosen);
      case 'print_statement': return _executePrint(session, chosen);
      case 'send_statement': return _executeSend(session, chosen);
      case 'last_transaction': return _executeLastTransaction(session, chosen);
      case 'delete_customer':
        session.expectingField = 'confirmDelete';
        final msg = VoicePromptsService.getPrompt(
          VoicePromptsService.pConfirmDeleteCustomer,
          vars: {'name': chosen.name},
        );
        return VoiceConversationResult(
          step: ConversationStep.askQuestion,
          prompt: msg,
          ttsMessage: msg,
          startListening: true,
        );
      case 'edit_customer': return _executeEdit(session, chosen);
      case 'rename_customer': return _askForField(session, 'renameTo');
      default:
        final askItems = SettingsService.getBool(
          AppSettings.voiceAlwaysAskForItems,
          defaultValue: false,
        );
        if (askItems && session.items == null) {
          return _askForField(session, 'items');
        }
        return _saveTransaction(session, chosen);
    }
  }

  // ═══════════════════════════════════════════════════════════
  // إضافة حساب جديد
  // ═══════════════════════════════════════════════════════════

  static Future<VoiceConversationResult> addNewCustomer({String source = 'voice_screen'}) async {
    final session = _sessions[source];
    if (session == null) return _fail('لا توجد جلسة نشطة');
    return _addNewCustomer(session);
  }

  static Future<VoiceConversationResult> _addNewCustomer(VoiceSession session) async {
    if (!_isCurrentSession(session)) return _cancelledResult();
    final name = session.customerName;
    if (name == null || name.trim().isEmpty) return _fail('اسم الحساب غير معروف');

    try {
      final db = DatabaseHelper.instance;
      final existing = await db.findAllByExactName(name.trim());
      if (!_isCurrentSession(session)) return _cancelledResult();
      if (existing.isNotEmpty) {
        return _handleUnknownCustomer(session, existing);
      }

      final accountant = await AccountantService.getAccountantName();
      if (!_isCurrentSession(session)) return _cancelledResult();
      final now = DateTime.now().toIso8601String();

      if (!_isCurrentSession(session)) return _cancelledResult();
      final customerId = await db.insertCustomer(Customer(
        name: name.trim(),
        accountType: session.accountType,
        createdBy: accountant,
        updatedBy: accountant,
        updatedAt: now,
        createdAt: now,
      ));

      if (!_isCurrentSession(session)) return _cancelledResult();
      final newCustomer = await db.getCustomer(customerId);
      if (!_isCurrentSession(session)) return _cancelledResult();
      if (newCustomer == null) return _fail('فشل إنشاء الحساب');

      if (!_isCurrentSession(session)) return _cancelledResult();
      await LoggerService.logCustomerAdded(newCustomer.name, accountant: accountant);
      if (!_isCurrentSession(session)) return _cancelledResult();
      session.markCompleted();
      
      return VoiceConversationResult(
        step: ConversationStep.saved,
        matchedCustomer: newCustomer,
        ttsMessage: VoicePromptsService.getResponse(
          VoicePromptsService.tAccountCreated,
          vars: {'name': newCustomer.name},
        ),
      );
    } catch (e) {
      debugPrint('❌ [VoiceConv] addNewCustomer: $e');
      return _fail('خطأ في إنشاء الحساب: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // التنفيذ الفعلي للعمليات (Execution)
  // ═══════════════════════════════════════════════════════════

  static Future<VoiceConversationResult> _executeStatement(VoiceSession session, Customer customer) async {
    if (!_isCurrentSession(session)) return _cancelledResult();
    final db = DatabaseHelper.instance;
    final balance = await db.customerBalance(customer.id!);
    if (!_isCurrentSession(session)) return _cancelledResult();
    final String tts;
    
    if (balance > 0) {
      tts = VoicePromptsService.getResponse(VoicePromptsService.tBalanceDebt, vars: {'customer': customer.name, 'balance': balance.toStringAsFixed(0), 'currency': session.currency});
    } else if (balance < 0) {
      tts = VoicePromptsService.getResponse(VoicePromptsService.tBalanceCredit, vars: {'customer': customer.name, 'balance': (-balance).toStringAsFixed(0), 'currency': session.currency});
    } else {
      tts = VoicePromptsService.getResponse(VoicePromptsService.tBalanceZero, vars: {'customer': customer.name});
    }
    session.markCompleted();
    return VoiceConversationResult(step: ConversationStep.saved, ttsMessage: tts);
  }

  static Future<VoiceConversationResult> _executeBlock(VoiceSession session, Customer customer) async {
    if (!_isCurrentSession(session)) return _cancelledResult();
    final changed = await DatabaseHelper.instance.setCustomerActive(customer.id!, false);
    if (!_isCurrentSession(session)) return _cancelledResult();
    if (changed <= 0) return _fail('تعذر إيقاف الحساب');
    session.markCompleted();
    return VoiceConversationResult(
      step: ConversationStep.saved,
      ttsMessage: VoicePromptsService.getResponse(VoicePromptsService.rAccountBlocked, vars: {'name': customer.name}),
    );
  }

  static Future<VoiceConversationResult> _executeUnblock(VoiceSession session, Customer customer) async {
    if (!_isCurrentSession(session)) return _cancelledResult();
    final changed = await DatabaseHelper.instance.setCustomerActive(customer.id!, true);
    if (!_isCurrentSession(session)) return _cancelledResult();
    if (changed <= 0) return _fail('تعذر تفعيل الحساب');
    session.markCompleted();
    return VoiceConversationResult(
      step: ConversationStep.saved,
      ttsMessage: VoicePromptsService.getResponse(VoicePromptsService.rAccountUnblocked, vars: {'name': customer.name}),
    );
  }

  static Future<VoiceConversationResult> _executeSetLimit(VoiceSession session, Customer customer) async {
    if (!_isCurrentSession(session)) return _cancelledResult();
    final changed = await DatabaseHelper.instance.updateCustomerFields(
      customer.id!,
      {'max_balance': session.amount},
    );
    if (!_isCurrentSession(session)) return _cancelledResult();
    if (changed <= 0) return _fail('تعذر تحديد سقف الحساب');
    session.markCompleted();
    return VoiceConversationResult(
      step: ConversationStep.saved,
      ttsMessage: VoicePromptsService.getResponse(
        VoicePromptsService.rLimitSet,
        vars: {
          'name': customer.name,
          'amount': session.amount!.toStringAsFixed(0),
          'currency': session.currency,
        },
      ),
    );
  }

  static Future<VoiceConversationResult> _executeRemoveLimit(VoiceSession session, Customer customer) async {
    if (!_isCurrentSession(session)) return _cancelledResult();
    final changed = await DatabaseHelper.instance.updateCustomerFields(
      customer.id!,
      {'max_balance': null},
    );
    if (!_isCurrentSession(session)) return _cancelledResult();
    if (changed <= 0) return _fail('تعذر إلغاء سقف الحساب');
    session.markCompleted();
    return VoiceConversationResult(
      step: ConversationStep.saved,
      ttsMessage: 'تم إلغاء سقف الحساب ${customer.name}',
    );
  }

  static Future<VoiceConversationResult> _executePrint(VoiceSession session, Customer customer) async {
    if (!_isCurrentSession(session)) return _cancelledResult();
    session.markCompleted();
    return VoiceConversationResult(
      step: ConversationStep.saved,
      ttsMessage: VoicePromptsService.getResponse(VoicePromptsService.rPrintingStatement, vars: {'name': customer.name}),
      targetScreen: 'print',
      matchedCustomer: customer,
      fromDate: session.fromDate,
      toDate: session.toDate,
    );
  }

  static Future<VoiceConversationResult> _executeSend(VoiceSession session, Customer customer) async {
    if (!_isCurrentSession(session)) return _cancelledResult();
    session.markCompleted();
    return VoiceConversationResult(
      step: ConversationStep.saved,
      ttsMessage: VoicePromptsService.getResponse(VoicePromptsService.rSendingStatement, vars: {'name': customer.name}),
      targetScreen: 'send',
      matchedCustomer: customer,
      fromDate: session.fromDate,
      toDate: session.toDate,
    );
  }

  static Future<VoiceConversationResult> _executeLastTransaction(VoiceSession session, Customer customer) async {
    if (!_isCurrentSession(session)) return _cancelledResult();
    final db = DatabaseHelper.instance;
    final txList = await db.customerTransactions(customer.id!);
    if (!_isCurrentSession(session)) return _cancelledResult();
    if (txList.isEmpty) {
      session.markCompleted();
      return VoiceConversationResult(step: ConversationStep.saved, ttsMessage: 'لا توجد عمليات لهذا الحساب');
    }
    final last = txList.first;
    final summary = '${last.type == 'debt' ? 'دين' : last.type == 'payment' ? 'سداد' : 'مرتجع'} ${last.amount.toStringAsFixed(0)} ${last.currency}';
    session.markCompleted();
    return VoiceConversationResult(
      step: ConversationStep.saved,
      ttsMessage: VoicePromptsService.getResponse(VoicePromptsService.rLastTransaction, vars: {'summary': summary}),
    );
  }

  static Future<VoiceConversationResult> _executeDelete(VoiceSession session) async {
    if (!_isCurrentSession(session)) return _cancelledResult();
    if (session.matchedCustomer == null) return _fail('لم يتم تحديد الحساب');
    final customer = Customer.fromMap(session.matchedCustomer!);
    final changed = await DatabaseHelper.instance.softDeleteCustomer(customer.id!);
    if (!_isCurrentSession(session)) return _cancelledResult();
    if (changed <= 0) return _fail('تعذر حذف الحساب');
    session.markCompleted();
    return VoiceConversationResult(
      step: ConversationStep.saved,
      ttsMessage: VoicePromptsService.getResponse(VoicePromptsService.rCustomerDeleted, vars: {'name': customer.name}),
    );
  }

  static Future<VoiceConversationResult> _executeRename(
    VoiceSession session,
    Customer customer,
    String newName,
  ) async {
    final normalizedName = newName.trim();
    if (normalizedName.isEmpty) {
      return _askForField(session, 'renameTo');
    }

    final matches = await DatabaseHelper.instance.findAllByExactName(normalizedName);
    if (!_isCurrentSession(session)) return _cancelledResult();
    if (matches.any((item) => item.id != customer.id)) {
      return _fail('يوجد حساب آخر بهذا الاسم بالفعل');
    }

    if (!_isCurrentSession(session)) return _cancelledResult();
    final changed = await DatabaseHelper.instance.updateCustomerFields(
      customer.id!,
      {'name': normalizedName},
    );
    if (!_isCurrentSession(session)) return _cancelledResult();
    if (changed <= 0) return _fail('تعذر تغيير اسم الحساب');

    session.markCompleted();
    return VoiceConversationResult(
      step: ConversationStep.saved,
      ttsMessage: 'تم تغيير اسم الحساب من ${customer.name} إلى $normalizedName',
    );
  }

  static Future<VoiceConversationResult> _executeEdit(VoiceSession session, Customer customer) async {
    session.markCompleted();
    return VoiceConversationResult(
      step: ConversationStep.saved,
      ttsMessage: VoicePromptsService.getResponse(VoicePromptsService.rEditSaved, vars: {'name': customer.name}),
      targetScreen: 'edit',
      matchedCustomer: customer,
    );
  }

  static Future<VoiceConversationResult> _executeStatistics(VoiceSession session) async {
    session.markCompleted();
    return VoiceConversationResult(
      step: ConversationStep.saved,
      ttsMessage: VoicePromptsService.getResponse(VoicePromptsService.rShowingStats),
      targetScreen: 'stats',
    );
  }

  static Future<VoiceConversationResult> _executeSearch(VoiceSession session, String query) async {
    session.markCompleted();
    return VoiceConversationResult(
      step: ConversationStep.saved,
      ttsMessage: VoicePromptsService.getResponse(VoicePromptsService.rSearchResults, vars: {'count': '...'}),
      targetScreen: 'search',
    );
  }

  // ═══════════════════════════════════════════════════════════
  // الحفظ
  // ═══════════════════════════════════════════════════════════

  static Future<VoiceConversationResult> _saveTransaction(
    VoiceSession session,
    Customer customer,
  ) async {
    try {
      // Refuse to enter the persistence path if this is no longer the active
      // conversation. This also prevents stale async callbacks from saving.
      if (!_isCurrentSession(session)) {
        return VoiceConversationResult(
          step: ConversationStep.failed,
          ttsMessage: 'تم إلغاء العملية',
          errorMessage: 'تم إلغاء العملية',
        );
      }

      final db = DatabaseHelper.instance;

      final fakeParsed = _FakeParsed(
        intent: session.intent!,
        amount: session.amount!,
        currency: session.currency,
        items: session.items ?? '',
      );

      // Capture the exact session object. If the user cancels while any
      // asynchronous validation is running, the session is removed from its source and the
      // transaction handler will refuse the final database insert.
      final ok = await TransactionHandler.save(
        customer: customer,
        parsed: fakeParsed,
        db: db,
        source: session.source,
        audioPath: null,
        canCommit: () =>
            _isCurrentSession(session),
      );

      if (!ok) {
        if (!identical(_sessions[session.source], session)) {
          return VoiceConversationResult(
            step: ConversationStep.failed,
            ttsMessage: 'تم إلغاء العملية',
            errorMessage: 'تم إلغاء العملية',
          );
        }
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

  static Future<(Customer?, List<Customer>)> _findCustomerWithCandidates(
    String name,
  ) async {
    final db = DatabaseHelper.instance;

    // 1. البحث الدقيق (يجد كل المطابقات)
    final exactList = await db.findAllByExactName(name);
    if (exactList.length == 1) {
      return (exactList.first, <Customer>[]);
    }
    if (exactList.length > 1) {
      return (null, exactList);
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
    _candidatesBySource[session.source] = candidates;

    final name = session.customerName ?? '';

    final prompt = VoicePromptsService.getPrompt(
      VoicePromptsService.pAskCustomerAmbiguous,
      vars: {'name': name},
    );

    if (candidates.isEmpty && session.intent == 'add_account') {
      final prompt = 'لا يوجد حساب باسم $name، هل تريد إضافة حساب جديد باسم $name؟';
      session.expectingField = 'confirmAddAccount';
      session.lastPrompt = prompt;
      return VoiceConversationResult(
        step: ConversationStep.askQuestion,
        prompt: prompt,
        ttsMessage: prompt,
        startListening: true,
      );
    }

    // أوامر إدارة الحساب لا تنشئ إشعارات "عملية معلقة" عند غياب الحساب.
    // نوضح للمستخدم أن الحساب غير موجود وننهي الطلب دون تغيير أي بيانات.
    const accountManagementIntents = {
      'block_account',
      'unblock_account',
      'set_limit',
      'remove_limit',
      'delete_customer',
      'edit_customer',
      'rename_customer',
      'statement',
      'print_statement',
      'send_statement',
      'last_transaction',
    };
    if (candidates.isEmpty && accountManagementIntents.contains(session.intent)) {
      final message = 'لا يوجد حساب باسم $name';
      cancelSession(source: session.source);
      return VoiceConversationResult(
        step: ConversationStep.failed,
        ttsMessage: message,
        errorMessage: message,
      );
    }

    final ttsMessage = candidates.isEmpty
        ? VoicePromptsService.getResponse(VoicePromptsService.rNoAccount, vars: {'name': name})
        : VoicePromptsService.getResponse(VoicePromptsService.tMultipleAccounts);

    return VoiceConversationResult(
      step: ConversationStep.showCandidates,
      prompt: prompt,
      ttsMessage: ttsMessage,
      candidates: candidates,
      startListening: candidates.isNotEmpty,
    );
  }

  /// يحدد هل فهم المحلل الإجابة الخاصة بالحقل المطلوب.
  static bool _hasAnswerForField(VoiceSession session, String field) {
    switch (field) {
      case 'intent':
      case 'intentForCustomer':
      case 'processType':
        return session.hasIntent;
      case 'customerName':
        return session.hasCustomer;
      case 'amount':
      case 'limitAmount':
        return session.hasAmount;
      case 'items':
        // النص الفارغ مقبول عند قول المستخدم "بدون بيان".
        return session.items != null;
      case 'renameTo':
        return session.items != null && session.items!.trim().isNotEmpty;
      case 'searchQuery':
        return true;
      default:
        return true;
    }
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
        prompt = VoicePromptsService.getPrompt(VoicePromptsService.pAskIntent);
        break;

      case 'intentForCustomer':
        prompt = VoicePromptsService.getPrompt(VoicePromptsService.pAskIntentForCustomer);
        break;

      case 'processType':
        prompt = VoicePromptsService.getPrompt(VoicePromptsService.pAskProcessType);
        break;

      case 'customerName':
        if (session.intent == 'statement' || session.intent == 'print_statement' || session.intent == 'send_statement') {
           prompt = 'أي حساب تريد؟'; // يمكن تعديلها من VoicePromptsService لاحقاً
        } else if (session.intent == 'block_account' || session.intent == 'unblock_account' || session.intent == 'delete_customer' || session.intent == 'edit_customer' || session.intent == 'rename_customer') {
           prompt = 'أي حساب تريد؟';
        } else if (session.intent == 'payment') {
          prompt = VoicePromptsService.getPrompt(VoicePromptsService.pAskCustomerPayment);
        } else if (session.intent == 'return') {
          prompt = VoicePromptsService.getPrompt(VoicePromptsService.pAskCustomerReturn);
        } else if (session.intent == 'debt') {
          prompt = VoicePromptsService.getPrompt(VoicePromptsService.pAskCustomerDebt);
        } else {
          prompt = VoicePromptsService.getPrompt(VoicePromptsService.pAskCustomerUnknown);
        }
        break;

      case 'amount':
        prompt = VoicePromptsService.getPrompt(VoicePromptsService.pAskAmount);
        break;

      case 'limitAmount':
        prompt = VoicePromptsService.getPrompt(VoicePromptsService.pAskLimitAmount);
        break;

      case 'items':
        prompt = VoicePromptsService.getPrompt(VoicePromptsService.pAskItems);
        break;

      case 'renameTo':
        prompt = 'ما الاسم الجديد للحساب؟';
        break;

      case 'searchQuery':
        prompt = VoicePromptsService.getPrompt(VoicePromptsService.pAskSearchQuery);
        break;

      case 'confirmAddAccount':
        prompt = 'هل تريد إضافة الحساب؟ قل نعم أو لا';
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

  static VoiceConversationResult _cancelledResult() => VoiceConversationResult(
        step: ConversationStep.failed,
        ttsMessage: 'تم إلغاء العملية',
        errorMessage: 'تم إلغاء العملية',
      );

  static VoiceConversationResult _fail(String error) {
    return VoiceConversationResult(
      step: ConversationStep.failed,
      errorMessage: error,
    );
  }

  static Future<VoiceConversationResult> _failAfterMaxAttempts(VoiceSession session) async {
    final maxRounds = SettingsService.getInt(
      AppSettings.voiceMaxConversationRounds,
      defaultValue: 3,
    );

    // لا نحفظ العمليات غير المكتملة ولا ننشئ سجلاً معلقاً عند فشل التعرف.
    cancelSession(source: session.source);

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
,
    ).hasMatch(answer);
  }

  /// قبول إجابات الرفض الواضحة فقط في تأكيد الإضافة والحذف.
  static bool isNegativeConfirmation(String text) {
    final answer = _normalizeConfirmationAnswer(text);
    const exactAnswers = {
      'لا', 'كلا', 'مش', 'لا تضف', 'لا تضيف', 'غير موافق',
      'no', 'nope',
    };
    return exactAnswers.contains(answer) ||
        RegExp(r'^(?:لا|كلا)\\s+(?:تحذف|تحذف الحساب|تضف|تضيف|تنفذ|تكمل)
    cancelSession(source: source);
    return VoiceConversationResult(
      step: ConversationStep.failed,
      ttsMessage: 'تم إلغاء العملية',
      errorMessage: 'تم إلغاء العملية',
    );
  }

  static Future<VoiceConversationResult> processText(
    String text, {
    String? expecting,
    String source = 'voice_screen',
  }) async {
    // يجب أن يسبق الإلغاء كل التحليلات، خصوصاً تحليل البيان وتأكيد الحذف.
    if (isCancelCommand(text)) return cancelFromVoice(source: source);

    if (!hasActiveSessionFor(source)) startSession(source: source);
    final session = _sessions[source]!;

    if (session.isCompleted) {
      return _fail('الجلسة منتهية بالفعل');
    }

    // 🆕 1. فحص الاستعلام المباشر (كشف حساب، رصيد، إلخ) إذا لم نكن في منتصف حوار
    if (expecting == null &&
        session.collectedTexts.isEmpty &&
        session.expectingField == null) {
      try {
        if (QueryService.isQuery(text)) {
          final qResult = await QueryService.query(text);
          if (!_isCurrentSession(session)) return _cancelledResult();
          session.markCompleted();
          return VoiceConversationResult(
            step: ConversationStep.saved,
            ttsMessage: qResult.spokenAnswer,
            startListening: false,
          );
        }
      } catch (e) {
        debugPrint('❌ [VoiceConv] Query error: $e');
      }
    }

    final prevExpecting = session.expectingField ?? expecting;
    if (prevExpecting != null) {
      // نسجل المحاولة، لكن لا نرفض الإجابة قبل تحليلها؛ فقد تكون الإجابة
      // الصحيحة هي المحاولة الثالثة.
      session.incrementAttempt(prevExpecting);
    }

    // تأكيد إضافة حساب جديد عندما لا يوجد حساب بالاسم المنطوق.
    if (prevExpecting == 'confirmAddAccount' ||
        prevExpecting == 'confirmDelete') {
      final answer = text.trim().toLowerCase();
      const yes = [
        'نعم', 'ايوه', 'أيوه', 'اي', 'أجل', 'اجل', 'أكيد', 'اكيد',
        'نعم أضف', 'اضف', 'موافق', 'تمام',
      ];
      const no = [
        'لا', 'كلا', 'مش', 'لا تضف', 'لا تضيف', 'غير موافق',
      ];

      if (yes.contains(answer)) {
        if (prevExpecting == 'confirmAddAccount') {
          return _addNewCustomer(session);
        }
        return _executeDelete(session);
      }

      if (no.contains(answer)) {
        cancelSession(source: session.source);
        final message = prevExpecting == 'confirmAddAccount'
            ? 'تم إلغاء إضافة الحساب'
            : 'تم إلغاء الحذف';
        return VoiceConversationResult(
          step: ConversationStep.failed,
          ttsMessage: message,
          errorMessage: message,
        );
      }

      // الصمت أو الإجابة غير الواضحة لا تعني الرفض؛ أعد السؤال حتى 3 مرات.
      final maxRounds = SettingsService.getInt(
        AppSettings.voiceMaxConversationRounds,
        defaultValue: 3,
      );
      if (session.attemptsFor(prevExpecting!) >= maxRounds) {
        return _failAfterMaxAttempts(session);
      }

      final message = prevExpecting == 'confirmAddAccount'
          ? 'هل تريد إضافة الحساب؟ قل نعم أو لا'
          : 'هل أنت متأكد من حذف الحساب؟ قل نعم أو لا';
      session.expectingField = prevExpecting;
      session.lastPrompt = message;
      return VoiceConversationResult(
        step: ConversationStep.askQuestion,
        prompt: message,
        ttsMessage: message,
        startListening: true,
      );
    }

    // 3. تحليل النص
    final partial = ParserService.parsePartial(
      text,
      expecting: prevExpecting,
    );
    session.merge(partial);
    session.expectingField = null;

    // لا نلغي إلا بعد ثلاث إجابات غير مفهومة فعلاً، وليس قبل تحليل الإجابة.
    if (prevExpecting != null &&
        !_hasAnswerForField(session, prevExpecting)) {
      final maxRounds = SettingsService.getInt(
        AppSettings.voiceMaxConversationRounds,
        defaultValue: 3,
      );
      if (session.attemptsFor(prevExpecting) >= maxRounds) {
        return _failAfterMaxAttempts(session);
      }
    }

    debugPrint('🎤 [VoiceConv] After merge: ${session.summary}');

    // ═══════════════════════════════════════════════════════════
    // 4. فحص الحقول الناقصة حسب النية
    // ═══════════════════════════════════════════════════════════

    // أ. إذا لم تكن هناك نية ولكن يوجد اسم عميل (فقط "محمد")
    if (!session.hasIntent && session.hasCustomer) {
      return _askForField(session, 'intentForCustomer');
    }

    if (!session.hasIntent) {
      return _askForField(session, 'intent');
    }

    // ب. عملية عامة (process): اسأل عن النوع
    if (session.intent == 'process') {
      return _askForField(session, 'processType');
    }

    // ج. النوايا التي لا تحتاج اسم عميل (إحصائيات)
    if (session.intent == 'statistics') {
      return _executeStatistics(session);
    }

    // د. البحث يحتاج كلمة بحث فقط
    if (session.intent == 'search') {
      if (prevExpecting == 'searchQuery') {
        return _executeSearch(session, text);
      }
      return _askForField(session, 'searchQuery');
    }

    // هـ. النوايا التي تحتاج اسم عميل فقط
    final needsCustomerOnly = [
      'statement',
      'block_account',
      'unblock_account',
      'remove_limit',
      'print_statement',
      'send_statement',
      'last_transaction',
      'delete_customer',
      'edit_customer',
      'rename_customer',
    ];
    if (needsCustomerOnly.contains(session.intent) && !session.hasCustomer) {
      return _askForField(session, 'customerName');
    }

    // و. تحديد السقف يحتاج اسم ومبلغ
    if (session.intent == 'set_limit') {
      if (!session.hasCustomer) return _askForField(session, 'customerName');
      if (!session.hasAmount) return _askForField(session, 'limitAmount');
    }

    // ز. العمليات المالية تحتاج اسم ومبلغ
    if (['debt', 'payment', 'return'].contains(session.intent)) {
      if (!session.hasCustomer) return _askForField(session, 'customerName');
      if (!session.hasAmount) return _askForField(session, 'amount');
    }

    // ح. إضافة حساب
    if (session.intent == 'add_account' && !session.hasCustomer) {
      return _askForField(session, 'customerName');
    }

    // ═══════════════════════════════════════════════════════════
    // 5. البحث عن العميل (إذا لزم)
    // ═══════════════════════════════════════════════════════════
    Customer? customer;
    if (session.hasCustomer) {
      final found = await _findCustomerWithCandidates(session.customerName!);
      if (!_isCurrentSession(session)) return _cancelledResult();
      if (found.$1 == null) {
        return _handleUnknownCustomer(session, found.$2);
      }
      customer = found.$1!;
      session.matchedCustomer = _customerToMap(customer);
    }

    // ═══════════════════════════════════════════════════════════
    // 6. التنفيذ بناءً على النية
    // ═══════════════════════════════════════════════════════════
    switch (session.intent) {
      case 'statement':
        return _executeStatement(session, customer!);
      case 'block_account':
        return _executeBlock(session, customer!);
      case 'unblock_account':
        return _executeUnblock(session, customer!);
      case 'set_limit':
        return _executeSetLimit(session, customer!);
      case 'remove_limit':
        return _executeRemoveLimit(session, customer!);
      case 'print_statement':
        return _executePrint(session, customer!);
      case 'send_statement':
        return _executeSend(session, customer!);
      case 'last_transaction':
        return _executeLastTransaction(session, customer!);
      case 'delete_customer':
        session.expectingField = 'confirmDelete';
        final msg = VoicePromptsService.getPrompt(
          VoicePromptsService.pConfirmDeleteCustomer,
          vars: {'name': customer!.name},
        );
        return VoiceConversationResult(
          step: ConversationStep.askQuestion,
          prompt: msg,
          ttsMessage: msg,
          startListening: true,
        );
      case 'edit_customer':
        return _executeEdit(session, customer!);
      case 'rename_customer':
        if (session.items == null || session.items!.trim().isEmpty) {
          return _askForField(session, 'renameTo');
        }
        return _executeRename(session, customer!, session.items!.trim());
      case 'debt':
      case 'payment':
      case 'return':
        final askItems = SettingsService.getBool(
          AppSettings.voiceAlwaysAskForItems,
          defaultValue: false,
        );
        if (askItems && session.items == null) {
          return _askForField(session, 'items');
        }
        return _saveTransaction(session, customer!);
      case 'add_account':
        return _addNewCustomer(session);
      default:
        return _fail('نية غير معروفة');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // اختيار مرشح من القائمة
  // ═══════════════════════════════════════════════════════════

  static Future<VoiceConversationResult> selectCandidate(int index, {String source = 'voice_screen'}) async {
    final session = _sessions[source];
    final candidates = _candidatesBySource[source] ?? const <Customer>[];
    if (session == null) return _fail('لا توجد جلسة نشطة');
    if (index < 0 || index >= candidates.length) return _fail('اختيار غير صالح');
    final chosen = candidates[index];
    session.matchedCustomer = _customerToMap(chosen);
    session.customerName = chosen.name;
    _candidatesBySource.remove(source);
    session.expectingField = null;
    session.resetAttemptsFor('customerName');

    // إعادة توجيه التنفيذ حسب النية الحالية
    switch (session.intent) {
      case 'statement': return _executeStatement(session, chosen);
      case 'block_account': return _executeBlock(session, chosen);
      case 'unblock_account': return _executeUnblock(session, chosen);
      case 'set_limit': return _executeSetLimit(session, chosen);
      case 'remove_limit': return _executeRemoveLimit(session, chosen);
      case 'print_statement': return _executePrint(session, chosen);
      case 'send_statement': return _executeSend(session, chosen);
      case 'last_transaction': return _executeLastTransaction(session, chosen);
      case 'delete_customer':
        session.expectingField = 'confirmDelete';
        final msg = VoicePromptsService.getPrompt(
          VoicePromptsService.pConfirmDeleteCustomer,
          vars: {'name': chosen.name},
        );
        return VoiceConversationResult(
          step: ConversationStep.askQuestion,
          prompt: msg,
          ttsMessage: msg,
          startListening: true,
        );
      case 'edit_customer': return _executeEdit(session, chosen);
      case 'rename_customer': return _askForField(session, 'renameTo');
      default:
        final askItems = SettingsService.getBool(
          AppSettings.voiceAlwaysAskForItems,
          defaultValue: false,
        );
        if (askItems && session.items == null) {
          return _askForField(session, 'items');
        }
        return _saveTransaction(session, chosen);
    }
  }

  // ═══════════════════════════════════════════════════════════
  // إضافة حساب جديد
  // ═══════════════════════════════════════════════════════════

  static Future<VoiceConversationResult> addNewCustomer({String source = 'voice_screen'}) async {
    final session = _sessions[source];
    if (session == null) return _fail('لا توجد جلسة نشطة');
    return _addNewCustomer(session);
  }

  static Future<VoiceConversationResult> _addNewCustomer(VoiceSession session) async {
    if (!_isCurrentSession(session)) return _cancelledResult();
    final name = session.customerName;
    if (name == null || name.trim().isEmpty) return _fail('اسم الحساب غير معروف');

    try {
      final db = DatabaseHelper.instance;
      final existing = await db.findAllByExactName(name.trim());
      if (!_isCurrentSession(session)) return _cancelledResult();
      if (existing.isNotEmpty) {
        return _handleUnknownCustomer(session, existing);
      }

      final accountant = await AccountantService.getAccountantName();
      if (!_isCurrentSession(session)) return _cancelledResult();
      final now = DateTime.now().toIso8601String();

      if (!_isCurrentSession(session)) return _cancelledResult();
      final customerId = await db.insertCustomer(Customer(
        name: name.trim(),
        accountType: session.accountType,
        createdBy: accountant,
        updatedBy: accountant,
        updatedAt: now,
        createdAt: now,
      ));

      if (!_isCurrentSession(session)) return _cancelledResult();
      final newCustomer = await db.getCustomer(customerId);
      if (!_isCurrentSession(session)) return _cancelledResult();
      if (newCustomer == null) return _fail('فشل إنشاء الحساب');

      if (!_isCurrentSession(session)) return _cancelledResult();
      await LoggerService.logCustomerAdded(newCustomer.name, accountant: accountant);
      if (!_isCurrentSession(session)) return _cancelledResult();
      session.markCompleted();
      
      return VoiceConversationResult(
        step: ConversationStep.saved,
        matchedCustomer: newCustomer,
        ttsMessage: VoicePromptsService.getResponse(
          VoicePromptsService.tAccountCreated,
          vars: {'name': newCustomer.name},
        ),
      );
    } catch (e) {
      debugPrint('❌ [VoiceConv] addNewCustomer: $e');
      return _fail('خطأ في إنشاء الحساب: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // التنفيذ الفعلي للعمليات (Execution)
  // ═══════════════════════════════════════════════════════════

  static Future<VoiceConversationResult> _executeStatement(VoiceSession session, Customer customer) async {
    if (!_isCurrentSession(session)) return _cancelledResult();
    final db = DatabaseHelper.instance;
    final balance = await db.customerBalance(customer.id!);
    if (!_isCurrentSession(session)) return _cancelledResult();
    final String tts;
    
    if (balance > 0) {
      tts = VoicePromptsService.getResponse(VoicePromptsService.tBalanceDebt, vars: {'customer': customer.name, 'balance': balance.toStringAsFixed(0), 'currency': session.currency});
    } else if (balance < 0) {
      tts = VoicePromptsService.getResponse(VoicePromptsService.tBalanceCredit, vars: {'customer': customer.name, 'balance': (-balance).toStringAsFixed(0), 'currency': session.currency});
    } else {
      tts = VoicePromptsService.getResponse(VoicePromptsService.tBalanceZero, vars: {'customer': customer.name});
    }
    session.markCompleted();
    return VoiceConversationResult(step: ConversationStep.saved, ttsMessage: tts);
  }

  static Future<VoiceConversationResult> _executeBlock(VoiceSession session, Customer customer) async {
    if (!_isCurrentSession(session)) return _cancelledResult();
    final changed = await DatabaseHelper.instance.setCustomerActive(customer.id!, false);
    if (!_isCurrentSession(session)) return _cancelledResult();
    if (changed <= 0) return _fail('تعذر إيقاف الحساب');
    session.markCompleted();
    return VoiceConversationResult(
      step: ConversationStep.saved,
      ttsMessage: VoicePromptsService.getResponse(VoicePromptsService.rAccountBlocked, vars: {'name': customer.name}),
    );
  }

  static Future<VoiceConversationResult> _executeUnblock(VoiceSession session, Customer customer) async {
    if (!_isCurrentSession(session)) return _cancelledResult();
    final changed = await DatabaseHelper.instance.setCustomerActive(customer.id!, true);
    if (!_isCurrentSession(session)) return _cancelledResult();
    if (changed <= 0) return _fail('تعذر تفعيل الحساب');
    session.markCompleted();
    return VoiceConversationResult(
      step: ConversationStep.saved,
      ttsMessage: VoicePromptsService.getResponse(VoicePromptsService.rAccountUnblocked, vars: {'name': customer.name}),
    );
  }

  static Future<VoiceConversationResult> _executeSetLimit(VoiceSession session, Customer customer) async {
    if (!_isCurrentSession(session)) return _cancelledResult();
    final changed = await DatabaseHelper.instance.updateCustomerFields(
      customer.id!,
      {'max_balance': session.amount},
    );
    if (!_isCurrentSession(session)) return _cancelledResult();
    if (changed <= 0) return _fail('تعذر تحديد سقف الحساب');
    session.markCompleted();
    return VoiceConversationResult(
      step: ConversationStep.saved,
      ttsMessage: VoicePromptsService.getResponse(
        VoicePromptsService.rLimitSet,
        vars: {
          'name': customer.name,
          'amount': session.amount!.toStringAsFixed(0),
          'currency': session.currency,
        },
      ),
    );
  }

  static Future<VoiceConversationResult> _executeRemoveLimit(VoiceSession session, Customer customer) async {
    if (!_isCurrentSession(session)) return _cancelledResult();
    final changed = await DatabaseHelper.instance.updateCustomerFields(
      customer.id!,
      {'max_balance': null},
    );
    if (!_isCurrentSession(session)) return _cancelledResult();
    if (changed <= 0) return _fail('تعذر إلغاء سقف الحساب');
    session.markCompleted();
    return VoiceConversationResult(
      step: ConversationStep.saved,
      ttsMessage: 'تم إلغاء سقف الحساب ${customer.name}',
    );
  }

  static Future<VoiceConversationResult> _executePrint(VoiceSession session, Customer customer) async {
    if (!_isCurrentSession(session)) return _cancelledResult();
    session.markCompleted();
    return VoiceConversationResult(
      step: ConversationStep.saved,
      ttsMessage: VoicePromptsService.getResponse(VoicePromptsService.rPrintingStatement, vars: {'name': customer.name}),
      targetScreen: 'print',
      matchedCustomer: customer,
      fromDate: session.fromDate,
      toDate: session.toDate,
    );
  }

  static Future<VoiceConversationResult> _executeSend(VoiceSession session, Customer customer) async {
    if (!_isCurrentSession(session)) return _cancelledResult();
    session.markCompleted();
    return VoiceConversationResult(
      step: ConversationStep.saved,
      ttsMessage: VoicePromptsService.getResponse(VoicePromptsService.rSendingStatement, vars: {'name': customer.name}),
      targetScreen: 'send',
      matchedCustomer: customer,
      fromDate: session.fromDate,
      toDate: session.toDate,
    );
  }

  static Future<VoiceConversationResult> _executeLastTransaction(VoiceSession session, Customer customer) async {
    if (!_isCurrentSession(session)) return _cancelledResult();
    final db = DatabaseHelper.instance;
    final txList = await db.customerTransactions(customer.id!);
    if (!_isCurrentSession(session)) return _cancelledResult();
    if (txList.isEmpty) {
      session.markCompleted();
      return VoiceConversationResult(step: ConversationStep.saved, ttsMessage: 'لا توجد عمليات لهذا الحساب');
    }
    final last = txList.first;
    final summary = '${last.type == 'debt' ? 'دين' : last.type == 'payment' ? 'سداد' : 'مرتجع'} ${last.amount.toStringAsFixed(0)} ${last.currency}';
    session.markCompleted();
    return VoiceConversationResult(
      step: ConversationStep.saved,
      ttsMessage: VoicePromptsService.getResponse(VoicePromptsService.rLastTransaction, vars: {'summary': summary}),
    );
  }

  static Future<VoiceConversationResult> _executeDelete(VoiceSession session) async {
    if (!_isCurrentSession(session)) return _cancelledResult();
    if (session.matchedCustomer == null) return _fail('لم يتم تحديد الحساب');
    final customer = Customer.fromMap(session.matchedCustomer!);
    final changed = await DatabaseHelper.instance.softDeleteCustomer(customer.id!);
    if (!_isCurrentSession(session)) return _cancelledResult();
    if (changed <= 0) return _fail('تعذر حذف الحساب');
    session.markCompleted();
    return VoiceConversationResult(
      step: ConversationStep.saved,
      ttsMessage: VoicePromptsService.getResponse(VoicePromptsService.rCustomerDeleted, vars: {'name': customer.name}),
    );
  }

  static Future<VoiceConversationResult> _executeRename(
    VoiceSession session,
    Customer customer,
    String newName,
  ) async {
    final normalizedName = newName.trim();
    if (normalizedName.isEmpty) {
      return _askForField(session, 'renameTo');
    }

    final matches = await DatabaseHelper.instance.findAllByExactName(normalizedName);
    if (!_isCurrentSession(session)) return _cancelledResult();
    if (matches.any((item) => item.id != customer.id)) {
      return _fail('يوجد حساب آخر بهذا الاسم بالفعل');
    }

    if (!_isCurrentSession(session)) return _cancelledResult();
    final changed = await DatabaseHelper.instance.updateCustomerFields(
      customer.id!,
      {'name': normalizedName},
    );
    if (!_isCurrentSession(session)) return _cancelledResult();
    if (changed <= 0) return _fail('تعذر تغيير اسم الحساب');

    session.markCompleted();
    return VoiceConversationResult(
      step: ConversationStep.saved,
      ttsMessage: 'تم تغيير اسم الحساب من ${customer.name} إلى $normalizedName',
    );
  }

  static Future<VoiceConversationResult> _executeEdit(VoiceSession session, Customer customer) async {
    session.markCompleted();
    return VoiceConversationResult(
      step: ConversationStep.saved,
      ttsMessage: VoicePromptsService.getResponse(VoicePromptsService.rEditSaved, vars: {'name': customer.name}),
      targetScreen: 'edit',
      matchedCustomer: customer,
    );
  }

  static Future<VoiceConversationResult> _executeStatistics(VoiceSession session) async {
    session.markCompleted();
    return VoiceConversationResult(
      step: ConversationStep.saved,
      ttsMessage: VoicePromptsService.getResponse(VoicePromptsService.rShowingStats),
      targetScreen: 'stats',
    );
  }

  static Future<VoiceConversationResult> _executeSearch(VoiceSession session, String query) async {
    session.markCompleted();
    return VoiceConversationResult(
      step: ConversationStep.saved,
      ttsMessage: VoicePromptsService.getResponse(VoicePromptsService.rSearchResults, vars: {'count': '...'}),
      targetScreen: 'search',
    );
  }

  // ═══════════════════════════════════════════════════════════
  // الحفظ
  // ═══════════════════════════════════════════════════════════

  static Future<VoiceConversationResult> _saveTransaction(
    VoiceSession session,
    Customer customer,
  ) async {
    try {
      // Refuse to enter the persistence path if this is no longer the active
      // conversation. This also prevents stale async callbacks from saving.
      if (!_isCurrentSession(session)) {
        return VoiceConversationResult(
          step: ConversationStep.failed,
          ttsMessage: 'تم إلغاء العملية',
          errorMessage: 'تم إلغاء العملية',
        );
      }

      final db = DatabaseHelper.instance;

      final fakeParsed = _FakeParsed(
        intent: session.intent!,
        amount: session.amount!,
        currency: session.currency,
        items: session.items ?? '',
      );

      // Capture the exact session object. If the user cancels while any
      // asynchronous validation is running, the session is removed from its source and the
      // transaction handler will refuse the final database insert.
      final ok = await TransactionHandler.save(
        customer: customer,
        parsed: fakeParsed,
        db: db,
        source: session.source,
        audioPath: null,
        canCommit: () =>
            _isCurrentSession(session),
      );

      if (!ok) {
        if (!identical(_sessions[session.source], session)) {
          return VoiceConversationResult(
            step: ConversationStep.failed,
            ttsMessage: 'تم إلغاء العملية',
            errorMessage: 'تم إلغاء العملية',
          );
        }
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

  static Future<(Customer?, List<Customer>)> _findCustomerWithCandidates(
    String name,
  ) async {
    final db = DatabaseHelper.instance;

    // 1. البحث الدقيق (يجد كل المطابقات)
    final exactList = await db.findAllByExactName(name);
    if (exactList.length == 1) {
      return (exactList.first, <Customer>[]);
    }
    if (exactList.length > 1) {
      return (null, exactList);
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
    _candidatesBySource[session.source] = candidates;

    final name = session.customerName ?? '';

    final prompt = VoicePromptsService.getPrompt(
      VoicePromptsService.pAskCustomerAmbiguous,
      vars: {'name': name},
    );

    if (candidates.isEmpty && session.intent == 'add_account') {
      final prompt = 'لا يوجد حساب باسم $name، هل تريد إضافة حساب جديد باسم $name؟';
      session.expectingField = 'confirmAddAccount';
      session.lastPrompt = prompt;
      return VoiceConversationResult(
        step: ConversationStep.askQuestion,
        prompt: prompt,
        ttsMessage: prompt,
        startListening: true,
      );
    }

    // أوامر إدارة الحساب لا تنشئ إشعارات "عملية معلقة" عند غياب الحساب.
    // نوضح للمستخدم أن الحساب غير موجود وننهي الطلب دون تغيير أي بيانات.
    const accountManagementIntents = {
      'block_account',
      'unblock_account',
      'set_limit',
      'remove_limit',
      'delete_customer',
      'edit_customer',
      'rename_customer',
      'statement',
      'print_statement',
      'send_statement',
      'last_transaction',
    };
    if (candidates.isEmpty && accountManagementIntents.contains(session.intent)) {
      final message = 'لا يوجد حساب باسم $name';
      cancelSession(source: session.source);
      return VoiceConversationResult(
        step: ConversationStep.failed,
        ttsMessage: message,
        errorMessage: message,
      );
    }

    final ttsMessage = candidates.isEmpty
        ? VoicePromptsService.getResponse(VoicePromptsService.rNoAccount, vars: {'name': name})
        : VoicePromptsService.getResponse(VoicePromptsService.tMultipleAccounts);

    return VoiceConversationResult(
      step: ConversationStep.showCandidates,
      prompt: prompt,
      ttsMessage: ttsMessage,
      candidates: candidates,
      startListening: candidates.isNotEmpty,
    );
  }

  /// يحدد هل فهم المحلل الإجابة الخاصة بالحقل المطلوب.
  static bool _hasAnswerForField(VoiceSession session, String field) {
    switch (field) {
      case 'intent':
      case 'intentForCustomer':
      case 'processType':
        return session.hasIntent;
      case 'customerName':
        return session.hasCustomer;
      case 'amount':
      case 'limitAmount':
        return session.hasAmount;
      case 'items':
        // النص الفارغ مقبول عند قول المستخدم "بدون بيان".
        return session.items != null;
      case 'renameTo':
        return session.items != null && session.items!.trim().isNotEmpty;
      case 'searchQuery':
        return true;
      default:
        return true;
    }
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
        prompt = VoicePromptsService.getPrompt(VoicePromptsService.pAskIntent);
        break;

      case 'intentForCustomer':
        prompt = VoicePromptsService.getPrompt(VoicePromptsService.pAskIntentForCustomer);
        break;

      case 'processType':
        prompt = VoicePromptsService.getPrompt(VoicePromptsService.pAskProcessType);
        break;

      case 'customerName':
        if (session.intent == 'statement' || session.intent == 'print_statement' || session.intent == 'send_statement') {
           prompt = 'أي حساب تريد؟'; // يمكن تعديلها من VoicePromptsService لاحقاً
        } else if (session.intent == 'block_account' || session.intent == 'unblock_account' || session.intent == 'delete_customer' || session.intent == 'edit_customer' || session.intent == 'rename_customer') {
           prompt = 'أي حساب تريد؟';
        } else if (session.intent == 'payment') {
          prompt = VoicePromptsService.getPrompt(VoicePromptsService.pAskCustomerPayment);
        } else if (session.intent == 'return') {
          prompt = VoicePromptsService.getPrompt(VoicePromptsService.pAskCustomerReturn);
        } else if (session.intent == 'debt') {
          prompt = VoicePromptsService.getPrompt(VoicePromptsService.pAskCustomerDebt);
        } else {
          prompt = VoicePromptsService.getPrompt(VoicePromptsService.pAskCustomerUnknown);
        }
        break;

      case 'amount':
        prompt = VoicePromptsService.getPrompt(VoicePromptsService.pAskAmount);
        break;

      case 'limitAmount':
        prompt = VoicePromptsService.getPrompt(VoicePromptsService.pAskLimitAmount);
        break;

      case 'items':
        prompt = VoicePromptsService.getPrompt(VoicePromptsService.pAskItems);
        break;

      case 'renameTo':
        prompt = 'ما الاسم الجديد للحساب؟';
        break;

      case 'searchQuery':
        prompt = VoicePromptsService.getPrompt(VoicePromptsService.pAskSearchQuery);
        break;

      case 'confirmAddAccount':
        prompt = 'هل تريد إضافة الحساب؟ قل نعم أو لا';
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

  static VoiceConversationResult _cancelledResult() => VoiceConversationResult(
        step: ConversationStep.failed,
        ttsMessage: 'تم إلغاء العملية',
        errorMessage: 'تم إلغاء العملية',
      );

  static VoiceConversationResult _fail(String error) {
    return VoiceConversationResult(
      step: ConversationStep.failed,
      errorMessage: error,
    );
  }

  static Future<VoiceConversationResult> _failAfterMaxAttempts(VoiceSession session) async {
    final maxRounds = SettingsService.getInt(
      AppSettings.voiceMaxConversationRounds,
      defaultValue: 3,
    );

    // لا نحفظ العمليات غير المكتملة ولا ننشئ سجلاً معلقاً عند فشل التعرف.
    cancelSession(source: session.source);

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
)
            .hasMatch(answer);
  }

  /// إلغاء الجلسة بالكامل وإرجاع رسالة واضحة دون حفظ أي بيانات.
  static VoiceConversationResult cancelFromVoice({String source = 'voice_screen'}) {
    cancelSession(source: source);
    return VoiceConversationResult(
      step: ConversationStep.failed,
      ttsMessage: 'تم إلغاء العملية',
      errorMessage: 'تم إلغاء العملية',
    );
  }

  static Future<VoiceConversationResult> processText(
    String text, {
    String? expecting,
    String source = 'voice_screen',
  }) async {
    // يجب أن يسبق الإلغاء كل التحليلات، خصوصاً تحليل البيان وتأكيد الحذف.
    if (isCancelCommand(text)) return cancelFromVoice(source: source);

    if (!hasActiveSessionFor(source)) startSession(source: source);
    final session = _sessions[source]!;

    if (session.isCompleted) {
      return _fail('الجلسة منتهية بالفعل');
    }

    // 🆕 1. فحص الاستعلام المباشر (كشف حساب، رصيد، إلخ) إذا لم نكن في منتصف حوار
    if (expecting == null &&
        session.collectedTexts.isEmpty &&
        session.expectingField == null) {
      try {
        if (QueryService.isQuery(text)) {
          final qResult = await QueryService.query(text);
          if (!_isCurrentSession(session)) return _cancelledResult();
          session.markCompleted();
          return VoiceConversationResult(
            step: ConversationStep.saved,
            ttsMessage: qResult.spokenAnswer,
            startListening: false,
          );
        }
      } catch (e) {
        debugPrint('❌ [VoiceConv] Query error: $e');
      }
    }

    final prevExpecting = session.expectingField ?? expecting;
    if (prevExpecting != null) {
      // نسجل المحاولة، لكن لا نرفض الإجابة قبل تحليلها؛ فقد تكون الإجابة
      // الصحيحة هي المحاولة الثالثة.
      session.incrementAttempt(prevExpecting);
    }

    // تأكيد إضافة حساب جديد عندما لا يوجد حساب بالاسم المنطوق.
    if (prevExpecting == 'confirmAddAccount' ||
        prevExpecting == 'confirmDelete') {
      final answer = text.trim().toLowerCase();
      const yes = [
        'نعم', 'ايوه', 'أيوه', 'اي', 'أجل', 'اجل', 'أكيد', 'اكيد',
        'نعم أضف', 'اضف', 'موافق', 'تمام',
      ];
      const no = [
        'لا', 'كلا', 'مش', 'لا تضف', 'لا تضيف', 'غير موافق',
      ];

      if (yes.contains(answer)) {
        if (prevExpecting == 'confirmAddAccount') {
          return _addNewCustomer(session);
        }
        return _executeDelete(session);
      }

      if (no.contains(answer)) {
        cancelSession(source: session.source);
        final message = prevExpecting == 'confirmAddAccount'
            ? 'تم إلغاء إضافة الحساب'
            : 'تم إلغاء الحذف';
        return VoiceConversationResult(
          step: ConversationStep.failed,
          ttsMessage: message,
          errorMessage: message,
        );
      }

      // الصمت أو الإجابة غير الواضحة لا تعني الرفض؛ أعد السؤال حتى 3 مرات.
      final maxRounds = SettingsService.getInt(
        AppSettings.voiceMaxConversationRounds,
        defaultValue: 3,
      );
      if (session.attemptsFor(prevExpecting!) >= maxRounds) {
        return _failAfterMaxAttempts(session);
      }

      final message = prevExpecting == 'confirmAddAccount'
          ? 'هل تريد إضافة الحساب؟ قل نعم أو لا'
          : 'هل أنت متأكد من حذف الحساب؟ قل نعم أو لا';
      session.expectingField = prevExpecting;
      session.lastPrompt = message;
      return VoiceConversationResult(
        step: ConversationStep.askQuestion,
        prompt: message,
        ttsMessage: message,
        startListening: true,
      );
    }

    // 3. تحليل النص
    final partial = ParserService.parsePartial(
      text,
      expecting: prevExpecting,
    );
    session.merge(partial);
    session.expectingField = null;

    // لا نلغي إلا بعد ثلاث إجابات غير مفهومة فعلاً، وليس قبل تحليل الإجابة.
    if (prevExpecting != null &&
        !_hasAnswerForField(session, prevExpecting)) {
      final maxRounds = SettingsService.getInt(
        AppSettings.voiceMaxConversationRounds,
        defaultValue: 3,
      );
      if (session.attemptsFor(prevExpecting) >= maxRounds) {
        return _failAfterMaxAttempts(session);
      }
    }

    debugPrint('🎤 [VoiceConv] After merge: ${session.summary}');

    // ═══════════════════════════════════════════════════════════
    // 4. فحص الحقول الناقصة حسب النية
    // ═══════════════════════════════════════════════════════════

    // أ. إذا لم تكن هناك نية ولكن يوجد اسم عميل (فقط "محمد")
    if (!session.hasIntent && session.hasCustomer) {
      return _askForField(session, 'intentForCustomer');
    }

    if (!session.hasIntent) {
      return _askForField(session, 'intent');
    }

    // ب. عملية عامة (process): اسأل عن النوع
    if (session.intent == 'process') {
      return _askForField(session, 'processType');
    }

    // ج. النوايا التي لا تحتاج اسم عميل (إحصائيات)
    if (session.intent == 'statistics') {
      return _executeStatistics(session);
    }

    // د. البحث يحتاج كلمة بحث فقط
    if (session.intent == 'search') {
      if (prevExpecting == 'searchQuery') {
        return _executeSearch(session, text);
      }
      return _askForField(session, 'searchQuery');
    }

    // هـ. النوايا التي تحتاج اسم عميل فقط
    final needsCustomerOnly = [
      'statement',
      'block_account',
      'unblock_account',
      'remove_limit',
      'print_statement',
      'send_statement',
      'last_transaction',
      'delete_customer',
      'edit_customer',
      'rename_customer',
    ];
    if (needsCustomerOnly.contains(session.intent) && !session.hasCustomer) {
      return _askForField(session, 'customerName');
    }

    // و. تحديد السقف يحتاج اسم ومبلغ
    if (session.intent == 'set_limit') {
      if (!session.hasCustomer) return _askForField(session, 'customerName');
      if (!session.hasAmount) return _askForField(session, 'limitAmount');
    }

    // ز. العمليات المالية تحتاج اسم ومبلغ
    if (['debt', 'payment', 'return'].contains(session.intent)) {
      if (!session.hasCustomer) return _askForField(session, 'customerName');
      if (!session.hasAmount) return _askForField(session, 'amount');
    }

    // ح. إضافة حساب
    if (session.intent == 'add_account' && !session.hasCustomer) {
      return _askForField(session, 'customerName');
    }

    // ═══════════════════════════════════════════════════════════
    // 5. البحث عن العميل (إذا لزم)
    // ═══════════════════════════════════════════════════════════
    Customer? customer;
    if (session.hasCustomer) {
      final found = await _findCustomerWithCandidates(session.customerName!);
      if (!_isCurrentSession(session)) return _cancelledResult();
      if (found.$1 == null) {
        return _handleUnknownCustomer(session, found.$2);
      }
      customer = found.$1!;
      session.matchedCustomer = _customerToMap(customer);
    }

    // ═══════════════════════════════════════════════════════════
    // 6. التنفيذ بناءً على النية
    // ═══════════════════════════════════════════════════════════
    switch (session.intent) {
      case 'statement':
        return _executeStatement(session, customer!);
      case 'block_account':
        return _executeBlock(session, customer!);
      case 'unblock_account':
        return _executeUnblock(session, customer!);
      case 'set_limit':
        return _executeSetLimit(session, customer!);
      case 'remove_limit':
        return _executeRemoveLimit(session, customer!);
      case 'print_statement':
        return _executePrint(session, customer!);
      case 'send_statement':
        return _executeSend(session, customer!);
      case 'last_transaction':
        return _executeLastTransaction(session, customer!);
      case 'delete_customer':
        session.expectingField = 'confirmDelete';
        final msg = VoicePromptsService.getPrompt(
          VoicePromptsService.pConfirmDeleteCustomer,
          vars: {'name': customer!.name},
        );
        return VoiceConversationResult(
          step: ConversationStep.askQuestion,
          prompt: msg,
          ttsMessage: msg,
          startListening: true,
        );
      case 'edit_customer':
        return _executeEdit(session, customer!);
      case 'rename_customer':
        if (session.items == null || session.items!.trim().isEmpty) {
          return _askForField(session, 'renameTo');
        }
        return _executeRename(session, customer!, session.items!.trim());
      case 'debt':
      case 'payment':
      case 'return':
        final askItems = SettingsService.getBool(
          AppSettings.voiceAlwaysAskForItems,
          defaultValue: false,
        );
        if (askItems && session.items == null) {
          return _askForField(session, 'items');
        }
        return _saveTransaction(session, customer!);
      case 'add_account':
        return _addNewCustomer(session);
      default:
        return _fail('نية غير معروفة');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // اختيار مرشح من القائمة
  // ═══════════════════════════════════════════════════════════

  static Future<VoiceConversationResult> selectCandidate(int index, {String source = 'voice_screen'}) async {
    final session = _sessions[source];
    final candidates = _candidatesBySource[source] ?? const <Customer>[];
    if (session == null) return _fail('لا توجد جلسة نشطة');
    if (index < 0 || index >= candidates.length) return _fail('اختيار غير صالح');
    final chosen = candidates[index];
    session.matchedCustomer = _customerToMap(chosen);
    session.customerName = chosen.name;
    _candidatesBySource.remove(source);
    session.expectingField = null;
    session.resetAttemptsFor('customerName');

    // إعادة توجيه التنفيذ حسب النية الحالية
    switch (session.intent) {
      case 'statement': return _executeStatement(session, chosen);
      case 'block_account': return _executeBlock(session, chosen);
      case 'unblock_account': return _executeUnblock(session, chosen);
      case 'set_limit': return _executeSetLimit(session, chosen);
      case 'remove_limit': return _executeRemoveLimit(session, chosen);
      case 'print_statement': return _executePrint(session, chosen);
      case 'send_statement': return _executeSend(session, chosen);
      case 'last_transaction': return _executeLastTransaction(session, chosen);
      case 'delete_customer':
        session.expectingField = 'confirmDelete';
        final msg = VoicePromptsService.getPrompt(
          VoicePromptsService.pConfirmDeleteCustomer,
          vars: {'name': chosen.name},
        );
        return VoiceConversationResult(
          step: ConversationStep.askQuestion,
          prompt: msg,
          ttsMessage: msg,
          startListening: true,
        );
      case 'edit_customer': return _executeEdit(session, chosen);
      case 'rename_customer': return _askForField(session, 'renameTo');
      default:
        final askItems = SettingsService.getBool(
          AppSettings.voiceAlwaysAskForItems,
          defaultValue: false,
        );
        if (askItems && session.items == null) {
          return _askForField(session, 'items');
        }
        return _saveTransaction(session, chosen);
    }
  }

  // ═══════════════════════════════════════════════════════════
  // إضافة حساب جديد
  // ═══════════════════════════════════════════════════════════

  static Future<VoiceConversationResult> addNewCustomer({String source = 'voice_screen'}) async {
    final session = _sessions[source];
    if (session == null) return _fail('لا توجد جلسة نشطة');
    return _addNewCustomer(session);
  }

  static Future<VoiceConversationResult> _addNewCustomer(VoiceSession session) async {
    if (!_isCurrentSession(session)) return _cancelledResult();
    final name = session.customerName;
    if (name == null || name.trim().isEmpty) return _fail('اسم الحساب غير معروف');

    try {
      final db = DatabaseHelper.instance;
      final existing = await db.findAllByExactName(name.trim());
      if (!_isCurrentSession(session)) return _cancelledResult();
      if (existing.isNotEmpty) {
        return _handleUnknownCustomer(session, existing);
      }

      final accountant = await AccountantService.getAccountantName();
      if (!_isCurrentSession(session)) return _cancelledResult();
      final now = DateTime.now().toIso8601String();

      if (!_isCurrentSession(session)) return _cancelledResult();
      final customerId = await db.insertCustomer(Customer(
        name: name.trim(),
        accountType: session.accountType,
        createdBy: accountant,
        updatedBy: accountant,
        updatedAt: now,
        createdAt: now,
      ));

      if (!_isCurrentSession(session)) return _cancelledResult();
      final newCustomer = await db.getCustomer(customerId);
      if (!_isCurrentSession(session)) return _cancelledResult();
      if (newCustomer == null) return _fail('فشل إنشاء الحساب');

      if (!_isCurrentSession(session)) return _cancelledResult();
      await LoggerService.logCustomerAdded(newCustomer.name, accountant: accountant);
      if (!_isCurrentSession(session)) return _cancelledResult();
      session.markCompleted();
      
      return VoiceConversationResult(
        step: ConversationStep.saved,
        matchedCustomer: newCustomer,
        ttsMessage: VoicePromptsService.getResponse(
          VoicePromptsService.tAccountCreated,
          vars: {'name': newCustomer.name},
        ),
      );
    } catch (e) {
      debugPrint('❌ [VoiceConv] addNewCustomer: $e');
      return _fail('خطأ في إنشاء الحساب: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // التنفيذ الفعلي للعمليات (Execution)
  // ═══════════════════════════════════════════════════════════

  static Future<VoiceConversationResult> _executeStatement(VoiceSession session, Customer customer) async {
    if (!_isCurrentSession(session)) return _cancelledResult();
    final db = DatabaseHelper.instance;
    final balance = await db.customerBalance(customer.id!);
    if (!_isCurrentSession(session)) return _cancelledResult();
    final String tts;
    
    if (balance > 0) {
      tts = VoicePromptsService.getResponse(VoicePromptsService.tBalanceDebt, vars: {'customer': customer.name, 'balance': balance.toStringAsFixed(0), 'currency': session.currency});
    } else if (balance < 0) {
      tts = VoicePromptsService.getResponse(VoicePromptsService.tBalanceCredit, vars: {'customer': customer.name, 'balance': (-balance).toStringAsFixed(0), 'currency': session.currency});
    } else {
      tts = VoicePromptsService.getResponse(VoicePromptsService.tBalanceZero, vars: {'customer': customer.name});
    }
    session.markCompleted();
    return VoiceConversationResult(step: ConversationStep.saved, ttsMessage: tts);
  }

  static Future<VoiceConversationResult> _executeBlock(VoiceSession session, Customer customer) async {
    if (!_isCurrentSession(session)) return _cancelledResult();
    final changed = await DatabaseHelper.instance.setCustomerActive(customer.id!, false);
    if (!_isCurrentSession(session)) return _cancelledResult();
    if (changed <= 0) return _fail('تعذر إيقاف الحساب');
    session.markCompleted();
    return VoiceConversationResult(
      step: ConversationStep.saved,
      ttsMessage: VoicePromptsService.getResponse(VoicePromptsService.rAccountBlocked, vars: {'name': customer.name}),
    );
  }

  static Future<VoiceConversationResult> _executeUnblock(VoiceSession session, Customer customer) async {
    if (!_isCurrentSession(session)) return _cancelledResult();
    final changed = await DatabaseHelper.instance.setCustomerActive(customer.id!, true);
    if (!_isCurrentSession(session)) return _cancelledResult();
    if (changed <= 0) return _fail('تعذر تفعيل الحساب');
    session.markCompleted();
    return VoiceConversationResult(
      step: ConversationStep.saved,
      ttsMessage: VoicePromptsService.getResponse(VoicePromptsService.rAccountUnblocked, vars: {'name': customer.name}),
    );
  }

  static Future<VoiceConversationResult> _executeSetLimit(VoiceSession session, Customer customer) async {
    if (!_isCurrentSession(session)) return _cancelledResult();
    final changed = await DatabaseHelper.instance.updateCustomerFields(
      customer.id!,
      {'max_balance': session.amount},
    );
    if (!_isCurrentSession(session)) return _cancelledResult();
    if (changed <= 0) return _fail('تعذر تحديد سقف الحساب');
    session.markCompleted();
    return VoiceConversationResult(
      step: ConversationStep.saved,
      ttsMessage: VoicePromptsService.getResponse(
        VoicePromptsService.rLimitSet,
        vars: {
          'name': customer.name,
          'amount': session.amount!.toStringAsFixed(0),
          'currency': session.currency,
        },
      ),
    );
  }

  static Future<VoiceConversationResult> _executeRemoveLimit(VoiceSession session, Customer customer) async {
    if (!_isCurrentSession(session)) return _cancelledResult();
    final changed = await DatabaseHelper.instance.updateCustomerFields(
      customer.id!,
      {'max_balance': null},
    );
    if (!_isCurrentSession(session)) return _cancelledResult();
    if (changed <= 0) return _fail('تعذر إلغاء سقف الحساب');
    session.markCompleted();
    return VoiceConversationResult(
      step: ConversationStep.saved,
      ttsMessage: 'تم إلغاء سقف الحساب ${customer.name}',
    );
  }

  static Future<VoiceConversationResult> _executePrint(VoiceSession session, Customer customer) async {
    if (!_isCurrentSession(session)) return _cancelledResult();
    session.markCompleted();
    return VoiceConversationResult(
      step: ConversationStep.saved,
      ttsMessage: VoicePromptsService.getResponse(VoicePromptsService.rPrintingStatement, vars: {'name': customer.name}),
      targetScreen: 'print',
      matchedCustomer: customer,
      fromDate: session.fromDate,
      toDate: session.toDate,
    );
  }

  static Future<VoiceConversationResult> _executeSend(VoiceSession session, Customer customer) async {
    if (!_isCurrentSession(session)) return _cancelledResult();
    session.markCompleted();
    return VoiceConversationResult(
      step: ConversationStep.saved,
      ttsMessage: VoicePromptsService.getResponse(VoicePromptsService.rSendingStatement, vars: {'name': customer.name}),
      targetScreen: 'send',
      matchedCustomer: customer,
      fromDate: session.fromDate,
      toDate: session.toDate,
    );
  }

  static Future<VoiceConversationResult> _executeLastTransaction(VoiceSession session, Customer customer) async {
    if (!_isCurrentSession(session)) return _cancelledResult();
    final db = DatabaseHelper.instance;
    final txList = await db.customerTransactions(customer.id!);
    if (!_isCurrentSession(session)) return _cancelledResult();
    if (txList.isEmpty) {
      session.markCompleted();
      return VoiceConversationResult(step: ConversationStep.saved, ttsMessage: 'لا توجد عمليات لهذا الحساب');
    }
    final last = txList.first;
    final summary = '${last.type == 'debt' ? 'دين' : last.type == 'payment' ? 'سداد' : 'مرتجع'} ${last.amount.toStringAsFixed(0)} ${last.currency}';
    session.markCompleted();
    return VoiceConversationResult(
      step: ConversationStep.saved,
      ttsMessage: VoicePromptsService.getResponse(VoicePromptsService.rLastTransaction, vars: {'summary': summary}),
    );
  }

  static Future<VoiceConversationResult> _executeDelete(VoiceSession session) async {
    if (!_isCurrentSession(session)) return _cancelledResult();
    if (session.matchedCustomer == null) return _fail('لم يتم تحديد الحساب');
    final customer = Customer.fromMap(session.matchedCustomer!);
    final changed = await DatabaseHelper.instance.softDeleteCustomer(customer.id!);
    if (!_isCurrentSession(session)) return _cancelledResult();
    if (changed <= 0) return _fail('تعذر حذف الحساب');
    session.markCompleted();
    return VoiceConversationResult(
      step: ConversationStep.saved,
      ttsMessage: VoicePromptsService.getResponse(VoicePromptsService.rCustomerDeleted, vars: {'name': customer.name}),
    );
  }

  static Future<VoiceConversationResult> _executeRename(
    VoiceSession session,
    Customer customer,
    String newName,
  ) async {
    final normalizedName = newName.trim();
    if (normalizedName.isEmpty) {
      return _askForField(session, 'renameTo');
    }

    final matches = await DatabaseHelper.instance.findAllByExactName(normalizedName);
    if (!_isCurrentSession(session)) return _cancelledResult();
    if (matches.any((item) => item.id != customer.id)) {
      return _fail('يوجد حساب آخر بهذا الاسم بالفعل');
    }

    if (!_isCurrentSession(session)) return _cancelledResult();
    final changed = await DatabaseHelper.instance.updateCustomerFields(
      customer.id!,
      {'name': normalizedName},
    );
    if (!_isCurrentSession(session)) return _cancelledResult();
    if (changed <= 0) return _fail('تعذر تغيير اسم الحساب');

    session.markCompleted();
    return VoiceConversationResult(
      step: ConversationStep.saved,
      ttsMessage: 'تم تغيير اسم الحساب من ${customer.name} إلى $normalizedName',
    );
  }

  static Future<VoiceConversationResult> _executeEdit(VoiceSession session, Customer customer) async {
    session.markCompleted();
    return VoiceConversationResult(
      step: ConversationStep.saved,
      ttsMessage: VoicePromptsService.getResponse(VoicePromptsService.rEditSaved, vars: {'name': customer.name}),
      targetScreen: 'edit',
      matchedCustomer: customer,
    );
  }

  static Future<VoiceConversationResult> _executeStatistics(VoiceSession session) async {
    session.markCompleted();
    return VoiceConversationResult(
      step: ConversationStep.saved,
      ttsMessage: VoicePromptsService.getResponse(VoicePromptsService.rShowingStats),
      targetScreen: 'stats',
    );
  }

  static Future<VoiceConversationResult> _executeSearch(VoiceSession session, String query) async {
    session.markCompleted();
    return VoiceConversationResult(
      step: ConversationStep.saved,
      ttsMessage: VoicePromptsService.getResponse(VoicePromptsService.rSearchResults, vars: {'count': '...'}),
      targetScreen: 'search',
    );
  }

  // ═══════════════════════════════════════════════════════════
  // الحفظ
  // ═══════════════════════════════════════════════════════════

  static Future<VoiceConversationResult> _saveTransaction(
    VoiceSession session,
    Customer customer,
  ) async {
    try {
      // Refuse to enter the persistence path if this is no longer the active
      // conversation. This also prevents stale async callbacks from saving.
      if (!_isCurrentSession(session)) {
        return VoiceConversationResult(
          step: ConversationStep.failed,
          ttsMessage: 'تم إلغاء العملية',
          errorMessage: 'تم إلغاء العملية',
        );
      }

      final db = DatabaseHelper.instance;

      final fakeParsed = _FakeParsed(
        intent: session.intent!,
        amount: session.amount!,
        currency: session.currency,
        items: session.items ?? '',
      );

      // Capture the exact session object. If the user cancels while any
      // asynchronous validation is running, the session is removed from its source and the
      // transaction handler will refuse the final database insert.
      final ok = await TransactionHandler.save(
        customer: customer,
        parsed: fakeParsed,
        db: db,
        source: session.source,
        audioPath: null,
        canCommit: () =>
            _isCurrentSession(session),
      );

      if (!ok) {
        if (!identical(_sessions[session.source], session)) {
          return VoiceConversationResult(
            step: ConversationStep.failed,
            ttsMessage: 'تم إلغاء العملية',
            errorMessage: 'تم إلغاء العملية',
          );
        }
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

  static Future<(Customer?, List<Customer>)> _findCustomerWithCandidates(
    String name,
  ) async {
    final db = DatabaseHelper.instance;

    // 1. البحث الدقيق (يجد كل المطابقات)
    final exactList = await db.findAllByExactName(name);
    if (exactList.length == 1) {
      return (exactList.first, <Customer>[]);
    }
    if (exactList.length > 1) {
      return (null, exactList);
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
    _candidatesBySource[session.source] = candidates;

    final name = session.customerName ?? '';

    final prompt = VoicePromptsService.getPrompt(
      VoicePromptsService.pAskCustomerAmbiguous,
      vars: {'name': name},
    );

    if (candidates.isEmpty && session.intent == 'add_account') {
      final prompt = 'لا يوجد حساب باسم $name، هل تريد إضافة حساب جديد باسم $name؟';
      session.expectingField = 'confirmAddAccount';
      session.lastPrompt = prompt;
      return VoiceConversationResult(
        step: ConversationStep.askQuestion,
        prompt: prompt,
        ttsMessage: prompt,
        startListening: true,
      );
    }

    // أوامر إدارة الحساب لا تنشئ إشعارات "عملية معلقة" عند غياب الحساب.
    // نوضح للمستخدم أن الحساب غير موجود وننهي الطلب دون تغيير أي بيانات.
    const accountManagementIntents = {
      'block_account',
      'unblock_account',
      'set_limit',
      'remove_limit',
      'delete_customer',
      'edit_customer',
      'rename_customer',
      'statement',
      'print_statement',
      'send_statement',
      'last_transaction',
    };
    if (candidates.isEmpty && accountManagementIntents.contains(session.intent)) {
      final message = 'لا يوجد حساب باسم $name';
      cancelSession(source: session.source);
      return VoiceConversationResult(
        step: ConversationStep.failed,
        ttsMessage: message,
        errorMessage: message,
      );
    }

    final ttsMessage = candidates.isEmpty
        ? VoicePromptsService.getResponse(VoicePromptsService.rNoAccount, vars: {'name': name})
        : VoicePromptsService.getResponse(VoicePromptsService.tMultipleAccounts);

    return VoiceConversationResult(
      step: ConversationStep.showCandidates,
      prompt: prompt,
      ttsMessage: ttsMessage,
      candidates: candidates,
      startListening: candidates.isNotEmpty,
    );
  }

  /// يحدد هل فهم المحلل الإجابة الخاصة بالحقل المطلوب.
  static bool _hasAnswerForField(VoiceSession session, String field) {
    switch (field) {
      case 'intent':
      case 'intentForCustomer':
      case 'processType':
        return session.hasIntent;
      case 'customerName':
        return session.hasCustomer;
      case 'amount':
      case 'limitAmount':
        return session.hasAmount;
      case 'items':
        // النص الفارغ مقبول عند قول المستخدم "بدون بيان".
        return session.items != null;
      case 'renameTo':
        return session.items != null && session.items!.trim().isNotEmpty;
      case 'searchQuery':
        return true;
      default:
        return true;
    }
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
        prompt = VoicePromptsService.getPrompt(VoicePromptsService.pAskIntent);
        break;

      case 'intentForCustomer':
        prompt = VoicePromptsService.getPrompt(VoicePromptsService.pAskIntentForCustomer);
        break;

      case 'processType':
        prompt = VoicePromptsService.getPrompt(VoicePromptsService.pAskProcessType);
        break;

      case 'customerName':
        if (session.intent == 'statement' || session.intent == 'print_statement' || session.intent == 'send_statement') {
           prompt = 'أي حساب تريد؟'; // يمكن تعديلها من VoicePromptsService لاحقاً
        } else if (session.intent == 'block_account' || session.intent == 'unblock_account' || session.intent == 'delete_customer' || session.intent == 'edit_customer' || session.intent == 'rename_customer') {
           prompt = 'أي حساب تريد؟';
        } else if (session.intent == 'payment') {
          prompt = VoicePromptsService.getPrompt(VoicePromptsService.pAskCustomerPayment);
        } else if (session.intent == 'return') {
          prompt = VoicePromptsService.getPrompt(VoicePromptsService.pAskCustomerReturn);
        } else if (session.intent == 'debt') {
          prompt = VoicePromptsService.getPrompt(VoicePromptsService.pAskCustomerDebt);
        } else {
          prompt = VoicePromptsService.getPrompt(VoicePromptsService.pAskCustomerUnknown);
        }
        break;

      case 'amount':
        prompt = VoicePromptsService.getPrompt(VoicePromptsService.pAskAmount);
        break;

      case 'limitAmount':
        prompt = VoicePromptsService.getPrompt(VoicePromptsService.pAskLimitAmount);
        break;

      case 'items':
        prompt = VoicePromptsService.getPrompt(VoicePromptsService.pAskItems);
        break;

      case 'renameTo':
        prompt = 'ما الاسم الجديد للحساب؟';
        break;

      case 'searchQuery':
        prompt = VoicePromptsService.getPrompt(VoicePromptsService.pAskSearchQuery);
        break;

      case 'confirmAddAccount':
        prompt = 'هل تريد إضافة الحساب؟ قل نعم أو لا';
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

  static VoiceConversationResult _cancelledResult() => VoiceConversationResult(
        step: ConversationStep.failed,
        ttsMessage: 'تم إلغاء العملية',
        errorMessage: 'تم إلغاء العملية',
      );

  static VoiceConversationResult _fail(String error) {
    return VoiceConversationResult(
      step: ConversationStep.failed,
      errorMessage: error,
    );
  }

  static Future<VoiceConversationResult> _failAfterMaxAttempts(VoiceSession session) async {
    final maxRounds = SettingsService.getInt(
      AppSettings.voiceMaxConversationRounds,
      defaultValue: 3,
    );

    // لا نحفظ العمليات غير المكتملة ولا ننشئ سجلاً معلقاً عند فشل التعرف.
    cancelSession(source: session.source);

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
