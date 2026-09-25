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
              await Navigator.push(context,
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
                gradient: const LinearGradient(
                  colors: [Color(0xFF1B6B3A), Color(0xFF2E8B57)],
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
                        child: Text(c.name.characters.first),
                      ),
                      title: Text(c.name),
                      trailing: FutureBuilder<double>(
                        future: db.customerBalance(c.id!),
                        builder: (_, snap) => Text(
                          '${(snap.data ?? 0).toStringAsFixed(0)} ريال',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.red.shade700,
                          ),
                        ),
                      ),
                      onTap: () async {
                        await Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    CustomerScreen(customer: c)));
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
                          : (isDebt ? Colors.red : Colors.green),
                    ),
                    title: Text(c.name),
                    subtitle: Text(
                      t.items.isEmpty
                          ? (isDebt ? 'دين' : 'سداد')
                          : t.items,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${t.amount.toStringAsFixed(0)} ${t.currency}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(t.createdAt.substring(5, 10),
                            style: const TextStyle(fontSize: 11)),
                      ],
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
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.inbox, size: 64, color: Colors.grey),
                      SizedBox(height: 12),
                      Text('لا توجد بيانات بعد',
                          style: TextStyle(color: Colors.grey, fontSize: 16)),
                      SizedBox(height: 6),
                      Text('اضغط الزر البرتقالي للتسجيل بالصوت',
                          style: TextStyle(color: Colors.grey, fontSize: 12)),
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
