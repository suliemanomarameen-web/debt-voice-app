import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import '../models/account_type.dart';
import '../models/customer.dart';
import '../models/transaction.dart';
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
  String _text = '';
  bool _listening = false;
  ParsedEntry? _parsed;
  QueryResult? _queryResult;
  Customer? _foundCustomer;
  List<Customer> _matches = [];
  String? _errorMessage;
  bool _askingWhich = false;
  bool _autoProcessed = false;

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

  Future<void> _toggle() async {
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

  Future<void> _process() async {
    if (_autoProcessed) return;
    _autoProcessed = true;

    // 1) استعلام
    if (QueryService.isQuery(_text)) {
      final result = await QueryService.query(_text);
      if (!mounted) return;
      setState(() {
        _queryResult = result;
        _parsed = null;
        _errorMessage = null;
      });
      await TtsService.speak(result.spokenAnswer);
      return;
    }

    // 2) معاملة
    final parsed = ParserService.parse(_text);
    if (parsed == null) {
      setState(() {
        _parsed = null;
        _errorMessage = 'لم أفهم الجملة. جرّب: "سجل على محمد 1500 ريال"';
      });
      await TtsService.speakDidNotUnderstand();
      return;
    }

    if (parsed.intent == 'add_account') {
      setState(() {
        _parsed = parsed;
        _foundCustomer = null;
        _matches = [];
        _errorMessage = null;
        _askingWhich = false;
      });
      return;
    }

    final db = DatabaseHelper.instance;
    final exact = await db.findExactCustomer(parsed.customerName);
    if (exact != null) {
      setState(() {
        _parsed = parsed;
        _foundCustomer = exact;
        _matches = [];
        _errorMessage = null;
        _askingWhich = false;
      });
      return;
    }

    final partial = await db.findCustomersContaining(parsed.customerName);
    if (partial.isEmpty) {
      setState(() {
        _parsed = null;
        _foundCustomer = null;
        _matches = [];
        _errorMessage = '❌ لا يوجد حساب باسم "${parsed.customerName}"';
      });
      await TtsService.speakNoAccount(parsed.customerName);
      return;
    }

    if (partial.length == 1) {
      setState(() {
        _parsed = parsed;
        _foundCustomer = partial.first;
        _matches = [];
        _errorMessage = null;
        _askingWhich = false;
      });
      return;
    }

    setState(() {
      _parsed = parsed;
      _foundCustomer = null;
      _matches = partial;
      _errorMessage = null;
      _askingWhich = true;
    });
    await TtsService.speakMultipleAccounts();
  }

  void _chooseCustomer(Customer c) {
    setState(() {
      _foundCustomer = c;
      _askingWhich = false;
      _matches = [];
    });
  }

  Future<void> _saveAccount() async {
    if (_parsed == null || _parsed!.customerName.isEmpty) return;
    final db = DatabaseHelper.instance;

    final existing = await db.findExactCustomer(_parsed!.customerName);
    if (existing != null) {
      setState(() {
        _errorMessage = 'الحساب موجود مسبقاً';
        _parsed = null;
      });
      await TtsService.speakExistsBefore(_parsed!.customerName);
      return;
    }

    await db.insertCustomer(Customer(
      name: _parsed!.customerName,
      accountType: _parsed!.accountType,
      createdAt: DateTime.now().toIso8601String(),
    ));

    if (!mounted) return;
    await TtsService.speakAccountCreated(_parsed!.customerName);
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
  }

  Future<void> _saveTransaction() async {
    final p = _parsed;
    final c = _foundCustomer;
    if (p == null || c == null) return;
    final db = DatabaseHelper.instance;

    final storedType = (p.intent == 'return') ? 'payment' : p.intent;

    await db.insertTransaction(Transaction(
      customerId: c.id!,
      amount: p.amount,
      currency: p.currency,
      type: storedType,
      items: p.intent == 'return'
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
    }[p.intent] ?? 'عملية';

    await TtsService.confirmTransaction(
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
    }[p.intent] ?? '✅ تم التسجيل';

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
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('تسجيل بالصوت')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: theme.colorScheme.outline.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('النص المكتشف:',
                        style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 8),
                    Text(
                      _text.isEmpty
                          ? (_listening ? '🎙️ أستمع...' : 'اضغط الزر وتحدّث')
                          : _text,
                      style: TextStyle(
                          fontSize: 16,
                          color: theme.colorScheme.onSurface,
                          fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: _toggle,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _listening ? Colors.red : theme.colorScheme.primary,
                    boxShadow: [
                      BoxShadow(
                        color: (_listening
                                ? Colors.red
                                : theme.colorScheme.primary)
                            .withOpacity(0.4),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Icon(
                    _listening ? Icons.stop : Icons.mic,
                    color: Colors.white,
                    size: 50,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(_listening ? 'أستمع...' : 'اضغط للتحدث',
                  style: TextStyle(
                      fontSize: 16, color: theme.colorScheme.onSurface)),

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
                                    color:
                                        theme.colorScheme.onErrorContainer))),
                      ],
                    ),
                  ),
                ),
              ],

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
                                    color:
                                        theme.colorScheme.onPrimaryContainer,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(_queryResult!.spokenAnswer,
                            style: TextStyle(
                                fontSize: 15,
                                color: theme.colorScheme.onPrimaryContainer)),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Icon(Icons.volume_up,
                                size: 20,
                                color: theme.colorScheme.primary),
                            const SizedBox(width: 6),
                            TextButton(
                              onPressed: () =>
                                  TtsService.speak(_queryResult!.spokenAnswer),
                              child: const Text('أعد الإجابة صوتياً'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],

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
                                    color:
                                        theme.colorScheme.onTertiaryContainer,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ..._matches.map((c) => ListTile(
                              leading: CircleAvatar(
                                backgroundColor: theme.colorScheme.primary,
                                child: Text(c.name.characters.first,
                                    style: const TextStyle(
                                        color: Colors.white)),
                              ),
                              title: Text(c.name,
                                  style: TextStyle(
                                      color: theme
                                          .colorScheme.onTertiaryContainer)),
                              subtitle: Text(
                                  AccountType.labelsAr[c.accountType] ?? '',
                                  style: TextStyle(
                                      color: theme
                                          .colorScheme.onTertiaryContainer)),
                              trailing: const Icon(Icons.arrow_forward_ios,
                                  size: 16),
                              onTap: () => _chooseCustomer(c),
                            )),
                      ],
                    ),
                  ),
                ),
              ],

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
                                color: theme.colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.bold,
                                fontSize: 16)),
                        const SizedBox(height: 12),
                        _row('النوع', _typeLabel(_parsed!.intent), theme),
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
                                onPressed: () => setState(() {
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
                                onPressed: _saveTransaction,
                                child: const Text('حفظ'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],

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
                                color:
                                    theme.colorScheme.onSecondaryContainer,
                                fontWeight: FontWeight.bold,
                                fontSize: 16)),
                        const SizedBox(height: 12),
                        _row('الاسم', _parsed!.customerName, theme),
                        _row(
                            'النوع',
                            AccountType.labelsAr[_parsed!.accountType] ?? '',
                            theme),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => setState(() {
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
              ],
            ],
          ),
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
                  style:
                      TextStyle(color: theme.colorScheme.onPrimaryContainer))),
        ],
      ),
    );
  }
}
