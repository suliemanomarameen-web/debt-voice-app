import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import '../models/customer.dart';
import '../models/transaction.dart';
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
      if (tx.isNotEmpty) {
        recent.add(MapEntry(c, tx.first));
      }
    }
    recent.sort((a, b) => b.value.createdAt.compareTo(a.value.createdAt));

    if (!mounted) return;
    setState(() {
      _total = t;
      _topDebtors = withBalance.take(5).map((e) => e.key).toList();
      _recent = recent.take(5).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('دفتر الديون'),
        actions: [
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
                      Text('لا توجد بيانات بعد',
                          style: TextStyle(
                              color: theme.disabledColor, fontSize: 16)),
                      const SizedBox(height: 6),
                      Text('اضغط الزر البرتقالي للتسجيل بالصوت',
                          style: TextStyle(
                              color: theme.disabledColor, fontSize: 12)),
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
