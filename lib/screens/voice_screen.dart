import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import '../models/account_type.dart';
import '../models/customer.dart';
import '../models/voice_session.dart';
import '../services/accountant_service.dart';
import '../services/audio_recorder_service.dart';
import '../services/logger_service.dart';
import '../services/parser_service.dart';
import '../services/query_service.dart';
import '../services/speech_service.dart';
import '../services/tts_service.dart';
import '../services/voice_conversation_service.dart';
import '../services/pdf_service.dart';
import '../config/app_settings.dart';
import '../services/settings_service.dart';
import 'stats_screen.dart';
import 'add_account_screen.dart';

class VoiceScreen extends StatefulWidget {
  final String? initialText;

  const VoiceScreen({super.key, this.initialText});
  @override
  State<VoiceScreen> createState() => _VoiceScreenState();
}

class _VoiceScreenState extends State<VoiceScreen> {
  final _speech = SpeechService();
  final _audioService = AudioRecorderService();

  // ─── حالة التسجيل ───
  String _text = '';
  bool _listening = false;
  bool _recording = false;
  bool _isProcessing = false;
  String? _currentAudioPath;

  // ─── حالة الاستعلام ───
  QueryResult? _queryResult;

  // ─── حالة إضافة حساب ───
  ParsedPartial? _addAccountParsed;

  // ─── حالة الحوار ───
  VoiceConversationResult? _lastResult;
  List<Customer> _candidates = [];
  bool _sessionCompleted = false;
  int _listenGeneration = 0;

  // ─── خطأ ───
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _speech.init();
    TtsService.init();

