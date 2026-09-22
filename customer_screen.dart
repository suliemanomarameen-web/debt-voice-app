import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import '../models/customer.dart';
import '../models/transaction.dart';

class CustomerScreen extends StatefulWidget {
  final Customer customer;
  const CustomerScreen({super.key, required this.customer});
  @override
  State<CustomerScreen> createState() => _CustomerScreenState();
}

class _CustomerScreenState extends State<CustomerScreen> {
  final db = DatabaseHelper.instance;
  double _balance = 0;
  List<Transaction> _tx = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final bal = await db.customerBalance(widget.customer.id!);
    final tx = await db.customerTransactions(widget.customer.id!);
    if (!mounted) return;
    setState(() { _balance = bal; _tx = tx; });
  }

  Future<void> _addTransaction(String type) async {
    final amountCtrl = TextEditingController();
    final itemsCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(type == 'debt' ? 'دين جديد' : 'دفعة سداد'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'المبلغ'),
              ),
              if (type == 'debt')
                TextField(
                  controller: itemsCtrl,
                  decoration: const InputDecoration(labelText: 'الأصناف'),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context),
                child: const Text('إلغاء')),
            FilledButton(
              onPressed: () async {
                final amt = double.tryParse(amountCtrl.text);
                if (amt == null || amt <= 0) return;
                await db.insertTransaction(Transaction(
                  customerId: widget.customer.id!,
                  amount: amt,
                  type: type,
                  items: itemsCtrl.text.trim(),
                  createdAt: DateTime.now().toIso8601String(),
                ));
                if (mounted) Navigator.pop(context);
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: Text(widget.customer.name)),
        body: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              color: _balance > 0 ? Colors.red.shade50 : Colors.green.shade50,
              child: Column(
                children: [
                  const Text('الرصيد المتبقي'),
                  Text('${_balance.toStringAsFixed(0)} ريال',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: _balance > 0
                            ? Colors.red.shade700
                            : Colors.green.shade700,
                      )),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: _tx.length,
                itemBuilder: (_, i) {
                  final t = _tx[i];
                  final isDebt = t.type == 'debt';
                  return ListTile(
                    leading: Icon(
                      isDebt ? Icons.arrow_upward : Icons.arrow_downward,
                      color: isDebt ? Colors.red : Colors.green,
                    ),
                    title: Text('${t.amount.toStringAsFixed(0)} ${t.currency}'),
                    subtitle: Text(t.items.isEmpty ? t.type : t.items),
                    trailing: Text(t.createdAt.substring(0, 10)),
                  );
                },
              ),
            ),
          ],
        ),
        bottomNavigationBar: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _addTransaction('debt'),
                  icon: const Icon(Icons.add),
                  label: const Text('دين'),
                  style: FilledButton.styleFrom(backgroundColor: Colors.red),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _addTransaction('payment'),
                  icon: const Icon(Icons.payments),
                  label: const Text('سداد'),
                  style: FilledButton.styleFrom(backgroundColor: Colors.green),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}