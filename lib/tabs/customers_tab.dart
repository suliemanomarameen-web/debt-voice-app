import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import '../models/account_type.dart';
import '../models/customer.dart';
import '../services/export_service.dart';
import '../screens/add_account_screen.dart';
import '../screens/customer_screen.dart';
import '../screens/voice_screen.dart';

/// 🆕 نوع فلتر حالة الحساب
enum CustomerStatusFilter {
  active, // النشطون فقط (افتراضي)
  inactive, // الموقوفون فقط
  all, // الكل
}

class CustomersTab extends StatefulWidget {
  const CustomersTab({super.key});
  @override
  State<CustomersTab> createState() => _CustomersTabState();
}

class _CustomersTabState extends State<CustomersTab> {
  final db = DatabaseHelper.instance;
  List<Customer> _allCustomers = [];
  List<Customer> _filtered = [];
  String _search = '';
  String? _filterType;

  // 🆕 فلتر الحالة
  CustomerStatusFilter _statusFilter = CustomerStatusFilter.active;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final all = await db.allCustomers();
    if (!mounted) return;
    setState(() {
      _allCustomers = all;
      _applyFilters();
    });
  }

  void _applyFilters() {
    _filtered = _allCustomers.where((c) {
      // فلتر الحالة
      switch (_statusFilter) {
        case CustomerStatusFilter.active:
          if (!c.isActive) return false;
          break;
        case CustomerStatusFilter.inactive:
          if (c.isActive) return false;
          break;
        case CustomerStatusFilter.all:
          break;
      }

      // فلتر النوع
      if (_filterType != null && c.accountType != _filterType) {
        return false;
      }

      // فلتر البحث
      if (_search.isNotEmpty &&
          !c.name.toLowerCase().contains(_search.toLowerCase())) {
        return false;
      }

      return true;
    }).toList();
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
          content:
              Text('سيتم حذف "${c.name}" وكل معاملاته.\n\nلا يمكن التراجع.'),
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

  // 🆕 تبديل حالة الحساب
  Future<void> _toggleActive(Customer c) async {
    final willStop = c.isActive;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Row(
            children: [
              Icon(
                willStop ? Icons.block : Icons.check_circle,
                color: willStop ? Colors.orange : Colors.green,
              ),
              const SizedBox(width: 8),
              Text(willStop ? 'إيقاف الحساب' : 'تفعيل الحساب'),
            ],
          ),
          content: Text(
            willStop
                ? 'سيتم إيقاف الحساب "${c.name}".\n\n'
                    '• لن يُظهر في القوائم العادية.\n'
                    '• البيانات محفوظة بالكامل.'
                : 'سيتم تفعيل الحساب "${c.name}" مرة أخرى.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: willStop ? Colors.orange : Colors.green,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(willStop ? 'إيقاف' : 'تفعيل'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    await db.setCustomerActive(c.id!, !c.isActive);
    await _refresh();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(willStop
            ? 'تم إيقاف الحساب "${c.name}"'
            : 'تم تفعيل الحساب "${c.name}"'),
        backgroundColor: willStop ? Colors.orange : Colors.green,
      ),
    );
  }

  Future<void> _exportCustomer(Customer c) async {
    final f = await ExportService.exportCustomerStatement(c.id!);
    await ExportService.shareFile(f, text: 'كشف حساب ${c.name}');
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
              // رأس القائمة
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: c.isActive
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey,
                      child: Text(
                        c.name.characters.first,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          if (!c.isActive)
                            const Text(
                              'موقوف',
                              style: TextStyle(
                                color: Colors.orange,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),

              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('تعديل الحساب'),
                onTap: () {
                  Navigator.pop(context);
                  _editCustomer(c);
                },
              ),
              ListTile(
                leading: const Icon(Icons.table_chart),
                title: const Text('تصدير كشف الحساب (Excel)'),
                onTap: () {
                  Navigator.pop(context);
                  _exportCustomer(c);
                },
              ),

              // 🆕 إيقاف/تفعيل
              ListTile(
                leading: Icon(
                  c.isActive ? Icons.block : Icons.check_circle,
                  color: c.isActive ? Colors.orange : Colors.green,
                ),
                title: Text(
                  c.isActive ? 'إيقاف الحساب' : 'تفعيل الحساب',
                  style: TextStyle(
                    color: c.isActive ? Colors.orange : Colors.green,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _toggleActive(c);
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

  String _statusLabel() {
    switch (_statusFilter) {
      case CustomerStatusFilter.active:
        return 'النشطون';
      case CustomerStatusFilter.inactive:
        return 'الموقوفون';
      case CustomerStatusFilter.all:
        return 'الكل';
    }
  }

  int get _inactiveCount =>
      _allCustomers.where((c) => !c.isActive).length;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('الحسابات'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(140),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              children: [
                // ===== البحث =====
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
                    setState(() => _applyFilters());
                  },
                ),
                const SizedBox(height: 8),

                // ===== فلتر الحالة =====
                Row(
                  children: [
                    // 🆕 فلتر الحالة
                    ChoiceChip(
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.check_circle, size: 14),
                          const SizedBox(width: 4),
                          const Text('النشطون'),
                        ],
                      ),
                      selected: _statusFilter == CustomerStatusFilter.active,
                      onSelected: (_) {
                        setState(() {
                          _statusFilter = CustomerStatusFilter.active;
                          _applyFilters();
                        });
                      },
                    ),
                    const SizedBox(width: 6),
                    // 🆕 الموقوفون
                    ChoiceChip(
                      avatar: _inactiveCount > 0
                          ? CircleAvatar(
                              backgroundColor: Colors.orange,
                              radius: 8,
                              child: Text(
                                '$_inactiveCount',
                                style: const TextStyle(
                                  fontSize: 9,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            )
                          : null,
                      label: const Text('الموقوفون'),
                      selected:
                          _statusFilter == CustomerStatusFilter.inactive,
                      onSelected: (_) {
                        setState(() {
                          _statusFilter = CustomerStatusFilter.inactive;
                          _applyFilters();
                        });
                      },
                    ),
                    const SizedBox(width: 6),
                    // 🆕 الكل
                    ChoiceChip(
                      label: const Text('الكل'),
                      selected: _statusFilter == CustomerStatusFilter.all,
                      onSelected: (_) {
                        setState(() {
                          _statusFilter = CustomerStatusFilter.all;
                          _applyFilters();
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // ===== فلتر النوع =====
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      FilterChip(
                        label: const Text('كل الأنواع'),
                        selected: _filterType == null,
                        onSelected: (_) {
                          setState(() => _filterType = null);
                          _applyFilters();
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
                                _applyFilters();
                              },
                            ),
                          )),
                    ],
                  ),
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
      body: _filtered.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _statusFilter == CustomerStatusFilter.inactive
                        ? Icons.block
                        : Icons.people_outline,
                    size: 64,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _statusFilter == CustomerStatusFilter.inactive
                        ? 'لا توجد حسابات موقوفة'
                        : 'لا توجد حسابات',
                    style: const TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: _filtered.length,
                itemBuilder: (_, i) {
                  final c = _filtered[i];
                  return Card(
                    // 🆕 تمييز الموقوف
                    color: c.isActive
                        ? null
                        : theme.colorScheme.surfaceContainerHighest
                            .withOpacity(0.5),
                    child: ListTile(
                      leading: Stack(
                        children: [
                          CircleAvatar(
                            backgroundColor: c.isActive
                                ? theme.colorScheme.primary
                                : Colors.grey,
                            child: Text(
                              c.name.characters.first,
                              style: TextStyle(
                                color: c.isActive
                                    ? Colors.white
                                    : Colors.white70,
                              ),
                            ),
                          ),
                          // 🆕 شارة الإيقاف
                          if (!c.isActive)
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: BoxDecoration(
                                  color: Colors.orange,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: theme.colorScheme.surface,
                                      width: 1.5),
                                ),
                                child: const Icon(
                                  Icons.block,
                                  size: 10,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                        ],
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              c.name,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: c.isActive ? null : Colors.grey,
                              ),
                            ),
                          ),
                          // 🆕 شارة "موقوف"
                          if (!c.isActive)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                    color: Colors.orange.withOpacity(0.5),
                                    width: 0.5),
                              ),
                              child: const Text(
                                'موقوف',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange,
                                ),
                              ),
                            ),
                        ],
                      ),
                      subtitle: Text(
                        AccountType.labelsAr[c.accountType] ?? '',
                        style: TextStyle(
                          color: c.isActive ? null : Colors.grey,
                        ),
                      ),
                      trailing: FutureBuilder<double>(
                        future: db.customerBalance(c.id!),
                        builder: (_, snap) {
                          final bal = snap.data ?? 0;
                          // 🆕 اللون حسب النسبة
                          Color textColor;
                          if (bal <= 0) {
                            textColor = Colors.green.shade700;
                          } else if (c.maxBalance != null &&
                              c.maxBalance! > 0) {
                            final ratio = c.balanceRatio(bal);
                            if (ratio < 0.5) {
                              textColor = Colors.green.shade700;
                            } else if (ratio < 0.8) {
                              textColor = Colors.amber.shade800;
                            } else {
                              textColor = Colors.red.shade700;
                            }
                          } else {
                            textColor = Colors.red.shade700;
                          }

                          return Text(
                            '${bal.toStringAsFixed(0)} ريال',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: c.isActive
                                  ? textColor
                                  : Colors.grey,
                            ),
                          );
                        },
                      ),
                      onTap: () async {
                        await Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    CustomerScreen(customer: c)));
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
