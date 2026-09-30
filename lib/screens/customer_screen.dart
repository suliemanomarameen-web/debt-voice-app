import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import '../models/customer.dart';
import '../models/transaction.dart';
import '../services/date_filter.dart';
import '../services/export_service.dart';
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
  List<Transaction> _allTx = [];
  List<Transaction> _tx = [];
  DateFilter _dateFilter = DateFilter();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final bal = await db.customerBalance(widget.customer.id!);
    final allTx = await db.customerTransactions(widget.customer.id!);
    if (!mounted) return;
    setState(() {
      _balance = bal;
      _allTx = allTx;
      _applyFilter();
    });
  }

  void _applyFilter() {
    _tx = _allTx.where((t) => _dateFilter.matches(t.createdAt)).toList();
  }

  String _formatDateTime(String iso) {
    try {
      final dt = DateTime.parse(iso);
      final y = dt.year;
      final m = dt.month.toString().padLeft(2, '0');
      final d = dt.day.toString().padLeft(2, '0');
      final h = dt.hour.toString().padLeft(2, '0');
      final min = dt.minute.toString().padLeft(2, '0');
      return '$y/$m/$d - $h:$min';
    } catch (_) {
      return iso.length >= 16 ? iso.substring(0, 16) : iso;
    }
  }

  // ============ فلتر التاريخ ============
  Future<void> _showDateFilter() async {
    final result = await showModalBottomSheet<DateFilter>(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('فلترة بالتاريخ',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              ListTile(
                leading: const Icon(Icons.all_inclusive),
                title: const Text('الكل'),
                trailing: _dateFilter.type == DateFilterType.all
                    ? const Icon(Icons.check, color: Colors.green)
                    : null,
                onTap: () => Navigator.pop(context, DateFilter()),
              ),
              ListTile(
                leading: const Icon(Icons.today),
                title: const Text('اليوم'),
                trailing: _dateFilter.type == DateFilterType.today
                    ? const Icon(Icons.check, color: Colors.green)
                    : null,
                onTap: () => Navigator.pop(
                    context, DateFilter(type: DateFilterType.today)),
              ),
              ListTile(
                leading: const Icon(Icons.date_range),
                title: const Text('آخر 7 أيام'),
                trailing: _dateFilter.type == DateFilterType.week
                    ? const Icon(Icons.check, color: Colors.green)
                    : null,
                onTap: () => Navigator.pop(
                    context, DateFilter(type: DateFilterType.week)),
              ),
              ListTile(
                leading: const Icon(Icons.calendar_month),
                title: const Text('آخر 30 يوماً'),
                trailing: _dateFilter.type == DateFilterType.month
                    ? const Icon(Icons.check, color: Colors.green)
                    : null,
                onTap: () => Navigator.pop(
                    context, DateFilter(type: DateFilterType.month)),
              ),
              ListTile(
                leading: const Icon(Icons.edit_calendar),
                title: const Text('نطاق مخصص'),
                trailing: _dateFilter.type == DateFilterType.custom
                    ? const Icon(Icons.check, color: Colors.green)
                    : null,
                onTap: () async {
                  Navigator.pop(context);
                  final picked = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                    initialDateRange: DateTimeRange(
                      start: _dateFilter.from ?? DateTime.now(),
                      end: _dateFilter.to ?? DateTime.now(),
                    ),
                    locale: const Locale('ar'),
                  );
                  if (picked != null) {
                    setState(() {
                      _dateFilter = DateFilter(
                        type: DateFilterType.custom,
                        from: picked.start,
                        to: picked.end,
                      );
                      _applyFilter();
                    });
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
    if (result != null) {
      setState(() {
        _dateFilter = result;
        _applyFilter();
      });
    }
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
            '${t.items.isNotEmpty ? 'الأصناف: ${t.items}\n' : ''}'
            'التاريخ: ${_formatDateTime(t.createdAt)}',
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
            content: Text('تم حذف العملية'),
            backgroundColor: Colors.red,
          ),
        );
      }
      _load();
    }
  }

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
            'سيتم حذف الحساب "${widget.customer.name}" وكل معاملاته (${_allTx.length} عملية).\n\n'
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
            content: Text('تم حذف الحساب'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _exportStatement() async {
    final f = await ExportService.exportCustomerStatement(widget.customer.id!);
    await ExportService.shareFile(f, text: 'كشف حساب ${widget.customer.name}');
  }

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
    final theme = Theme.of(context);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.customer.name),
          actions: [
            IconButton(
              icon: Icon(
                _dateFilter.type == DateFilterType.all
                    ? Icons.filter_alt_outlined
                    : Icons.filter_alt,
                color: _dateFilter.type == DateFilterType.all
                    ? null
                    : theme.colorScheme.primary,
              ),
              tooltip: 'فلترة: ${_dateFilter.label}',
              onPressed: _showDateFilter,
            ),
            IconButton(
              icon: const Icon(Icons.table_chart),
              tooltip: 'تصدير كشف الحساب',
              onPressed: _exportStatement,
            ),
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
              color: _balance > 0
                  ? theme.colorScheme.errorContainer
                  : theme.colorScheme.primaryContainer,
              child: Column(
                children: [
                  Text('الرصيد المتبقي',
                      style: TextStyle(
                          color: theme.colorScheme.onPrimaryContainer)),
                  Text(
                    '${_balance.toStringAsFixed(0)} ريال',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: _balance > 0
                          ? theme.colorScheme.error
                          : theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),

            // شريط الفلتر النشط
            if (_dateFilter.type != DateFilterType.all)
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                color: theme.colorScheme.primary.withOpacity(0.1),
                child: Row(
                  children: [
                    Icon(Icons.filter_alt,
                        size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: 6),
                    Text('فلتر: ${_dateFilter.label}',
                        style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.bold)),
                    const Spacer(),
                    Text('${_tx.length} عملية',
                        style: const TextStyle(fontSize: 12)),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        setState(() {
                          _dateFilter = DateFilter();
                          _applyFilter();
                        });
                      },
                    ),
                  ],
                ),
              ),

            Expanded(
              child: _tx.isEmpty
                  ? const Center(child: Text('لا توجد عمليات في هذا النطاق'))
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
                                : (isDebt
                                    ? theme.colorScheme.error
                                    : theme.colorScheme.primary),
                          ),
                          title: Text(
                              '${t.amount.toStringAsFixed(0)} ${t.currency}'),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (t.items.isNotEmpty)
                                Text(t.items,
                                    style: const TextStyle(fontSize: 13)),
                              const SizedBox(height: 2),
                              Text(
                                _formatDateTime(t.createdAt),
                                style: TextStyle(
                                    fontSize: 11,
                                    color: theme.colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ),
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
                  style: FilledButton.styleFrom(
                      backgroundColor: theme.colorScheme.error),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _addTransaction('payment'),
                  icon: const Icon(Icons.payments),
                  label: const Text('سداد'),
                  style: FilledButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary),
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
