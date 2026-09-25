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
  List<Customer> _matches = [];
  String? _errorMessage;
  bool _askingWhich = false;

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
      _matches = [];
      _errorMessage = null;
      _askingWhich = false;
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

    // إنشاء حساب جديد
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

    // معاملة عادية: البحث الذكي
    final db = DatabaseHelper.instance;

    // 1) مطابقة كاملة أولاً
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

    // 2) بحث جزئي
    final partial = await db.findCustomersContaining(parsed.customerName);

    if (partial.isEmpty) {
      setState(() {
        _parsed = null;
        _foundCustomer = null;
        _matches = [];
        _errorMessage = '❌ لا يوجد حساب باسم "${parsed.customerName}"\n\n'
            'قل: "أضف حساب عميل ${parsed.customerName}" لإنشائه.';
      });
      return;
    }

    // 3) نتيجة واحدة
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

    // 4) أكثر من نتيجة → اسأل
    setState(() {
      _parsed = parsed;
      _foundCustomer = null;
      _matches = partial;
      _errorMessage = null;
      _askingWhich = true;
    });
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