    if (widget.initialText != null && widget.initialText!.isNotEmpty) {
      _text = widget.initialText!;
      WidgetsBinding.instance.addPostFrameCallback((_) => _process(widget.initialText!));
    }
  }

  @override
  void dispose() {
    _listenGeneration++;
    _audioService.stopPlayback();
    // This screen may have been replaced while the overlay took ownership
    // of the shared conversation. Never cancel another source's session.
    if (VoiceConversationService.sessionFor('voice_screen')?.source == 'voice_screen') {
      // Release the native recognizer only when this screen still owns it.
      _speech.cancel();
      VoiceConversationService.cancelSession(source: 'voice_screen');
    }
    super.dispose();
  }

  bool _isVoiceEnabled() {
    return SettingsService.getBool(
      AppSettings.voiceEnabled,
      defaultValue: true,
    );
  }

  // ═══════════════════════════════════════════════════════════
  // زر التحدث (STT)
  // ═══════════════════════════════════════════════════════════
  Future<void> _toggleSpeech() async {
    if (!_isVoiceEnabled()) {
      _showDisabledMessage();
      return;
    }

    if (_recording) {
      await _audioService.stopRecording();
      setState(() => _recording = false);
    }

    if (_listening) {
      // إيقاف المستخدم صريح: لا نرسل صمتاً للحوار ولا نسمح لنتيجة متأخرة
      // من جلسة الشاشة بأن تغيّر حالة الواجهة أو تنفّذ أمراً.
      _listenGeneration++;
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }

    final generation = ++_listenGeneration;
    setState(() {
      _text = '';
      _errorMessage = null;
      _queryResult = null;
      _addAccountParsed = null;
      _listening = true;
    });

    final started = await _speech.listen(
      pauseFor: const Duration(seconds: 3),
      onSilence: () {
        if (!mounted || generation != _listenGeneration) return;
        setState(() => _listening = false);
        if (VoiceConversationService.hasActiveSessionFor('voice_screen')) {
          _processConversation('');
        }
      },
      onResult: (text, isFinal) {
        if (!mounted || generation != _listenGeneration) return;
        setState(() => _text = text);
        if (isFinal) {
          setState(() => _listening = false);

          // الصمت هنا صادر عن نهاية استماع حقيقية فقط؛ الإيقاف اليدوي
          // يلغي generation ويمنع الوصول إلى هذا المسار.
          if (text.trim().isEmpty) {
            if (VoiceConversationService.hasActiveSessionFor('voice_screen')) {
              _processConversation('');
            }
            return;
          }
          _process(text);
        }
      },
    );
    if (!started && mounted && generation == _listenGeneration) {
      setState(() {
        _listening = false;
        _errorMessage = 'تعذر بدء الاستماع. تحقق من إذن الميكروفون وخدمة التعرف على الكلام.';
      });
    }
  }

  // ═══════════════════════════════════════════════════════════
  // زر التسجيل (ملف صوتي)
  // ═══════════════════════════════════════════════════════════
  Future<void> _toggleRecording() async {
    if (!_isVoiceEnabled()) {
      _showDisabledMessage();
      return;
    }

    if (_listening) {
      // Invalidate the pending listen() completion as well as its callbacks.
      _listenGeneration++;
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
    }

    if (_recording) {
      final path = await _audioService.stopRecording();
      if (!mounted) return;
      setState(() {
        _recording = false;
        _currentAudioPath = path;
      });

      if (path != null) {
        await LoggerService.logVoicePending(
          rawText: '(تسجيل صوتي محفوظ - بانتظار المراجعة)',
          audioPath: path,
        );

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                      '✅ تم حفظ التسجيل — راجعه من السجل → المعلقات'),
                ),
              ],
            ),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
          ),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ فشل حفظ التسجيل'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    setState(() {
      _errorMessage = null;
      _recording = true;
      _currentAudioPath = null;
    });

    final ok = await _audioService.startRecording();
    if (!ok) {
      if (!mounted) return;
      setState(() => _recording = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ فشل بدء التسجيل — تأكد من إذن الميكروفون'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showDisabledMessage() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('الإدخال الصوتي معطّل من الإعدادات'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // معالجة النص
  // ═══════════════════════════════════════════════════════════
  Future<void> _process(String text) async {
    if (text.trim().isEmpty) return;

    // أمر الإلغاء له أولوية مطلقة: لا نمرره إلى الاستعلام أو إضافة الحساب.
    if (VoiceConversationService.isCancelCommand(text)) {
      await _processConversation(text);
      return;
    }

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
      _queryResult = null;
      _addAccountParsed = null;
    });

    try {
      // 1. استعلام مباشر — فقط إذا كان النص 3 كلمات أو أكثر (يحتوي على اسم عميل محتمل)
      final wordCount = text.trim().split(RegExp(r'\s+')).length;
      if (wordCount >= 3 && QueryService.isQuery(text)) {
        try {
          final result = await QueryService.query(text);
          if (!mounted) return;
          if (result.spokenAnswer.trim().isNotEmpty) {
            setState(() {
              _queryResult = result;
              _isProcessing = false;
            });
            await TtsService.speak(result.spokenAnswer);
            return;
          }
        } catch (e) {
          debugPrint('⚠️ QueryService failed, falling through: $e');
        }
      }

      // 2. مرّر أمر إضافة الحساب إلى الحوار التفاعلي أيضاً؛
      // حتى يسأل التطبيق عن الاسم إذا لم يذكره المستخدم في الأمر.
      // كما يبقى الإلغاء وأوامر المتابعة ضمن جلسة واحدة متسقة.
      await _processConversation(text);
    } catch (e) {
      debugPrint('❌ _process error: $e');
      if (!mounted) return;
      setState(() {
        _errorMessage = 'حدث خطأ: $e';
        _isProcessing = false;
      });
    }
  }

  // ═══════════════════════════════════════════════════════════
  // الحوار التفاعلي
  // ═══════════════════════════════════════════════════════════
  Future<void> _processConversation(String text) async {
    final activeSession = VoiceConversationService.sessionFor('voice_screen');
    if (activeSession == null || activeSession.source != 'voice_screen') {
      // Do not mix an overlay/notification conversation with this screen.
      VoiceConversationService.cancelSession(source: 'voice_screen');
      VoiceConversationService.startSession(source: 'voice_screen');
    }

    final ownedSession = VoiceConversationService.sessionFor('voice_screen');
    final result = await VoiceConversationService.processText(text, source: 'voice_screen');
    if (!mounted ||
        ownedSession == null ||
        !identical(VoiceConversationService.sessionFor('voice_screen'), ownedSession)) {
      return;
    }

    setState(() {
      _lastResult = result;
      _candidates = result.candidates ?? [];
      _isProcessing = false;
      _sessionCompleted = result.step == ConversationStep.saved;
    });

    // TTS
    if (result.ttsMessage != null && result.ttsMessage!.isNotEmpty) {
      try {
        await TtsService.speak(result.ttsMessage!);
      } catch (_) {}
    }

    // If another source cancelled/replaced this conversation while TTS was
    // speaking, do not reopen the microphone for the obsolete screen session.
    if (!mounted ||
        !identical(VoiceConversationService.sessionFor('voice_screen'), ownedSession)) {
      return;
    }

    // بدء التسجيل تلقائيًا للسؤال التالي
    if (result.startListening) {
      final listenGenerationBeforeDelay = _listenGeneration;
      await Future.delayed(const Duration(milliseconds: 300));
      if (mounted &&
          !_listening &&
          _listenGeneration == listenGenerationBeforeDelay &&
          identical(VoiceConversationService.sessionFor('voice_screen'), ownedSession)) {
        _toggleSpeech();
      }
    }

    // نجاح
    if (result.step == ConversationStep.saved) {
      _onSaved(result);
    }

    // فشل
    if (result.step == ConversationStep.failed) {
      _onFailed(result);
    }
  }

  void _onSaved(VoiceConversationResult result) {
    if (!mounted) return;

    if (result.ttsMessage != null && result.ttsMessage!.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.ttsMessage!),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 4),
        ),
      );
    }

    // 🆕 إذا كان هناك شاشة مطلوب فتحها، افتحها
    if (result.targetScreen != null) {
      Future.delayed(const Duration(milliseconds: 800), () {
        if (!mounted) return;
        _handleTargetScreen(result);
      });
      return;
    }

    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      _resetSession();
    });
  }

  void _onFailed(VoiceConversationResult result) {
    if (!mounted) return;
    setState(() {
      _errorMessage = result.errorMessage ?? 'فشل التعرف';
    });
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) _resetSession();
    });
  }

  void _resetSession() {
    _listenGeneration++;
    if (VoiceConversationService.sessionFor('voice_screen')?.source == 'voice_screen') {
      VoiceConversationService.cancelSession(source: 'voice_screen');
    }
    if (!mounted) return;
    setState(() {
      _lastResult = null;
      _candidates = [];
      _sessionCompleted = false;
      _text = '';
    });
  }

  // ═══════════════════════════════════════════════════════════
  // 🆕 فتح الشاشة المطلوبة بعد تنفيذ الأمر الصوتي
  // ═══════════════════════════════════════════════════════════
  Future<void> _handleTargetScreen(VoiceConversationResult result) async {
    if (!mounted) return;

    switch (result.targetScreen) {
      case 'stats':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const StatsScreen()),
        ).then((_) {
          if (mounted) _resetSession();
        });
        break;

      case 'edit':
        if (result.matchedCustomer != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AddAccountScreen(existing: result.matchedCustomer),
            ),
          ).then((_) {
            if (mounted) _resetSession();
          });
        } else {
          if (mounted) _resetSession();
        }
        break;

      case 'print':
      case 'send':
        if (result.matchedCustomer != null) {
          await _showStatementDialog(result.matchedCustomer!);
          if (mounted) _resetSession();
        } else {
          if (mounted) _resetSession();
        }
        break;

      case 'search':
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('استخدم تبويب العملاء للبحث'),
              backgroundColor: Colors.blue,
            ),
          );
          _resetSession();
        }
        break;

      default:
        if (mounted) _resetSession();
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 🆕 عرض كشف الحساب في نافذة (للطباعة والإرسال)
  // ═══════════════════════════════════════════════════════════
  Future<void> _showStatementDialog(Customer customer) async {
    final db = DatabaseHelper.instance;
    final balance = await db.customerBalance(customer.id!);
    final txList = await db.customerTransactions(customer.id!);

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text('كشف حساب ${customer.name}'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: balance > 0
                          ? Colors.red.withOpacity(0.1)
                          : Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          balance > 0 ? Icons.arrow_upward : Icons.arrow_downward,
                          color: balance > 0 ? Colors.red : Colors.green,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'الرصيد: ${balance.abs().toStringAsFixed(0)} ريال',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: balance > 0 ? Colors.red : Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'آخر العمليات:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const Divider(),
                  if (txList.isEmpty)
                    const Text('لا توجد عمليات', style: TextStyle(color: Colors.grey))
                  else
                    ...txList.take(10).map((t) {
                      final typeLabel = t.type == 'debt'
                          ? 'دين'
                          : t.type == 'payment'
                              ? 'سداد'
                              : 'مرتجع';
                      final color = t.type == 'debt' ? Colors.red : Colors.green;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Icon(Icons.circle, size: 8, color: color),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '$typeLabel — ${t.amount.toStringAsFixed(0)} ${t.currency}',
                                style: TextStyle(fontSize: 13, color: color),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إغلاق'),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('طباعة / حفظ PDF'),
              onPressed: () async {
                DateTime? fromDate;
                DateTime? toDate;

                // اختيار بداية الفترة ونهايتها قبل إنشاء كشف الحساب.
                fromDate = await showDatePicker(
                  context: ctx,
                  initialDate: DateTime.now(),
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                  helpText: 'اختر تاريخ البداية',
                );
                if (fromDate == null || !ctx.mounted) return;

                toDate = await showDatePicker(
                  context: ctx,
                  initialDate: DateTime.now().isBefore(fromDate)
                      ? fromDate
                      : DateTime.now(),
                  firstDate: fromDate,
                  lastDate: DateTime(2100),
                  helpText: 'اختر تاريخ النهاية',
                );
                if (toDate == null || !ctx.mounted) return;

                Navigator.pop(ctx);
                try {
                  final file = await PdfService.generateStatement(
                    customer,
                    fromDate: fromDate,
                    toDate: toDate,
                  );
                  await PdfService.share(file, customer.name);
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('تعذر إنشاء كشف PDF: $e')),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // اختيار مرشح
  // ═══════════════════════════════════════════════════════════
  Future<void> _selectCandidate(int index) async {
    setState(() => _isProcessing = true);

    final result = await VoiceConversationService.selectCandidate(index, source: 'voice_screen');
    if (!mounted) return;

    setState(() {
      _lastResult = result;
      _candidates = result.candidates ?? [];
      _isProcessing = false;
      _sessionCompleted = result.step == ConversationStep.saved;
    });

    if (result.ttsMessage != null && result.ttsMessage!.isNotEmpty) {
      try {
        await TtsService.speak(result.ttsMessage!);
      } catch (_) {}
    }

    if (result.startListening && mounted) {
      await Future.delayed(const Duration(milliseconds: 300));
      if (mounted) _toggleSpeech();
    }

    if (result.step == ConversationStep.saved) _onSaved(result);
    if (result.step == ConversationStep.failed) _onFailed(result);
  }

  Future<void> _addNewCustomer() async {
    setState(() => _isProcessing = true);

    final result = await VoiceConversationService.addNewCustomer(source: 'voice_screen');
    if (!mounted) return;

    setState(() {
      _lastResult = result;
      _candidates = result.candidates ?? [];
      _isProcessing = false;
      _sessionCompleted = result.step == ConversationStep.saved;
    });

    if (result.ttsMessage != null && result.ttsMessage!.isNotEmpty) {
      try {
        await TtsService.speak(result.ttsMessage!);
      } catch (_) {}
    }

    if (result.startListening && mounted) {
      await Future.delayed(const Duration(milliseconds: 300));
      if (mounted) _toggleSpeech();
    }

    if (result.step == ConversationStep.saved) _onSaved(result);
    if (result.step == ConversationStep.failed) _onFailed(result);
  }

  // ═══════════════════════════════════════════════════════════
  // إضافة حساب (Legacy — عبر زر منفصل)
  // ═══════════════════════════════════════════════════════════
  Future<void> _saveAccount() async {
    final parsed = _addAccountParsed;
    if (parsed == null) return;
    if (parsed.customerName == null || parsed.customerName!.isEmpty) return;

    final db = DatabaseHelper.instance;
    final accountant = await AccountantService.getAccountantName();
    final customerName = parsed.customerName!;

    final existing = await db.findExactCustomer(customerName);
    if (existing != null) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'الحساب موجود مسبقاً';
        _addAccountParsed = null;
      });
      TtsService.speakExistsBefore(customerName);
      return;
    }

    final now = DateTime.now().toIso8601String();
    await db.insertCustomer(Customer(
      name: customerName,
      accountType: parsed.accountType,
      createdBy: accountant,
      updatedBy: accountant,
      updatedAt: now,
      createdAt: now,
    ));

    await LoggerService.logCustomerAdded(customerName, accountant: accountant);

    if (!mounted) return;
    TtsService.speakAccountCreated(customerName);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✅ تم إنشاء حساب: $customerName'),
        backgroundColor: Colors.green,
      ),
    );
    setState(() {
      _addAccountParsed = null;
      _text = '';
    });
  }

  // ═══════════════════════════════════════════════════════════
  // البناء
  // ═══════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final voiceEnabled = _isVoiceEnabled();
    final session = VoiceConversationService.sessionFor('voice_screen');

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('تسجيل بالصوت'),
          actions: [
            if (session != null && !_sessionCompleted)
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'إلغاء الجلسة',
                onPressed: () {
                  VoiceConversationService.cancelSession(source: 'voice_screen');
                  _resetSession();
                },
              ),
          ],
        ),
        body: Column(
          children: [
            if (_isProcessing) const LinearProgressIndicator(minHeight: 3),
            if (!voiceEnabled)
              _warningBanner('الإدخال الصوتي معطّل من الإعدادات'),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // ═══════════════════════════════════════════════
                    // النص المكتشف
                    // ═══════════════════════════════════════════════
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color:
                                theme.colorScheme.outline.withOpacity(0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('النص المكتشف:',
                              style: TextStyle(
                                  fontSize: 12,
                                  color:
                                      theme.colorScheme.onSurfaceVariant)),
                          const SizedBox(height: 8),
                          Text(
                            _text.isEmpty
                                ? (_listening
                                    ? '🎙️ أستمع...'
                                    : _recording
                                        ? '🔴 جاري التسجيل...'
                                        : 'اختر: تحدث (STT) أو سجّل (ملف)')
                                : _text,
                            style: TextStyle(
                                fontSize: 16,
                                color: theme.colorScheme.onSurface,
                                fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // ═══════════════════════════════════════════════
                    // الأزرار (تحدث / سجل)
                    // ═══════════════════════════════════════════════
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _bigCircleButton(
                          icon: _listening ? Icons.stop : Icons.mic,
                          label: _listening ? 'إيقاف' : 'تحدث',
                          subtitle: '(يتعرف على النص)',
                          color: !voiceEnabled
                              ? Colors.grey
                              : (_listening
                                  ? Colors.red
                                  : theme.colorScheme.primary),
                          onTap: (_isProcessing || !voiceEnabled)
                              ? null
                              : _toggleSpeech,
                          theme: theme,
                        ),
                        _bigCircleButton(
                          icon: _recording
                              ? Icons.stop_circle
                              : Icons.fiber_manual_record,
                          label: _recording ? 'إيقاف التسجيل' : 'سجّل',
                          subtitle: '(يحفظ ملف صوتي)',
                          color: !voiceEnabled
                              ? Colors.grey
                              : (_recording
                                  ? Colors.red
                                  : Colors.deepOrange),
                          onTap: (_isProcessing || !voiceEnabled)
                              ? null
                              : _toggleRecording,
                          theme: theme,
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // ═══════════════════════════════════════════════
                    // رسالة الحالة
                    // ═══════════════════════════════════════════════
                    Text(
                      !voiceEnabled
                          ? 'الإدخال الصوتي معطّل'
                          : _isProcessing
                              ? '⏳ جاري المعالجة...'
                              : _listening
                                  ? '🎙️ أستمع... تحدث بوضوح'
                                  : _recording
                                      ? '🔴 جاري التسجيل... اضغط ⏹️ للحفظ'
                                      : _sessionCompleted
                                          ? '✅ اكتملت الجلسة'
                                          : session != null
                                              ? '💬 جلسة نشطة'
                                              : 'اضغط "تحدث" للتعرف، أو "سجّل" لحفظ الصوت',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),

                    // ═══════════════════════════════════════════════
                    // معاينة الصوت
                    // ═══════════════════════════════════════════════
                    if (_currentAudioPath != null && !_recording)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: Colors.orange.withOpacity(0.4)),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.pending_actions,
                                  color: Colors.orange, size: 20),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'تم حفظ التسجيل — راجعه من السجل → المعلقات',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    // ═══════════════════════════════════════════════
                    // عرض تقدم الجلسة
                    // ═══════════════════════════════════════════════
                    if (session != null && !_sessionCompleted)
                      _buildSessionProgress(session, theme),

                    // ═══════════════════════════════════════════════
                    // عرض الحوار (سؤال / مرشحون)
                    // ═══════════════════════════════════════════════
                    if (_lastResult != null)
                      _buildConversationView(_lastResult!, theme),

                    // ═══════════════════════════════════════════════
                    // استعلام
                    // ═══════════════════════════════════════════════
                    if (_queryResult != null)
                      _buildQueryView(_queryResult!, theme),

                    // ═══════════════════════════════════════════════
                    // إضافة حساب (Legacy)
                    // ═══════════════════════════════════════════════
                    if (_addAccountParsed != null)
                      _buildAddAccountView(_addAccountParsed!, theme),

                    // ═══════════════════════════════════════════════
                    // خطأ
                    // ═══════════════════════════════════════════════
                    if (_errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 20),
                        child: Card(
                          color: theme.colorScheme.errorContainer,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Icon(Icons.error_outline,
                                    color: theme.colorScheme.error),
                                const SizedBox(width: 12),
                                Expanded(
                                    child: Text(_errorMessage!,
                                        style: TextStyle(
                                            color: theme.colorScheme
                                                .onErrorContainer))),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // بناء أزرار الدوائر الكبيرة
  // ═══════════════════════════════════════════════════════════
  Widget _bigCircleButton({
    required IconData icon,
    required String label,
    required String subtitle,
    required Color color,
    required VoidCallback? onTap,
    required ThemeData theme,
  }) {
    final enabled = onTap != null;
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(enabled ? 0.4 : 0.0),
                  blurRadius: 15,
                  spreadRadius: 3,
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 45),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: enabled ? theme.colorScheme.onSurface : Colors.grey,
          ),
        ),
        Text(
          subtitle,
          style: const TextStyle(fontSize: 10, color: Colors.grey),
        ),
      ],
    );
  }

  Widget _warningBanner(String msg) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: Colors.orange.withOpacity(0.15),
      child: Row(
        children: [
          const Icon(Icons.warning_amber, color: Colors.orange),
          const SizedBox(width: 8),
          Expanded(child: Text(msg, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // بناء تقدم الجلسة
  // ═══════════════════════════════════════════════════════════
  Widget _buildSessionProgress(VoiceSession session, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Card(
        color: theme.colorScheme.primaryContainer.withOpacity(0.3),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.timeline,
                      size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 6),
                  Text(
                    'البيانات المجمّعة',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${session.totalAttempts} محاولة',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _fieldChip(
                    'النوع',
                    session.hasIntent ? _intentLabel(session.intent!) : null,
                    Colors.blue,
                  ),
                  _fieldChip(
                    'الاسم',
                    session.customerName,
                    Colors.teal,
                  ),
                  _fieldChip(
                    'المبلغ',
                    session.hasAmount
                        ? '${session.amount!.toStringAsFixed(0)} ${session.currency}'
                        : null,
                    Colors.green,
                  ),
                  _fieldChip(
                    'البيان',
                    session.items,
                    Colors.orange,
                    optional: true,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fieldChip(String label, String? value, Color color,
      {bool optional = false}) {
    final filled = value != null && value.isNotEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: filled
            ? color.withOpacity(0.15)
            : Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: filled ? color : Colors.grey.withOpacity(0.3),
          width: 0.7,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            filled ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 12,
            color: filled ? color : Colors.grey,
          ),
          const SizedBox(width: 4),
          Text(
            '$label: ${filled ? value : (optional ? "—" : "مفقود")}',
            style: TextStyle(
              fontSize: 11,
              color: filled ? color : Colors.grey,
              fontWeight: filled ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  String _intentLabel(String intent) {
    return {
      'debt': 'دين',
      'payment': 'سداد',
      'return': 'مرتجع',
      'add_account': 'إنشاء حساب',
      'statement': 'كشف حساب',
      'block_account': 'إيقاف حساب',
      'unblock_account': 'تفعيل حساب',
      'set_limit': 'تحديد سقف',
      'process': 'عملية',
      'print_statement': 'طباعة',
      'send_statement': 'إرسال',
      'statistics': 'إحصائيات',
      'last_transaction': 'آخر عملية',
      'search': 'بحث',
      'delete_customer': 'حذف حساب',
      'edit_customer': 'تعديل حساب',
    }[intent] ?? intent;
  }

  // ═══════════════════════════════════════════════════════════
  // عرض الحوار
  // ═══════════════════════════════════════════════════════════
  Widget _buildConversationView(
      VoiceConversationResult result, ThemeData theme) {
    // ─── سؤال ───
    if (result.step == ConversationStep.askQuestion) {
      return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Card(
          color: theme.colorScheme.tertiaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.question_answer,
                    color: theme.colorScheme.tertiary, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'السؤال:',
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onTertiaryContainer,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        result.prompt ?? '',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onTertiaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // ─── مرشحون ───
    if (result.step == ConversationStep.showCandidates) {
      return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Card(
          color: theme.colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.person_search,
                        color: theme.colorScheme.primary, size: 20),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        result.prompt ?? 'اختر الحساب',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_candidates.isNotEmpty) ...[
                  ..._candidates.asMap().entries.map((e) {
                    final c = e.value;
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      child: ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: theme.colorScheme.primary,
                          child: Text(
                            c.name.characters.first,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        title: Text(c.name,
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: c.phone != null && c.phone!.isNotEmpty
                            ? Text(c.phone!,
                                style: const TextStyle(fontSize: 11))
                            : null,
                        trailing: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '${e.key + 1}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        onTap: () => _selectCandidate(e.key),
                      ),
                    );
                  }),
                ],
                const Divider(),
                FilledButton.icon(
                  onPressed: _addNewCustomer,
                  icon: const Icon(Icons.person_add),
                  label: const Text('إضافة حساب جديد'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.teal,
                    minimumSize: const Size(double.infinity, 44),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // ─── محفوظ ───
    if (result.step == ConversationStep.saved) {
      return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Card(
          color: Colors.green.withOpacity(0.15),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.check_circle,
                    color: Colors.green, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        result.ttsMessage ?? '✅ تم التنفيذ بنجاح',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                      if (result.matchedCustomer != null)
                        Text(
                          result.matchedCustomer!.name,
                          style: const TextStyle(fontSize: 13),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // ─── فشل ───
    if (result.step == ConversationStep.failed) {
      return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Card(
          color: Colors.orange.withOpacity(0.15),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.warning_amber,
                    color: Colors.orange, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    result.errorMessage ?? 'فشل الحوار',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  // ═══════════════════════════════════════════════════════════
  // عرض الاستعلام
  // ═══════════════════════════════════════════════════════════
  Widget _buildQueryView(QueryResult result, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Card(
        color: theme.colorScheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.info_outline,
                      color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text('الإجابة:',
                      style: TextStyle(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
                ],
              ),
              const SizedBox(height: 12),
              Text(result.spokenAnswer,
                  style: TextStyle(
                      fontSize: 15,
                      color: theme.colorScheme.onPrimaryContainer)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.volume_up,
                      size: 20, color: theme.colorScheme.primary),
                  const SizedBox(width: 6),
                  TextButton(
                    onPressed: () => TtsService.speak(result.spokenAnswer),
                    child: const Text('أعد الإجابة صوتياً'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // عرض إضافة حساب (Legacy)
  // ═══════════════════════════════════════════════════════════
  Widget _buildAddAccountView(ParsedPartial parsed, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Card(
        color: theme.colorScheme.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('➕ إنشاء حساب جديد',
                  style: TextStyle(
                      color: theme.colorScheme.onSecondaryContainer,
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
              const SizedBox(height: 12),
              _infoRow('الاسم', parsed.customerName ?? '—', theme),
              _infoRow(
                  'النوع',
                  AccountType.labelsAr[parsed.accountType] ?? '',
                  theme),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setState(() {
                        _addAccountParsed = null;
                        _text = '';
                      }),
                      child: const Text('إلغاء'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: _saveAccount,
                      child: const Text('إنشاء'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(String key, String value, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text('$key:',
                style: TextStyle(
                    color: theme.colorScheme.onSecondaryContainer,
                    fontWeight: FontWeight.bold)),
          ),
          Expanded(
              child: Text(value,
                  style: TextStyle(
                      color: theme.colorScheme.onSecondaryContainer))),
        ],
      ),
    );
  }
}

// Voice Screen v1: النسخة القديمة (يدوي، بدون حوار)
// Voice Screen v2: ربط كامل مع VoiceConversationService
// - معالجة الحوار: askQuestion / showCandidates / saved / failed
// - TTS تلقائي لكل خطوة
// - بدء التسجيل تلقائيًا بعد السؤال
// - عرض تقدم الجلسة (chips للحقول)
// - عرض المرشحين كقائمة قابلة للنقر
// - زر "أضف حساب جديد" عند عدم وجود مرشح
// - احتياطي: استعلام + إضافة حساب (Legacy)
// - زر إلغاء الجلسة في الـ AppBar
// Voice Screen v3: دعم targetScreen والنوايا الجديدة
// - إحصائيات: فتح StatsScreen
// - تعديل: فتح AddAccountScreen(existing)
// - طباعة/إرسال: عرض نافذة كشف الحساب
// - بحث: توجيه المستخدم لتبويب العملاء
// - _intentLabel: يدعم جميع النوايا الجديدة
// - QueryService word-count heuristic: يتخطى الاستعلامات القصيرة التي لا تحتوي على اسم
