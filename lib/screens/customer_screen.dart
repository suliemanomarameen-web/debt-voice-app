import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import '../models/customer.dart';
import '../models/transaction.dart';
import 'add_account_screen.dart';

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
    setState(() {
      _balance = bal;
      _tx = tx;
    });
  }

  // ============ إضافة معاملة ============
  Future<void> _addTransaction(String type) async {
    final amountCtrl = TextEditingController();
    final itemsCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(type == 'debt'
              ? 'دين جديد'
              : type == 'return'
                  ? 'مرتجع جديد'
                  : 'دفعة سداد'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'المبلغ'),
              ),
              if (type != 'payment')
                TextField(
                  controller: itemsCtrl,
                  decoration: const InputDecoration(labelText: 'الأصناف'),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () async {
                final amt = double.tryParse(amountCtrl.text);
                if (amt == null || amt <= 0) return;
                await db.insertTransaction(Transaction(
                  customerId: widget.customer.id!,
                  amount: amt,
                  type: type == 'return' ? 'payment' : type,
                  items: type == 'return'
                      ? 'مرتجع${itemsCtrl.text.trim().isEmpty ? "" : ": ${itemsCtrl.text.trim()}"}'
                      : itemsCtrl.text.trim(),
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

  // ============ تعديل معاملة ============
  Future<void> _editTransaction(Transaction t) async {
    final isDebt = t.type == 'debt';
    final isReturn = t.items.startsWith('مرتجع');
    final amountCtrl = TextEditingController(text: t.amount.toStringAsFixed(0));
    final itemsCtrl = TextEditingController(
        text: isReturn
            ? t.items.replaceFirst(RegExp(r'^مرتجع:?\s*'), '')
            : t.items);

    await showDialog(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(isDebt
              ? 'تعديل الدين'
              : isReturn
                  ? 'تعديل المرتجع'
                  : 'تعديل السداد'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'المبلغ'),
              ),
              if (isDebt || isReturn)
                TextField(
                  controller: itemsCtrl,
                  decoration: const InputDecoration(labelText: 'الأصناف'),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () async {
                final amt = double.tryParse(amountCtrl.text);
                if (amt == null || amt <= 0) return;
                await db.updateTransaction(Transaction(
                  id: t.id,
                  customerId: t.customerId,
                  amount: amt,
                  currency: t.currency,
                  type: t.type,
                  items: isReturn
                      ? 'مرتجع: ${itemsCtrl.text.trim()}'
                      : itemsCtrl.text.trim(),
                  createdAt: t.createdAt,
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

  // ============ حذف معاملة ============
  Future<void> _deleteTransaction(Transaction t) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber, color: Colors.orange),
              SizedBox(width: 8),
              Text('تأكيد الحذف'),
            ],
          ),
          content: Text(
            'سيتم حذف هذه العملية نهائياً:\n\n'
            'النوع: ${t.type == 'debt' ? 'دين' : 'سداد'}\n'
            'المبلغ: ${t.amount.toStringAsFixed(0)} ${t.currency}\n'
            '${t.items.isNotEmpty ? 'الأصناف: ${t.items}\n' : ''}\n'
            'لا يمكن التراجع عن هذا الإجراء.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('حذف نهائي'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      await db.deleteTransaction(t.id!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ تم حذف العملية'),
            backgroundColor: Colors.red,
          ),
        );
      }
      _load();
    }
  }

  // ============ حذف الحساب ============
  Future<void> _deleteCustomer() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber, color: Colors.red),
              SizedBox(width: 8),
              Text('تأكيد حذف الحساب'),
            ],
          ),
          content: Text(
            'سيتم حذف الحساب "${widget.customer.name}" وكل معاملاته (${_tx.length} عملية).\n\n'
            'لا يمكن التراجع عن هذا الإجراء.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('حذف الحساب'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      await db.deleteCustomer(widget.customer.id!);
      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ تم حذف الحساب'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ============ قائمة الخيارات ============
  void _showTransactionMenu(Transaction t) {
    showModalBottomSheet(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('تعديل'),
                onTap: () {
                  Navigator.pop(context);
                  _editTransaction(t);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('حذف', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  _deleteTransaction(t);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.customer.name),
          actions: [
            PopupMenuButton<String>(
              onSelected: (v) {
                switch (v) {
                  case 'edit':
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            AddAccountScreen(existing: widget.customer),
                      ),
                    ).then((_) => _load());
                    break;
                  case 'delete':
                    _deleteCustomer();
                    break;
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'edit',
                  child: ListTile(
                    leading: Icon(Icons.edit),
                    title: Text('تعديل بيانات الحساب'),
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    leading: Icon(Icons.delete, color: Colors.red),
                    title: Text('حذف الحساب',
                        style: TextStyle(color: Colors.red)),
                  ),
                ),
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              color: _balance > 0 ? Colors.red.shade50 : Colors.green.shade50,
              child: Column(
                children: [
                  const Text('الرصيد المتبقي'),
                  Text(
                    '${_balance.toStringAsFixed(0)} ريال',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: _balance > 0
                          ? Colors.red.shade700
                          : Colors.green.shade700,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _tx.isEmpty
                  ? const Center(child: Text('لا توجد عمليات بعد'))
                  : ListView.builder(
                      itemCount: _tx.length,
                      itemBuilder: (_, i) {
                        final t = _tx[i];
                        final isDebt = t.type == 'debt';
                        final isReturn = t.items.startsWith('مرتجع');

                        return ListTile(
                          leading: Icon(
                            isReturn
                                ? Icons.keyboard_return
                                : (isDebt
                                    ? Icons.arrow_upward
                                    : Icons.arrow_downward),
                            color: isReturn
                                ? Colors.orange
                                : (isDebt ? Colors.red : Colors.green),
                          ),
                          title: Text(
                              '${t.amount.toStringAsFixed(0)} ${t.currency}'),
                          subtitle: Text(
                            isReturn
                                ? t.items
                                : (t.items.isEmpty
                                    ? (isDebt ? 'دين' : 'سداد')
                                    : t.items),
                          ),
                          trailing: Text(t.createdAt.substring(0, 10)),
                          onLongPress: () => _showTransactionMenu(t),
                          onTap: () => _showTransactionMenu(t),
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
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _addTransaction('payment'),
                  icon: const Icon(Icons.payments),
                  label: const Text('سداد'),
                  style: FilledButton.styleFrom(backgroundColor: Colors.green),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _addTransaction('return'),
                  icon: const Icon(Icons.keyboard_return),
                  label: const Text('مرتجع'),
                  style: FilledButton.styleFrom(backgroundColor: Colors.orange),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
