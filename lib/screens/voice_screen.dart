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

    // 1) هل هي استعلام؟
    if (QueryService.isQuery(_text)) {
      final result = await QueryService.query(_text);
      if (!mounted) return;
      setState(() {
        _queryResult = result;
        _parsed = null;
        _errorMessage = null;
      });
      // انطق الجواب
      await TtsService.speak(result.spokenAnswer);
      return;
    }

    // 2) معاملة عادية
    final parsed = ParserService.parse(_text);
    if (parsed == null) {
      setState(() {
        _parsed = null;
        _errorMessage = 'لم أفهم الجملة. جرّب: "سجل على محمد 1500 ريال"';
      });
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
      await TtsService.speak('لا يوجد حساب باسم ${parsed.customerName}');
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
    await TtsService.speak('أي حساب تقصد؟');
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
      return;
    }

    await db.insertCustomer(Customer(
      name: _parsed!.customerName,
      accountType: _parsed!.accountType,
      createdAt: DateTime.now().toIso8601String(),
    ));

    if (!mounted) return;
    await TtsService.speak('تم إنشاء حساب ${_parsed!.customerName}');
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

    // نطق التأكيد
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
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
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
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('تسجيل بالصوت')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // النص المكتشف
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('النص المكتشف:',
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 8),
                    Text(
                      _text.isEmpty
                          ? (_listening ? '🎙️ أستمع...' : 'اضغط الزر وتحدّث')
                          : _text,
                      style: const TextStyle(fontSize: 16),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // زر الميكروفون
              GestureDetector(
                onTap: _toggle,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _listening ? Colors.red : Colors.green,
                    boxShadow: [
                      BoxShadow(
                        color: (_listening ? Colors.red : Colors.green)
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
                  style: const TextStyle(fontSize: 16)),

              // خطأ
              if (_errorMessage != null) ...[
                const SizedBox(height: 20),
                Card(
                  color: Colors.red.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red),
                        const SizedBox(width: 12),
                        Expanded(child: Text(_errorMessage!)),
                      ],
                    ),
                  ),
                ),
              ],

              // نتيجة الاستعلام
              if (_queryResult != null) ...[
                const SizedBox(height: 20),
                Card(
                  color: Colors.blue.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.info_outline, color: Colors.blue),
                            SizedBox(width: 8),
                            Text('الإجابة:',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 16)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(_queryResult!.spokenAnswer,
                            style: const TextStyle(fontSize: 15)),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(Icons.volume_up, size: 20),
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

              // قائمة الاختيار
              if (_askingWhich && _matches.isNotEmpty) ...[
                const SizedBox(height: 20),
                Card(
                  color: Colors.orange.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.help_outline, color: Colors.orange),
                            SizedBox(width: 8),
                            Text('أي حساب تقصد؟',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 16)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ..._matches.map((c) => ListTile(
                              leading: CircleAvatar(
                                child: Text(c.name.characters.first),
                              ),
                              title: Text(c.name),
                              subtitle: Text(
                                  AccountType.labelsAr[c.accountType] ?? ''),
                              trailing: const Icon(Icons.arrow_forward_ios,
                                  size: 16),
                              onTap: () => _chooseCustomer(c),
                            )),
                      ],
                    ),
                  ),
                ),
              ],

              // بطاقة التأكيد
              if (_parsed != null && _foundCustomer != null) ...[
                const SizedBox(height: 24),
                Card(
                  color: Colors.green.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('✅ تأكيد:',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 12),
                        _row('النوع', _typeLabel(_parsed!.intent)),
                        _row('الحساب', _foundCustomer!.name),
                        _row(
                            'المبلغ',
                            '${_parsed!.amount.toStringAsFixed(0)} ${_parsed!.currency}'),
                        if (_parsed!.items.isNotEmpty)
                          _row('الأصناف', _parsed!.items),
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

              // بطاقة إنشاء حساب
              if (_parsed != null &&
                  _parsed!.intent == 'add_account' &&
                  _foundCustomer == null) ...[
                const SizedBox(height: 24),
                Card(
                  color: Colors.blue.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('➕ إنشاء حساب جديد',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 12),
                        _row('الاسم', _parsed!.customerName),
                        _row('النوع',
                            AccountType.labelsAr[_parsed!.accountType] ?? ''),
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

  Widget _row(String key, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text('$key:',
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
