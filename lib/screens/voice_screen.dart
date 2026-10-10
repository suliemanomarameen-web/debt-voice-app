import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import '../models/account_type.dart';
import '../models/customer.dart';
import '../models/transaction.dart';
import '../services/accountant_service.dart';
import '../services/audio_recorder_service.dart';
import '../services/code_service.dart';
import '../services/logger_service.dart';
import '../services/parser_service.dart';
import '../services/query_service.dart';
import '../services/speech_service.dart';
import '../services/tts_service.dart';

class VoiceScreen extends StatefulWidget {
  final String? initialText;

  const VoiceScreen({super.key, this.initialText});
  @override
  State<VoiceScreen> createState() => _VoiceScreenState();
}

class _VoiceScreenState extends State<VoiceScreen> {
  final _speech = SpeechService();
  final _audioService = AudioRecorderService();

  String _text = '';
  bool _listening = false;
  bool _recording = false;
  ParsedEntry? _parsed;
  QueryResult? _queryResult;
  Customer? _foundCustomer;
  List<Customer> _matches = [];
  String? _errorMessage;
  bool _askingWhich = false;
  bool _autoProcessed = false;

  bool _isSavingTransaction = false;
  bool _isSavingAccount = false;
  bool _isProcessing = false;

  String? _currentAudioPath;

  @override
  void initState() {
    super.initState();
    _speech.init();
    TtsService.init();

    if (widget.initialText != null && widget.initialText!.isNotEmpty) {
      _text = widget.initialText!;
      WidgetsBinding.instance.addPostFrameCallback((_) => _process());
    }
  }

  // ============================================================
  // 🎤 زر التحدث (Speech-to-Text)
  // ============================================================
  Future<void> _toggleSpeech() async {
    if (_recording) {
      await _audioService.stopRecording();
      setState(() => _recording = false);
    }

    if (_listening) {
      await _speech.stop();
      setState(() => _listening = false);
      if (_text.isNotEmpty) _process();
      return;
    }

    setState(() {
      _text = '';
      _parsed = null;
      _queryResult = null;
      _foundCustomer = null;
      _matches = [];
      _errorMessage = null;
      _askingWhich = false;
      _listening = true;
      _autoProcessed = false;
      _currentAudioPath = null;
    });

    await _speech.listen(onResult: (text, isFinal) {
      if (!mounted) return;
      setState(() => _text = text);
      if (isFinal) {
        setState(() => _listening = false);
        _process();
      }
    });
  }

