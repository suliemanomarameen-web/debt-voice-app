import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import '../models/customer.dart';
import 'add_account_screen.dart';
import 'customer_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final db = DatabaseHelper.instance;
  double _total = 0;
  List<Customer> _customers = [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final t = await db.totalDebts();
    final list = await db.allCustomers();
    if (!mounted) return;
    setState(() { _total = t; _customers = list; });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('دفتر الديون')),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () async {
            await Navigator.push(context,
                MaterialPageRoute(builder: (_) => const AddAccountScreen()));
            _refresh();
          },
          icon: const Icon(Icons.person_add),
          label: const Text('حساب جديد'),
        ),
        body: Column(
          children: [
            Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(16),
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
                          fontSize: 28,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            Expanded(
              child: _customers.isEmpty
                  ? const Center(child: Text('لا توجد حسابات بعد'))
                  : RefreshIndicator(
                      onRefresh: _refresh,
                      child: ListView.builder(
                        itemCount: _customers.length,
                        itemBuilder: (_, i) {
                          final c = _customers[i];
                          return FutureBuilder<double>(
                            future: db.customerBalance(c.id!),
                            builder: (_, snap) {
                              final bal = snap.data ?? 0;
                              return ListTile(
                                leading: CircleAvatar(
                                    child: Text(c.name.characters.first)),
                                title: Text(c.name),
                                trailing: Text('${bal.toStringAsFixed(0)} ريال',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: bal > 0
                                          ? Colors.red.shade700
                                          : Colors.green.shade700,
                                    )),
                                onTap: () async {
                                  await Navigator.push(context,
                                      MaterialPageRoute(
                                          builder: (_) =>
                                              CustomerScreen(customer: c)));
                                  _refresh();
                                },
                              );
                            },
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}