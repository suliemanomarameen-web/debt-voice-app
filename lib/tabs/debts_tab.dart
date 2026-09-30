import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import '../models/customer.dart';
import '../models/transaction.dart';
import '../services/date_filter.dart';
import '../screens/add_account_screen.dart';
import '../screens/customer_screen.dart';
import '../screens/voice_screen.dart';

class DebtsTab extends StatefulWidget {
  const DebtsTab({super.key});
  @override
  State<DebtsTab> createState() => _DebtsTabState();
}

class _DebtsTabState extends State<DebtsTab> {
  final db = DatabaseHelper.instance;
  double _total = 0;
  List<Customer> _topDebtors = [];
  List<MapEntry<Customer, Transaction>> _recent = [];
  DateFilter _dateFilter = DateFilter();

  @override
  void initState() {
    super.initState();
    _refresh();
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

  Future<void> _refresh() async {
    final t = await db.totalDebts();
    final all = await db.allCustomers();

    final withBalance = <MapEntry<Customer, double>>[];
    for (final c in all) {
      final bal = await db.customerBalance(c.id!);
      if (bal > 0) withBalance.add(MapEntry(c, bal));
    }
    withBalance.sort((a, b) => b.value.compareTo(a.value));

    final recent = <MapEntry<Customer, Transaction>>[];
    for (final c in all) {
      final tx = await db.customerTransactions(c.id!);
      for (final t in tx) {
        if (_dateFilter.matches(t.createdAt)) {
          recent.add(MapEntry(c, t));
        }
      }
    }
    recent.sort((a, b) => b.value.createdAt.compareTo(a.value.createdAt));

    if (!mounted) return;
    setState(() {
      _total = t;
      _topDebtors = withBalance.take(5).map((e) => e.key).toList();
      _recent = recent.take(10).toList();
    });
  }

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
            ],
          ),
        ),
      ),
    );
    if (result != null) {
      setState(() => _dateFilter = result);
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('دفتر الديون'),
        actions: [
          IconButton(
            icon: Icon(
              _dateFilter.type == DateFilterType.all
                  ? Icons.filter_alt_outlined
                  : Icons.filter_alt,
            ),
            tooltip: 'فلترة: ${_dateFilter.label}',
            onPressed: _showDateFilter,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'voice_debts',
            onPressed: () async {
              await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const VoiceScreen()));
              _refresh();
            },
            backgroundColor: Colors.deepOrange,
            child: const Icon(Icons.mic, color: Colors.white),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'add_customer',
            onPressed: () async {
              await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const AddAccountScreen()));
              _refresh();
            },
            icon: const Icon(Icons.person_add),
            label: const Text('حساب جديد'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.primary,
                    theme.colorScheme.primary.withOpacity(0.7),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('إجمالي المتبقي',
                      style: TextStyle(color: Colors.white70, fontSize: 14)),
                  const SizedBox(height: 6),
                  Text('${_total.toStringAsFixed(0)} ريال',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),

            // شريط الفلتر النشط
            if (_dateFilter.type != DateFilterType.all) ...[
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
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
                    Text('${_recent.length} عملية'),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        setState(() => _dateFilter = DateFilter());
                        _refresh();
                      },
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 20),
            if (_topDebtors.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Text('أعلى المدينين',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 8),
              ..._topDebtors.map((c) => Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: theme.colorScheme.primary,
                        child: Text(c.name.characters.first,
                            style: const TextStyle(color: Colors.white)),
                      ),
                      title: Text(c.name),
                      trailing: FutureBuilder<double>(
                        future: db.customerBalance(c.id!),
                        builder: (_, snap) => Text(
                          '${(snap.data ?? 0).toStringAsFixed(0)} ريال',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ),
                      onTap: () async {
                        await Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => CustomerScreen(customer: c)));
                        _refresh();
                      },
                    ),
                  )),
              const SizedBox(height: 20),
            ],
            if (_recent.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Text('آخر العمليات',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 8),
              ..._recent.map((entry) {
                final c = entry.key;
                final t = entry.value;
                final isDebt = t.type == 'debt';
                final isReturn = t.items.startsWith('مرتجع');
                return Card(
                  child: ListTile(
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
                    title: Text(c.name),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (t.items.isNotEmpty)
                          Text(t.items,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
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
                    trailing: Text(
                      '${t.amount.toStringAsFixed(0)} ${t.currency}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onTap: () async {
                      await Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => CustomerScreen(customer: c)));
                      _refresh();
                    },
                  ),
                );
              }),
            ],
            if (_topDebtors.isEmpty && _recent.isEmpty)
              Padding(
                padding: const EdgeInsets.all(40),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.inbox, size: 64, color: theme.disabledColor),
                      const SizedBox(height: 12),
                      Text('لا توجد بيانات',
                          style: TextStyle(
                              color: theme.disabledColor, fontSize: 16)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