  // ============================================================
  // 🔴 زر التسجيل (Record فقط)
  // ============================================================
  Future<void> _toggleRecording() async {
    if (_listening) {
      await _speech.stop();
      setState(() => _listening = false);
    }

    if (_recording) {
      final path = await _audioService.stopRecording();
      if (!mounted) return;
      setState(() {
        _recording = false;
        _currentAudioPath = path;
      });

      if (path != null) {
        await LoggerService.logVoiceSuccess(
          text: '(تسجيل صوتي محفوظ - بدون تعرف)',
          audioPath: path,
          parsedAction: 'تسجيل صوتي',
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
                      '✅ تم حفظ التسجيل — يمكنك الاستماع إليه من السجل'),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
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

  // ============================================================
  // معالجة النص
  // ============================================================
  Future<void> _process() async {
    if (_autoProcessed) return;
    _autoProcessed = true;

    if (!mounted) return;
    setState(() => _isProcessing = true);

    final audioPath = _currentAudioPath;

    try {
      if (QueryService.isQuery(_text)) {
        final result = await QueryService.query(_text);
        if (!mounted) return;
        setState(() {
          _queryResult = result;
          _parsed = null;
          _errorMessage = null;
          _isProcessing = false;
        });
        TtsService.speak(result.spokenAnswer);
        return;
      }

      final parsed = ParserService.parse(_text);
      if (parsed == null) {
        if (!mounted) return;
        setState(() {
          _parsed = null;
          _errorMessage = 'لم أفهم الجملة. جرّب: "سجل على محمد 1500 ريال"';
          _isProcessing = false;
        });

        await LoggerService.logVoiceFail(
          reason: 'لم يُفهم النص',
          text: _text,
          audioPath: audioPath,
        );

        TtsService.speakDidNotUnderstand();
        return;
      }

      if (parsed.intent == 'add_account') {
        if (!mounted) return;
        setState(() {
          _parsed = parsed;
          _foundCustomer = null;
          _matches = [];
          _errorMessage = null;
          _askingWhich = false;
          _isProcessing = false;
        });
        return;
      }

      final db = DatabaseHelper.instance;
      final matches = await db.findCustomersContaining(parsed.customerName);

      if (matches.isEmpty) {
        if (!mounted) return;
        setState(() {
          _parsed = null;
          _foundCustomer = null;
          _matches = [];
          _errorMessage = '❌ لا يوجد حساب باسم "${parsed.customerName}"';
          _isProcessing = false;
        });

        await LoggerService.logVoiceFail(
          reason: 'لا يوجد حساب بهذا الاسم',
          text: _text,
          audioPath: audioPath,
        );

        TtsService.speakNoAccount(parsed.customerName);
        return;
      }

      Customer? exact;
      for (final m in matches) {
        if (m.name == parsed.customerName) {
          exact = m;
          break;
        }
      }

      await LoggerService.logVoiceSuccess(
        text: _text,
        audioPath: audioPath,
        parsedAction: _typeLabel(parsed.intent),
      );

      if (exact != null) {
        if (!mounted) return;
        setState(() {
          _parsed = parsed;
          _foundCustomer = exact;
          _matches = [];
          _errorMessage = null;
          _askingWhich = false;
          _isProcessing = false;
        });
        return;
      }

      if (matches.length == 1) {
        if (!mounted) return;
        setState(() {
          _parsed = parsed;
          _foundCustomer = matches.first;
          _matches = [];
          _errorMessage = null;
          _askingWhich = false;
          _isProcessing = false;
        });
        return;
      }

      if (!mounted) return;
      setState(() {
        _parsed = parsed;
        _foundCustomer = null;
        _matches = matches;
        _errorMessage = null;
        _askingWhich = true;
        _isProcessing = false;
      });
      TtsService.speakMultipleAccounts();
    } catch (e) {
      debugPrint('❌ _process error: $e');
      if (!mounted) return;
      setState(() {
        _errorMessage = 'حدث خطأ: $e';
        _isProcessing = false;
      });
    }
  }

  void _chooseCustomer(Customer c) {
    setState(() {
      _foundCustomer = c;
      _askingWhich = false;
      _matches = [];
    });
  }

  Future<void> _saveAccount() async {
    if (_isSavingAccount) return;
    if (_parsed == null || _parsed!.customerName.isEmpty) return;

    setState(() => _isSavingAccount = true);

    try {
      final db = DatabaseHelper.instance;

      final existing = await db.findExactCustomer(_parsed!.customerName);
      if (existing != null) {
        if (!mounted) return;
        setState(() {
          _errorMessage = 'الحساب موجود مسبقاً';
          _parsed = null;
        });
        TtsService.speakExistsBefore(_parsed!.customerName);
        return;
      }

      await db.insertCustomer(Customer(
        name: _parsed!.customerName,
        accountType: _parsed!.accountType,
        createdAt: DateTime.now().toIso8601String(),
      ));

      await LoggerService.logCustomerAdded(_parsed!.customerName);

      if (!mounted) return;
      TtsService.speakAccountCreated(_parsed!.customerName);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ تم إنشاء حساب: ${_parsed!.customerName}'),
          backgroundColor: Colors.green,
        ),
      );
      setState(() {
        _parsed = null;
        _text = '';
      });
    } finally {
      if (mounted) {
        setState(() => _isSavingAccount = false);
      }
    }
  }

  Future<void> _saveTransaction() async {
    if (_isSavingTransaction) return;

    final p = _parsed;
    final c = _foundCustomer;
    if (p == null || c == null) return;

    setState(() => _isSavingTransaction = true);

    try {
      final db = DatabaseHelper.instance;

      final normalizedType = CodeService.normalizeType(p.intent);
      final storedType =
          (normalizedType == 'return') ? 'payment' : normalizedType;

      final results = await Future.wait([
        db.transactionExistsRecent(
          customerId: c.id!,
          amount: p.amount.toDouble(),
          type: storedType,
          window: const Duration(seconds: 30),
        ),
        AccountantService.getAccountantName(),
        CodeService.generateCode(normalizedType),
      ]);

      final isDuplicate = results[0] as bool;
      final accountant = results[1] as String?;
      final code = results[2] as String?;

      if (isDuplicate) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ هذه العملية مسجلة بالفعل (خلال آخر 30 ثانية)'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
        return;
      }

      await db.insertTransaction(Transaction(
        customerId: c.id!,
        code: code,
        accountant: accountant,
        source: 'voice',
        amount: p.amount,
        currency: p.currency,
        type: storedType,
        items: normalizedType == 'return'
            ? 'مرتجع${p.items.isEmpty ? "" : ": ${p.items}"}'
            : p.items,
        createdAt: DateTime.now().toIso8601String(),
      ));

      final newBalance = await db.customerBalance(c.id!);
      if (!mounted) return;

      final label = {
        'debt': 'دين',
        'payment': 'سداد',
        'return': 'مرتجع',
      }[normalizedType] ?? 'عملية';

      await LoggerService.logTransactionAdded(
        typeLabel: label,
        customerName: c.name,
        amount: p.amount,
        currency: p.currency,
        code: code,
        accountant: accountant,
        source: 'voice',
      );

      TtsService.confirmTransaction(
        type: label,
        amount: p.amount,
        customerName: c.name,
        newBalance: newBalance,
        currency: p.currency,
      );

      if (!mounted) return;

      final title = {
        'debt': '✅ تم تسجيل الدين',
        'payment': '✅ تم تسجيل السداد',
        'return': '✅ تم تسجيل المرتجع',
      }[normalizedType] ?? '✅ تم التسجيل';

      final theme = Theme.of(context);

      await showDialog(
        context: context,
        builder: (_) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Text(title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('الاسم: ${c.name}'),
                if (code != null) Text('الرمز: $code'),
                if (accountant != null && accountant.isNotEmpty)
                  Text('المحاسب: $accountant'),
                Text('المبلغ: ${p.amount.toStringAsFixed(0)} ${p.currency}'),
                if (p.items.isNotEmpty) Text('الأصناف: ${p.items}'),
                const Divider(),
                Text('الرصيد: ${newBalance.toStringAsFixed(0)} ${p.currency}',
                    style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
              ],
            ),
            actions: [
              FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pop(context, true);
                },
                child: const Text('تم'),
              ),
            ],
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSavingTransaction = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('تسجيل بالصوت')),
        body: Column(
          children: [
            if (_isProcessing)
              const LinearProgressIndicator(minHeight: 3),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // ===== النص المكتشف =====
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

                    // ===== 🆕 زرّان: التحدث + التسجيل =====
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // 🎤 زر التحدث
                        Column(
                          children: [
                            GestureDetector(
                              onTap: _isProcessing ? null : _toggleSpeech,
                              child: Container(
                                width: 100,
                                height: 100,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _listening
                                      ? Colors.red
                                      : theme.colorScheme.primary,
                                  boxShadow: [
                                    BoxShadow(
                                      color: (_listening
                                              ? Colors.red
                                              : theme.colorScheme.primary)
                                          .withOpacity(0.4),
                                      blurRadius: 15,
                                      spreadRadius: 3,
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  _listening ? Icons.stop : Icons.mic,
                                  color: Colors.white,
                                  size: 45,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _listening ? 'إيقاف' : 'تحدث',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: _listening
                                    ? Colors.red
                                    : theme.colorScheme.onSurface,
                              ),
                            ),
                            const Text(
                              '(يتعرف على النص)',
                              style: TextStyle(
                                  fontSize: 10, color: Colors.grey),
                            ),
                          ],
                        ),

                        // 🔴 زر التسجيل
                        Column(
                          children: [
                            GestureDetector(
                              onTap: _isProcessing ? null : _toggleRecording,
                              child: Container(
                                width: 100,
                                height: 100,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _recording
                                      ? Colors.red
                                      : Colors.deepOrange,
                                  boxShadow: [
                                    BoxShadow(
                                      color: (_recording
                                              ? Colors.red
                                              : Colors.deepOrange)
                                          .withOpacity(0.4),
                                      blurRadius: 15,
                                      spreadRadius: 3,
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  _recording
                                      ? Icons.stop_circle
                                      : Icons.fiber_manual_record,
                                  color: Colors.white,
                                  size: 45,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _recording ? 'إيقاف التسجيل' : 'سجّل',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: _recording
                                    ? Colors.red
                                    : theme.colorScheme.onSurface,
                              ),
                            ),
                            const Text(
                              '(يحفظ ملف صوتي)',
                              style: TextStyle(
                                  fontSize: 10, color: Colors.grey),
                            ),
                          ],
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // ===== رسالة الحالة =====
                    Text(
                      _isProcessing
                          ? '⏳ جاري المعالجة...'
                          : _listening
                              ? '🎙️ أستمع... تحدث بوضوح'
                              : _recording
                                  ? '🔴 جاري التسجيل... اضغط ⏹️ للحفظ'
                                  : 'اضغط "تحدث" للتعرف، أو "سجّل" لحفظ الصوت',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),

                    // ===== معاينة الصوت =====
                    if (_currentAudioPath != null && !_recording) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: Colors.green.withOpacity(0.4)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.check_circle,
                                color: Colors.green, size: 20),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'تم حفظ التسجيل — يمكنك الاستماع إليه من السجل',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // ===== الأخطاء =====
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 20),
                      Card(
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
                                          color: theme
                                              .colorScheme
                                              .onErrorContainer))),
                            ],
                          ),
                        ),
                      ),
                    ],

                    // ===== الإجابة =====
                    if (_queryResult != null) ...[
                      const SizedBox(height: 20),
                      Card(
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
                                          color: theme.colorScheme
                                              .onPrimaryContainer,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16)),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(_queryResult!.spokenAnswer,
                                  style: TextStyle(
                                      fontSize: 15,
                                      color: theme.colorScheme
                                          .onPrimaryContainer)),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Icon(Icons.volume_up,
                                      size: 20,
                                      color: theme.colorScheme.primary),
                                  const SizedBox(width: 6),
                                  TextButton(
                                    onPressed: () => TtsService.speak(
                                        _queryResult!.spokenAnswer),
                                    child: const Text('أعد الإجابة صوتياً'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],

                    // ===== اختيار العميل =====
                    if (_askingWhich && _matches.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Card(
                        color: theme.colorScheme.tertiaryContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.help_outline,
                                      color: theme.colorScheme.tertiary),
                                  const SizedBox(width: 8),
                                  Text('أي حساب تقصد؟',
                                      style: TextStyle(
                                          color: theme.colorScheme
                                              .onTertiaryContainer,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16)),
                                ],
                              ),
                              const SizedBox(height: 12),
                              ..._matches.map((c) => ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor:
                                          theme.colorScheme.primary,
                                      child: Text(c.name.characters.first,
                                          style: const TextStyle(
                                              color: Colors.white)),
                                    ),
                                    title: Text(c.name,
                                        style: TextStyle(
                                            color: theme.colorScheme
                                                .onTertiaryContainer)),
                                    subtitle: Text(
                                        AccountType.labelsAr[c.accountType] ??
                                            '',
                                        style: TextStyle(
                                            color: theme.colorScheme
                                                .onTertiaryContainer)),
                                    trailing: const Icon(
                                        Icons.arrow_forward_ios,
                                        size: 16),
                                    onTap: () => _chooseCustomer(c),
                                  )),
                            ],
                          ),
                        ),
                      ),
                    ],

                    // ===== تأكيد العملية =====
                    if (_parsed != null && _foundCustomer != null) ...[
                      const SizedBox(height: 24),
                      Card(
                        color: theme.colorScheme.primaryContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('✅ تأكيد:',
                                  style: TextStyle(
                                      color: theme
                                          .colorScheme.onPrimaryContainer,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16)),
                              const SizedBox(height: 12),
                              _row('النوع', _typeLabel(_parsed!.intent),
                                  theme),
                              _row('الحساب', _foundCustomer!.name, theme),
                              _row(
                                  'المبلغ',
                                  '${_parsed!.amount.toStringAsFixed(0)} ${_parsed!.currency}',
                                  theme),
                              if (_parsed!.items.isNotEmpty)
                                _row('الأصناف', _parsed!.items, theme),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: _isSavingTransaction
                                          ? null
                                          : () => setState(() {
                                                _parsed = null;
                                                _text = '';
                                                _foundCustomer = null;
                                                _matches = [];
                                                _errorMessage = null;
                                                _askingWhich = false;
                                              }),
                                      child: const Text('إلغاء'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: FilledButton(
                                      onPressed: _isSavingTransaction
                                          ? null
                                          : _saveTransaction,
                                      child: _isSavingTransaction
                                          ? const SizedBox(
                                              width: 20,
                                              height: 20,
                                              child:
                                                  CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            )
                                          : const Text('حفظ'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],

                    // ===== إنشاء حساب =====
                    if (_parsed != null &&
                        _parsed!.intent == 'add_account' &&
                        _foundCustomer == null) ...[
                      const SizedBox(height: 24),
                      Card(
                        color: theme.colorScheme.secondaryContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('➕ إنشاء حساب جديد',
                                  style: TextStyle(
                                      color: theme
                                          .colorScheme.onSecondaryContainer,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16)),
                              const SizedBox(height: 12),
                              _row('الاسم', _parsed!.customerName, theme),
                              _row(
                                  'النوع',
                                  AccountType.labelsAr[_parsed!.accountType] ??
                                      '',
                                  theme),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: _isSavingAccount
                                          ? null
                                          : () => setState(() {
                                                _parsed = null;
                                                _text = '';
                                                _errorMessage = null;
                                              }),
                                      child: const Text('إلغاء'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: FilledButton(
                                      onPressed: _isSavingAccount
                                          ? null
                                          : _saveAccount,
                                      child: _isSavingAccount
                                          ? const SizedBox(
                                              width: 20,
                                              height: 20,
                                              child:
                                                  CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            )
                                          : const Text('إنشاء'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _typeLabel(String intent) {
    return {
      'debt': 'دين',
      'payment': 'سداد',
      'return': 'مرتجع',
      'add_account': 'إنشاء حساب',
    }[intent] ?? intent;
  }

  Widget _row(String key, String value, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text('$key:',
                style: TextStyle(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold)),
          ),
          Expanded(
              child: Text(value,
                  style: TextStyle(
                      color: theme.colorScheme.onPrimaryContainer))),
        ],
      ),
    );
  }
}
