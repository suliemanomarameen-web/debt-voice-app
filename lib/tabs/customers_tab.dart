import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import '../models/account_type.dart';
import '../models/customer.dart';
import '../models/log_event.dart';
import '../services/accountant_service.dart';
import '../services/export_service.dart';
import '../services/logger_service.dart';
import '../config/app_settings.dart';
import '../services/settings_service.dart';
import '../screens/add_account_screen.dart';
import '../screens/customer_screen.dart';
import '../screens/voice_screen.dart';
import '../widgets/quick_transaction_dialog.dart';

enum CustomerStatusFilter { active, inactive, all }

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

      if (_filterType != null && c.accountType != _filterType) {
        return false;
      }

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
    final balance = await db.customerBalance(c.id!);

    if (SettingsService.getBool(
          AppSettings.blockDeleteNonzeroBalance,
          defaultValue: true,
        ) &&
        balance != 0) {
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.block, color: Colors.red),
                SizedBox(width: 8),
                Text('لا يمكن الحذف'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'الحساب "${c.name}" رصيده غير صفري.',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('الرصيد الحالي',
                        style: TextStyle(fontSize: 13)),
                    Text(
                      '${balance.toStringAsFixed(0)} ريال',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: balance > 0 ? Colors.red : Colors.green,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  '💡 يجب تصفية الرصيد أولاً قبل الحذف.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('فهمت'),
              ),
            ],
          ),
        ),
      );
      return;
    }

    final txCount = await db.countCustomerTransactions(c.id!);

    if (SettingsService.getBool(
          AppSettings.blockDeleteWithTransactions,
          defaultValue: true,
        ) &&
        txCount > 0) {
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.block, color: Colors.red),
                SizedBox(width: 8),
                Text('لا يمكن الحذف'),
              ],
            ),
            content: Text(
              'الحساب "${c.name}" عليه $txCount عملية.\n\n'
              '💡 يجب حذف كل معاملاته أولاً.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('فهمت'),
              ),
            ],
          ),
        ),
      );
      return;
    }

    final useSoft = SettingsService.getBool(
      AppSettings.softDeleteEnabled,
      defaultValue: true,
    );

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
            useSoft
                ? 'سيتم نقل "${c.name}" وكل معاملاته إلى سلة المحذوفات.\n\n'
                    'يمكن استعادته خلال 30 يومًا.'
                : '⚠️ سيتم حذف "${c.name}" **نهائيًا**!\n\nلا يمكن التراجع.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child: Text(useSoft ? 'حذف' : 'حذف نهائي'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;

    final accountant = await AccountantService.getAccountantName();

    if (useSoft) {
      await db.softDeleteCustomer(c.id!, by: accountant);
    } else {
      await db.hardDeleteCustomer(c.id!);
    }

    // 🆕 تمرير التفاصيل الكاملة
    await LoggerService.logCustomerDeleted(
      c.name,
      phone: c.phone,
      accountType: c.accountType,
      isHard: !useSoft,
      accountant: accountant,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(useSoft
            ? 'تم نقل "${c.name}" إلى سلة المحذوفات'
            : 'تم حذف "${c.name}" نهائيًا'),
        backgroundColor: Colors.red,
      ),
    );

    _refresh();
  }

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

    final accountant = await AccountantService.getAccountantName();

    await db.setCustomerActive(c.id!, !c.isActive, by: accountant);

    await LoggerService.logCustomerStatusChanged(
      name: c.name,
      isActive: !c.isActive,
      accountant: accountant,
    );

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

  Future<void> _addTransactionQuick() async {
    final changed = await QuickTransactionDialog.show(context);
    if (changed == true && mounted) {
      await _refresh();
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

  int get _inactiveCount => _allCustomers.where((c) => !c.isActive).length;

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
                Row(
                  children: [
                    ChoiceChip(
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.check_circle, size: 14),
                          SizedBox(width: 4),
                          Text('النشطون'),
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
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FloatingActionButton(
                heroTag: 'voice_customers',
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const VoiceScreen()),
                  );
                  _refresh();
                },
                backgroundColor: Colors.deepOrange,
                tooltip: 'تسجيل صوتي',
                child: const Icon(Icons.mic, color: Colors.white),
              ),
              const SizedBox(width: 10),
              FloatingActionButton.extended(
                heroTag: 'add_transaction_customers',
                onPressed: _addTransactionQuick,
                icon: const Icon(Icons.add_card),
                label: const Text('عملية'),
                backgroundColor: Colors.teal,
              ),
              const SizedBox(width: 10),
              FloatingActionButton.extended(
                heroTag: 'add_customer_2',
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const AddAccountScreen()),
                  );
                  _refresh();
                },
                icon: const Icon(Icons.person_add),
                label: const Text('حساب'),
              ),
            ],
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
                  return FutureBuilder<double>(
                    future: db.customerBalance(c.id!),
                    builder: (_, snap) {
                      final bal = snap.data ?? 0;
                      final overLimit = c.maxBalance != null &&
                          c.maxBalance! > 0 &&
                          bal >= c.maxBalance!;

                      Color textColor;
                      if (bal <= 0) {
                        textColor = Colors.green.shade700;
                      } else if (c.maxBalance != null && c.maxBalance! > 0) {
                        if (overLimit) {
                          textColor = Colors.red.shade700;
                        } else {
                          final ratio = c.balanceRatio(bal);
                          if (ratio < 0.5) {
                            textColor = Colors.green.shade700;
                          } else if (ratio < 0.8) {
                            textColor = Colors.amber.shade800;
                          } else {
                            textColor = Colors.red.shade700;
                          }
                        }
                      } else {
                        textColor = Colors.red.shade700;
                      }

                      return Card(
                        color: !c.isActive
                            ? theme.colorScheme.surfaceContainerHighest
                                .withOpacity(0.5)
                            : (overLimit
                                ? Colors.red.withOpacity(0.08)
                                : null),
                        child: ListTile(
                          leading: Stack(
                            children: [
                              CircleAvatar(
                                backgroundColor: !c.isActive
                                    ? Colors.grey
                                    : (overLimit
                                        ? Colors.red.shade700
                                        : theme.colorScheme.primary),
                                child: Text(
                                  c.name.characters.first,
                                  style: TextStyle(
                                    color: c.isActive
                                        ? Colors.white
                                        : Colors.white70,
                                  ),
                                ),
                              ),
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
                                          color:
                                              theme.colorScheme.surface,
                                          width: 1.5),
                                    ),
                                    child: const Icon(
                                      Icons.block,
                                      size: 10,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              if (c.isActive && overLimit)
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade700,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                          color:
                                              theme.colorScheme.surface,
                                          width: 1.5),
                                    ),
                                    child: const Icon(
                                      Icons.warning_amber,
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
                              if (c.isActive && overLimit)
                                Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withOpacity(0.15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.warning_amber,
                                    color: Colors.red,
                                    size: 14,
                                  ),
                                ),
                              if (!c.isActive)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                        color: Colors.orange
                                            .withOpacity(0.5),
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
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                AccountType.labelsAr[c.accountType] ?? '',
                                style: TextStyle(
                                  color: c.isActive ? null : Colors.grey,
                                ),
                              ),
                              if (c.maxBalance != null && c.maxBalance! > 0)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    'الحد: ${c.maxBalance!.toStringAsFixed(0)} ريال',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: overLimit
                                          ? Colors.red.shade700
                                          : Colors.grey,
                                      fontWeight: overLimit
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          trailing: Text(
                            '${bal.toStringAsFixed(0)} ريال',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: c.isActive ? textColor : Colors.grey,
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
                          onLongPress: () => _showMenu(c),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
    );
  }
}
