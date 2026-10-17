import 'package:flutter/material.dart';
import '../models/log_event.dart';
import '../db/database_helper.dart';
import '../models/customer.dart';
import '../models/transaction.dart';
import '../services/logger_service.dart';
import '../config/app_settings.dart';
import '../services/settings_service.dart';

class DeletedBinScreen extends StatefulWidget {
  const DeletedBinScreen({super.key});

  @override
  State<DeletedBinScreen> createState() => _DeletedBinScreenState();
}

class _DeletedBinScreenState extends State<DeletedBinScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final db = DatabaseHelper.instance;

  List<Customer> _deletedCustomers = [];
  List<Transaction> _deletedTransactions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);

    final customers = await db.getDeletedCustomers();
    final transactions = await db.getDeletedTransactions();

    if (!mounted) return;
    setState(() {
      _deletedCustomers = customers;
      _deletedTransactions = transactions;
      _loading = false;
    });
  }

  // ═══════════════════════════════════════════════════════════
  // استعادة عميل
  // ═══════════════════════════════════════════════════════════
  Future<void> _restoreCustomer(Customer c) async {
    final confirm = await _confirmRestore(
      title: 'استعادة العميل',
      message: 'سيتم استعادة "${c.name}" وكل معاملاته.',
    );
    if (confirm != true) return;

    final accountant = await _getAccountantName();
    await db.restoreCustomer(c.id!, by: accountant);

    await LoggerService.log(
      action: 'استعادة عميل من السلة',
      description: 'تمت استعادة "${c.name}"',
      category: LogCategory.customer,
      accountant: accountant,
    );

    if (!mounted) return;
    _showSnack('✅ تمت استعادة "${c.name}"', Colors.green);
    _load();
  }

  // ═══════════════════════════════════════════════════════════
  // حذف نهائي لعميل
  // ═══════════════════════════════════════════════════════════
  Future<void> _hardDeleteCustomer(Customer c) async {
    final confirm = await _confirmDelete(
      title: 'حذف نهائي',
      message:
          'سيتم حذف "${c.name}" وكل معاملاته **نهائيًا**. لا يمكن التراجع!',
    );
    if (confirm != true) return;

    final accountant = await _getAccountantName();
    await db.hardDeleteCustomer(c.id!);

    await LoggerService.log(
      action: '🗑️ حذف نهائي لعميل',
      description: 'تم حذف "${c.name}" نهائيًا',
      level: LogLevel.warning,
      category: LogCategory.customer,
      accountant: accountant,
    );

    if (!mounted) return;
    _showSnack('تم الحذف النهائي', Colors.red);
    _load();
  }

  // ═══════════════════════════════════════════════════════════
  // استعادة معاملة
  // ═══════════════════════════════════════════════════════════
  Future<void> _restoreTransaction(Transaction t) async {
    final confirm = await _confirmRestore(
      title: 'استعادة العملية',
      message:
          'سيتم استعادة العملية بمبلغ ${t.amount.toStringAsFixed(0)} ${t.currency}.',
    );
    if (confirm != true) return;

    final accountant = await _getAccountantName();
    await db.restoreTransaction(t.id!, by: accountant);

    await LoggerService.log(
      action: 'استعادة عملية من السلة',
      description:
          'تمت استعادة عملية بمبلغ ${t.amount.toStringAsFixed(0)} ${t.currency}',
      category: LogCategory.transaction,
      accountant: accountant,
    );

    if (!mounted) return;
    _showSnack('✅ تمت استعادة العملية', Colors.green);
    _load();
  }

  // ═══════════════════════════════════════════════════════════
  // حذف نهائي لمعاملة
  // ═══════════════════════════════════════════════════════════
  Future<void> _hardDeleteTransaction(Transaction t) async {
    final confirm = await _confirmDelete(
      title: 'حذف نهائي',
      message:
          'سيتم حذف العملية **نهائيًا**. لا يمكن التراجع!',
    );
    if (confirm != true) return;

    final accountant = await _getAccountantName();
    await db.hardDeleteTransaction(t.id!);

    await LoggerService.log(
      action: '🗑️ حذف نهائي لعملية',
      description:
          'تم حذف عملية بمبلغ ${t.amount.toStringAsFixed(0)} نهائيًا',
      level: LogLevel.warning,
      category: LogCategory.transaction,
      accountant: accountant,
    );

    if (!mounted) return;
    _showSnack('تم الحذف النهائي', Colors.red);
    _load();
  }

  // ═══════════════════════════════════════════════════════════
  // تفريغ السلة
  // ═══════════════════════════════════════════════════════════
  Future<void> _emptyBin() async {
    final total = _deletedCustomers.length + _deletedTransactions.length;
    if (total == 0) return;

    final confirm = await _confirmDelete(
      title: 'تفريغ السلة',
      message:
          'سيتم حذف **كل** العناصر ($total) نهائيًا. لا يمكن التراجع!',
    );
    if (confirm != true) return;

    final accountant = await _getAccountantName();
    int deleted = 0;

    // حذف كل المعاملات نهائيًا
    for (final t in _deletedTransactions) {
      await db.hardDeleteTransaction(t.id!);
      deleted++;
    }

    // حذف كل العملاء نهائيًا
    for (final c in _deletedCustomers) {
      await db.hardDeleteCustomer(c.id!);
      deleted++;
    }

    await LoggerService.log(
      action: '🗑️ تفريغ سلة المحذوفات',
      description: 'تم حذف $deleted عنصر نهائيًا',
      level: LogLevel.warning,
      category: LogCategory.system,
      accountant: accountant,
      needsAck: true,
    );

    if (!mounted) return;
    _showSnack('تم تفريغ السلة ($deleted عنصر)', Colors.red);
    _load();
  }

  // ═══════════════════════════════════════════════════════════
  // أدوات
  // ═══════════════════════════════════════════════════════════
  Future<String?> _getAccountantName() async {
    try {
      final db2 = DatabaseHelper.instance;
      final r = await db2.database.then((d) => d.query('settings',
          where: 'key = ?', whereArgs: ['accountant_name'], limit: 1));
      if (r.isNotEmpty) return r.first['value'] as String?;
    } catch (_) {}
    return null;
  }

  Future<bool?> _confirmRestore({
    required String title,
    required String message,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.restore, color: Colors.green),
              const SizedBox(width: 8),
              Text(title),
            ],
          ),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.green),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('استعادة'),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool?> _confirmDelete({
    required String title,
    required String message,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.warning_amber, color: Colors.red),
              const SizedBox(width: 8),
              Text(title),
            ],
          ),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف نهائي'),
            ),
          ],
        ),
      ),
    );
  }

  void _showSnack(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  String _formatDateTime(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    try {
      final dt = DateTime.parse(iso);
      final y = dt.year;
      final m = dt.month.toString().padLeft(2, '0');
      final d = dt.day.toString().padLeft(2, '0');
      final h = dt.hour.toString().padLeft(2, '0');
      final min = dt.minute.toString().padLeft(2, '0');
      return '$y/$m/$d - $h:$min';
    } catch (_) {
      return iso;
    }
  }

  int _daysRemaining(String? deletedAt) {
    if (deletedAt == null || deletedAt.isEmpty) return 0;
    try {
      final dt = DateTime.parse(deletedAt);
      final retention = SettingsService.getInt(AppSettings.retentionDays,
          defaultValue: 30);
      final expiry = dt.add(Duration(days: retention));
      return expiry.difference(DateTime.now()).inDays;
    } catch (_) {
      return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = _deletedCustomers.length + _deletedTransactions.length;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('سلة المحذوفات'),
          bottom: TabBar(
            controller: _tabController,
            tabs: [
              Tab(
                icon: const Icon(Icons.people, size: 18),
                text: 'عملاء (${_deletedCustomers.length})',
              ),
              Tab(
                icon: const Icon(Icons.receipt_long, size: 18),
                text: 'معاملات (${_deletedTransactions.length})',
              ),
            ],
          ),
          actions: [
            if (total > 0)
              IconButton(
                icon: const Icon(Icons.delete_sweep),
                tooltip: 'تفريغ السلة',
                onPressed: _emptyBin,
              ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  // شريط معلومات
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    color: Colors.orange.withOpacity(0.1),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline,
                            color: Colors.orange, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'العناصر المحذوفة تُحذف نهائيًا بعد '
                            '${SettingsService.getInt(AppSettings.retentionDays, defaultValue: 30)} يوم',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildCustomersTab(theme),
                        _buildTransactionsTab(theme),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // تبويب العملاء
  // ═══════════════════════════════════════════════════════════
  Widget _buildCustomersTab(ThemeData theme) {
    if (_deletedCustomers.isEmpty) {
      return _emptyView('لا يوجد عملاء محذوفون');
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: _deletedCustomers.length,
        itemBuilder: (_, i) {
          final c = _deletedCustomers[i];
          final daysLeft = _daysRemaining(c.deletedAt);

          return Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            color: Colors.red.withOpacity(0.05),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // الاسم
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Colors.grey.shade400,
                        child: Text(
                          c.name.characters.first,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              c.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            if (c.phone != null && c.phone!.isNotEmpty)
                              Text(
                                c.phone!,
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.grey),
                              ),
                          ],
                        ),
                      ),
                      if (daysLeft > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '$daysLeft يوم',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange,
                            ),
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  // من حذف + متى
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.person_off,
                                size: 14, color: Colors.red),
                            const SizedBox(width: 4),
                            Text(
                              'حذفه: ${c.deletedByLabel}',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.red,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(Icons.schedule,
                                size: 14, color: Colors.grey),
                            const SizedBox(width: 4),
                            Text(
                              'وقت الحذف: ${_formatDateTime(c.deletedAt)}',
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.grey),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 10),

                  // الأزرار
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _restoreCustomer(c),
                          icon: const Icon(Icons.restore, size: 16),
                          label: const Text('استعادة'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.green,
                            side: const BorderSide(color: Colors.green),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _hardDeleteCustomer(c),
                          icon: const Icon(Icons.delete_forever, size: 16),
                          label: const Text('حذف نهائي'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // تبويب المعاملات
  // ═══════════════════════════════════════════════════════════
  Widget _buildTransactionsTab(ThemeData theme) {
    if (_deletedTransactions.isEmpty) {
      return _emptyView('لا توجد معاملات محذوفة');
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: _deletedTransactions.length,
        itemBuilder: (_, i) {
          final t = _deletedTransactions[i];
          final daysLeft = _daysRemaining(t.deletedAt);

          return Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            color: Colors.red.withOpacity(0.05),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.grey.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          t.isReturn
                              ? Icons.keyboard_return
                              : (t.isDebt
                                  ? Icons.arrow_upward
                                  : Icons.arrow_downward),
                          size: 18,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${t.displayLabel} — ${t.amount.toStringAsFixed(0)} ${t.currency}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            if (t.code != null && t.code!.isNotEmpty)
                              Text(
                                'الرمز: ${t.code}',
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.blue),
                              ),
                            if (t.items.isNotEmpty)
                              Text(
                                t.items,
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.grey),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                      if (daysLeft > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '$daysLeft يوم',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange,
                            ),
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.person_off,
                                size: 14, color: Colors.red),
                            const SizedBox(width: 4),
                            Text(
                              'حذفه: ${t.deletedByLabel}',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.red,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(Icons.schedule,
                                size: 14, color: Colors.grey),
                            const SizedBox(width: 4),
                            Text(
                              'وقت الحذف: ${_formatDateTime(t.deletedAt)}',
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.grey),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 10),

                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _restoreTransaction(t),
                          icon: const Icon(Icons.restore, size: 16),
                          label: const Text('استعادة'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.green,
                            side: const BorderSide(color: Colors.green),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _hardDeleteTransaction(t),
                          icon: const Icon(Icons.delete_forever, size: 16),
                          label: const Text('حذف نهائي'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _emptyView(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.delete_outline,
            size: 80,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'السلة فارغة',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
