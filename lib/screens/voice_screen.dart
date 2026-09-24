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
  String _text = '';
  bool _listening = false;
  ParsedEntry? _parsed;
  bool _processing = false;

  @override
  void initState() {
    super.initState();
    SpeechService.init();
  }

  Future<void> _startListening() async {
    setState(() {
      _listening = true;
      _text = '';
      _parsed = null;
    });

    await SpeechService.listen(
      onResult: (text, isFinal) {
        setState(() => _text = text);
        if (isFinal) {
          setState(() => _listening = false);
          _processText();
        }
      },
    );
  }

  Future<void> _stopListening() async {
    await SpeechService.stop();
    setState(() => _listening = false);
    if (_text.isNotEmpty) _processText();
  }

  void _processText() {
    final parsed = ParserService.parse(_text);
    setState(() => _parsed = parsed);
  }

  Future<void> _confirmAndSave() async {
    if (_parsed == null) return;
    setState(() => _processing = true);

    final db = DatabaseHelper.instance;
    // 1) ابحث عن الحساب أو أنشئه
    var customer = await db.findCustomerByName(_parsed!.customerName);
    customer ??= Customer(
      id: await db.insertCustomer(Customer(
        name: _parsed!.customerName,
        accountType: AccountType.customer,
        createdAt: DateTime.now().toIso8601String(),
      )),
      name: _parsed!.customerName,
      accountType: AccountType.customer,
      createdAt: DateTime.now().toIso8601String(),
    );

    // 2) أضف المعاملة
    await db.insertTransaction(Transaction(
      customerId: customer.id!,
      amount: _parsed!.amount,
      currency: _parsed!.currency,
      type: _parsed!.type,
      items: _parsed!.items,
      createdAt: DateTime.now().toIso8601String(),
    ));

    // 3) احسب الرصيد الجديد
    final balance = await db.customerBalance(customer.id!);

    setState(() => _processing = false);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _parsed!.type == 'debt'
              ? 'تم تسجيل ${_parsed!.amount.toStringAsFixed(0)} ${_parsed!.currency} على ${customer.name}'
              : 'تم تسجيل دفعة من ${customer.name} — الباقي: ${balance.toStringAsFixed(0)}',
        ),
        backgroundColor: Colors.green,
      ),
    );

    Navigator.pop(context, true);
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
              // زر الميكروفون
              GestureDetector(
                onTap: _listening ? _stopListening : _startListening,
                child: Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    color: _listening ? Colors.red : Colors.green,
                    shape: BoxShape.circle,
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
                    size: 70,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _listening
                    ? '🎙️ أستمع...'
                    : 'اضغط للتحدث',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),

              // النص المُستخرج
              if (_text.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('📝 ما سمعته:',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      Text(_text, style: const TextStyle(fontSize: 16)),
                    ],
                  ),
                ),
              const SizedBox(height: 16),

              // نتيجة التحليل
              if (_parsed != null) _buildParsedCard(),
              if (_text.isNotEmpty && _parsed == null && !_listening)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    '⚠️ لم أفهم الجملة. جرّب مثلاً:\n"سجل على محمد 1500 ريال خميرة شاي"',
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildParsedCard() {
    final p = _parsed!;
    final isDebt = p.type == 'debt';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDebt ? Colors.red.shade50 : Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isDebt ? Colors.red.shade200 : Colors.green.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(isDebt ? Icons.arrow_upward : Icons.arrow_downward,
                  color: isDebt ? Colors.red : Colors.green),
              const SizedBox(width: 8),
              Text(isDebt ? '🔴 دين جديد' : '🟢 سداد',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          const Divider(),
          _row('الاسم', p.customerName),
          _row('المبلغ', '${p.amount.toStringAsFixed(0)} ${p.currency}'),
          if (p.items.isNotEmpty) _row('الأصناف', p.items),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() {
                    _parsed = null;
                    _text = '';
                  }),
                  child: const Text('إلغاء'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: _processing ? null : _confirmAndSave,
                  style: FilledButton.styleFrom(
                    backgroundColor: isDebt ? Colors.red : Colors.green,
                  ),
                  child: _processing
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('حفظ'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(width: 80, child: Text('$k:',
                style: const TextStyle(fontWeight: FontWeight.bold))),
            Expanded(child: Text(v, style: const TextStyle(fontSize: 16))),
          ],
        ),
      );
}
