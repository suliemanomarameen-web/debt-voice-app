import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import '../models/account_type.dart';
import '../models/customer.dart';
import '../screens/add_account_screen.dart';
import '../screens/customer_screen.dart';
import '../screens/voice_screen.dart';

class CustomersTab extends StatefulWidget {
  const CustomersTab({super.key});
  @override
  State<CustomersTab> createState() => _CustomersTabState();
}

class _CustomersTabState extends State<CustomersTab> {
  final db = DatabaseHelper.instance;
  List<Customer> _customers = [];
  String _search = '';
  String? _filterType;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final all = await db.allCustomers();
    if (!mounted) return;
    setState(() {
      _customers = all
          .where((c) =>
              (_filterType == null || c.accountType == _filterType) &&
              (_search.isEmpty ||
                  c.name.toLowerCase().contains(_search.toLowerCase())))
          .toList();
    });
  }

  Future<void> _editCustomer(Customer c) async {
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => AddAccountScreen(existing: c)));
    _refresh();
  }

  Future<void> _deleteCustomer(Customer c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber, color: Colors.red),
              SizedBox(width: 8),
              Text('تأكيد الحذف'),
            ],
          ),
          content: Text('سيتم حذف "${c.name}" وكل معاملاته.\n\nلا يمكن التراجع.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('حذف'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      await db.deleteCustomer(c.id!);
      _refresh();
    }
  }

  void _showMenu(Customer c) {
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
                title: const Text('تعديل الحساب'),
                onTap: () {
                  Navigator.pop(context);
                  _editCustomer(c);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('حذف الحساب',
                    style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  _deleteCustomer(c);
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('الحسابات'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(100),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              children: [
                TextField(
                  decoration: InputDecoration(
                    hintText: 'ابحث بالاسم...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  onChanged: (v) {
                    _search = v;
                    _refresh();
                  },
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    FilterChip(
                      label: const Text('الكل'),
                      selected: _filterType == null,
                      onSelected: (_) {
                        setState(() => _filterType = null);
                        _refresh();
                      },
                    ),
                    const SizedBox(width: 6),
                    ...AccountType.all.map((t) => Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: FilterChip(
                            label: Text(AccountType.labelsAr[t]!),
                            selected: _filterType == t,
                            onSelected: (_) {
                              setState(() => _filterType = t);
                              _refresh();
                            },
                          ),
                        )),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'voice_customers',
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
            heroTag: 'add_customer_2',
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
      body: _customers.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.people_outline, size: 64, color: Colors.grey),
                  SizedBox(height: 12),
                  Text('لا توجد حسابات',
                      style: TextStyle(color: Colors.grey, fontSize: 16)),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: _customers.length,
                itemBuilder: (_, i) {
                  final c = _customers[i];
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Text(c.name.characters.first),
                      ),
                      title: Text(c.name),
                      subtitle: Text(AccountType.labelsAr[c.accountType] ?? ''),
                      trailing: FutureBuilder<double>(
                        future: db.customerBalance(c.id!),
                        builder: (_, snap) {
                          final bal = snap.data ?? 0;
                          return Text(
                            '${bal.toStringAsFixed(0)} ريال',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: bal > 0
                                  ? Colors.red.shade700
                                  : Colors.green.shade700,
                            ),
                          );
                        },
                      ),
                      onTap: () async {
                        await Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => CustomerScreen(customer: c)));
                        _refresh();
                      },
                      onLongPress: () => _showMenu(c),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
