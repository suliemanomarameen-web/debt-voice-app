import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import '../models/account_type.dart';
import '../models/customer.dart';
import '../models/transaction.dart';
import '../services/parser_service.dart';
import '../services/speech_service.dart';

class VoiceScreen extends StatefulWidget {
  const VoiceScreen({super.key});
  @override
  State<VoiceScreen> createState() => _VoiceScreenState();
}

class _VoiceScreenState extends State<VoiceScreen> {
  final _speech = SpeechService();
  String _text = '';
  bool _listening = false;
  ParsedEntry? _parsed;
  Customer? _foundCustomer;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _speech.init();
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
      _foundCustomer = null;
      _errorMessage = null;
      _listening = true;
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
        _errorMessage = null;
      });
      return;
    }

    final db = DatabaseHelper.instance;
    final customer = await db.findCustomerByName(parsed.customerName);

    if (customer == null) {
      setState(() {
        _parsed = null;
        _foundCustomer = null;
        _errorMessage = '❌ لا يوجد حساب باسم "${parsed.customerName}"\n\n'
            'قل: "أضف حساب عميل ${parsed.customerName}" لإنشائه.';
      });
      return;
    }

    setState(() {
      _parsed = parsed;
      _foundCustomer = customer;
      _errorMessage = null;
    });
  }

  Future<void> _saveAccount() async {
    if (_parsed == null || _parsed!.customerName.isEmpty) return;
    final db = DatabaseHelper.instance;

    final existing = await db.findCustomerByName(_parsed!.customerName);
    if (existing != null) {
      setState(() {
        _errorMessage = 'الحساب "${_parsed!.customerName}" موجود مسبقاً';
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✅ تم إنشاء حساب: ${_parsed!.customerName} '
            '(${AccountType.labelsAr[_parsed!.accountType]})'),
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
              if (p.warning != null) ...[
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(p.warning!,
                      style: const TextStyle(
                          fontSize: 12, color: Colors.deepOrange)),
                ),
                const SizedBox(height: 12),
              ],
              Text('الاسم: ${c.name}'),
              Text('المبلغ: ${p.amount.toStringAsFixed(0)} ${p.currency}'),
              if (p.items.isNotEmpty) Text('الأصناف: ${p.items}'),
              const Divider(),
              Text('الرصيد الجديد: ${newBalance.toStringAsFixed(0)} ${p.currency}',
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

              if (_parsed != null) ...[
                const SizedBox(height: 24),
                Card(
                  color: _parsed!.intent == 'add_account'
                      ? Colors.blue.shade50
                      : Colors.green.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _parsed!.intent == 'add_account'
                              ? '➕ إنشاء حساب جديد'
                              : '✅ النتيجة:',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 12),
                        if (_parsed!.intent != 'add_account') ...[
                          _row('النوع', _typeLabel(_parsed!.intent)),
                          _row('الاسم', _parsed!.customerName),
                          _row(
                              'المبلغ',
                              '${_parsed!.amount.toStringAsFixed(0)} ${_parsed!.currency}'),
                          if (_parsed!.items.isNotEmpty)
                            _row('الأصناف', _parsed!.items),
                        ] else ...[
                          _row('الاسم', _parsed!.customerName),
                          _row('النوع',
                              AccountType.labelsAr[_parsed!.accountType] ?? ''),
                        ],
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => setState(() {
                                  _parsed = null;
                                  _text = '';
                                  _foundCustomer = null;
                                  _errorMessage = null;
                                }),
                                child: const Text('إلغاء'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilledButton(
                                onPressed: _parsed!.intent == 'add_account'
                                    ? _saveAccount
                                    : _saveTransaction,
                                child: Text(_parsed!.intent == 'add_account'
                                    ? 'إنشاء'
                                    : 'حفظ'),
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
