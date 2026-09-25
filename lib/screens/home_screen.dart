import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import '../models/customer.dart';
import 'add_account_screen.dart';
import 'customer_screen.dart';
import 'voice_screen.dart';
import '../services/overlay_service.dart';

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
    setState(() {
      _total = t;
      _customers = list;
    });
  }

  Future<void> _editCustomer(Customer c) async {
    await Navigator.push(
        context,
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
          content: Text(
              'سيتم حذف "${c.name}" وكل معاملاته.\n\nلا يمكن التراجع.'),
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

  void _showCustomerMenu(Customer c) {
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
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
  title: const Text('دفتر الديون'),
  actions: [
    PopupMenuButton<String>(
      onSelected: (v) async {
        if (v == 'start_overlay') {
          final granted = await OverlayService.requestPermission();
          if (granted == true) {
            await OverlayService.show();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('✅ تم تشغيل الزر العائم'),
                  backgroundColor: Colors.green,
                ),
              );
            }
          }
        } else if (v == 'stop_overlay') {
          await OverlayService.hide();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('تم إيقاف الزر العائم'),
                backgroundColor: Colors.grey,
              ),
            );
          }
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: 'start_overlay',
          child: ListTile(
            leading: Icon(Icons.picture_in_picture_alt),
            title: Text('تشغيل الزر العائم'),
          ),
        ),
        PopupMenuItem(
          value: 'stop_overlay',
          child: ListTile(
            leading: Icon(Icons.close),
            title: Text('إيقاف الزر العائم'),
          ),
        ),
      ],
    ),
  ],
),
        floatingActionButton: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            FloatingActionButton(
              heroTag: 'voice',
              onPressed: () async {
                await Navigator.push(context,
                    MaterialPageRoute(builder: (_) => VoiceScreen()));
                _refresh();
              },
              backgroundColor: Colors.deepOrange,
              child: const Icon(Icons.mic, color: Colors.white),
            ),
            const SizedBox(height: 12),
            FloatingActionButton.extended(
              heroTag: 'add',
              onPressed: () async {
                await Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => AddAccountScreen()));
                _refresh();
              },
              icon: const Icon(Icons.person_add),
              label: const Text('حساب جديد'),
            ),
          ],
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
                                trailing: Text(
                                  '${bal.toStringAsFixed(0)} ريال',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: bal > 0
                                        ? Colors.red.shade700
                                        : Colors.green.shade700,
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
                                onLongPress: () => _showCustomerMenu(c),
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
