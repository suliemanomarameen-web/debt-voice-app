import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import '../models/account_type.dart';
import '../models/customer.dart';
import '../models/transaction.dart';
import '../services/accountant_service.dart';
import '../services/code_service.dart';
import '../services/export_service.dart';
import '../services/logger_service.dart';
import '../screens/add_account_screen.dart';
import '../screens/customer_screen.dart';
import '../screens/voice_screen.dart';

enum CustomerStatusFilter {
  active,
  inactive,
  all,
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

      // 🆕 تسجيل الحدث
      await LoggerService.logCustomerDeleted(c.name);

      _refresh();
    }
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

    await db.setCustomerActive(c.id!, !c.isActive);

    // 🆕 تسجيل الحدث
    await LoggerService.logCustomerStatusChanged(
      name: c.name,
      isActive: !c.isActive,
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

  // ============================================================
  // ============ نافذة عملية جديدة ============================
  // ============================================================
  Future<void> _addTransactionQuick() async {
    final all = await db.activeCustomers();
    if (all.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا يوجد عملاء نشطون. أضف حساباً أولاً'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final accountant = await AccountantService.getAccountantName();

    String type = 'debt';
    Customer? selectedCustomer;
    final amountCtrl = TextEditingController();
    final itemsCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    final searchCtrl = TextEditingController();
    List<Customer> filtered = List.from(all);
    bool isSaving = false;

    await showDialog(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (ctx, setStateDialog) => AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.add_card, color: Colors.teal),
                const SizedBox(width: 8),
                const Expanded(child: Text('عملية جديدة')),
                if (accountant != null && accountant.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.teal.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                      border:
                          Border.all(color: Colors.teal.withOpacity(0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.person,
                            size: 12, color: Colors.teal),
                        const SizedBox(width: 4),
                        Text(
                          accountant,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.teal,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'نوع العملية:',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 6),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'debt',
                          label: _SegmentLabel('دين', Icons.arrow_upward),
                        ),
                        ButtonSegment(
                          value: 'payment',
                          label: _SegmentLabel('سداد', Icons.payments),
                        ),
                        ButtonSegment(
                          value: 'return',
                          label:
                              _SegmentLabel('مرتجع', Icons.keyboard_return),
                        ),
                      ],
                      selected: {type},
                      onSelectionChanged: (v) {
                        setStateDialog(() => type = v.first);
                      },
                    ),
                    const Divider(height: 24),
                    const Text(
                      'العميل:',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (selectedCustomer != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.teal.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.teal),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.person,
                                color: Colors.teal, size: 18),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                selectedCustomer!.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.teal,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () {
                                setStateDialog(() {
                                  selectedCustomer = null;
                                  searchCtrl.clear();
                                  filtered = List.from(all);
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    if (selectedCustomer == null) ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: searchCtrl,
                        decoration: InputDecoration(
                          hintText: 'ابحث بالاسم...',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                        ),
                        onChanged: (v) {
                          setStateDialog(() {
                            filtered = all
                                .where((c) => c.name.contains(v.trim()))
                                .toList();
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 180),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: filtered.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.all(20),
                                child: Center(
                                  child: Text(
                                    'لا توجد نتائج',
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                ),
                              )
                            : ListView.builder(
                                shrinkWrap: true,
                                itemCount: filtered.length,
                                itemBuilder: (_, i) {
                                  final c = filtered[i];
                                  return ListTile(
                                    dense: true,
                                    leading: CircleAvatar(
                                      radius: 16,
                                      backgroundColor:
                                          Theme.of(ctx).colorScheme.primary,
                                      child: Text(
                                        c.name.characters.first,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                    title: Text(c.name),
                                    subtitle: c.phone != null &&
                                            c.phone!.isNotEmpty
                                        ? Text(
                                            c.phone!,
                                            style:
                                                const TextStyle(fontSize: 11),
                                          )
                                        : null,
                                    onTap: () {
                                      setStateDialog(() {
                                        selectedCustomer = c;
                                      });
                                    },
                                  );
                                },
                              ),
                      ),
                    ],
                    const Divider(height: 24),
                    const Text(
                      'المبلغ:',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: amountCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        hintText: 'أدخل المبلغ',
                        prefixIcon: const Icon(Icons.attach_money),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (type == 'payment') ...[
                      const Text(
                        'البيان:',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: noteCtrl,
                        decoration: InputDecoration(
                          hintText: 'مثال: دفعة شهر أكتوبر...',
                          prefixIcon:
                              const Icon(Icons.description_outlined),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                        ),
                      ),
                    ],
                    if (type != 'payment') ...[
                      const Text(
                        'الأصناف:',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: itemsCtrl,
                        decoration: InputDecoration(
                          hintText: 'مثال: رز، شاي، زبادي',
                          prefixIcon:
                              const Icon(Icons.inventory_2_outlined),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed:
                    isSaving ? null : () => Navigator.pop(dialogContext),
                child: const Text('إلغاء'),
              ),
              FilledButton.icon(
                onPressed: isSaving
                    ? null
                    : () async {
                        if (selectedCustomer == null) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(
                              content: Text('الرجاء اختيار عميل'),
                              backgroundColor: Colors.orange,
                              duration: Duration(seconds: 1),
                            ),
                          );
                          return;
                        }

                        final amt = double.tryParse(amountCtrl.text);
                        if (amt == null || amt <= 0) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(
                              content: Text('الرجاء إدخال مبلغ صحيح'),
                              backgroundColor: Colors.orange,
                              duration: Duration(seconds: 1),
                            ),
                          );
                          return;
                        }

                        setStateDialog(() => isSaving = true);

                        try {
                          final storedType =
                              (type == 'return') ? 'payment' : type;

                          final isDuplicate =
                              await db.transactionExistsRecent(
                            customerId: selectedCustomer!.id!,
                            amount: amt,
                            type: storedType,
                            window: const Duration(seconds: 30),
                          );

                          if (isDuplicate) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    '⚠️ هذه العملية مسجلة بالفعل (خلال آخر 30 ثانية)'),
                                backgroundColor: Colors.orange,
                                duration: Duration(seconds: 2),
                              ),
                            );
                            setStateDialog(() => isSaving = false);
                            return;
                          }

                          String? code;
                          try {
                            code = await CodeService.generateCode(type);
                          } catch (_) {}

                          String extraText;
                          if (type == 'payment') {
                            extraText = noteCtrl.text.trim();
                          } else if (type == 'return') {
                            extraText = itemsCtrl.text.trim().isEmpty
                                ? 'مرتجع'
                                : 'مرتجع: ${itemsCtrl.text.trim()}';
                          } else {
                            extraText = itemsCtrl.text.trim();
                          }

                          await db.insertTransaction(Transaction(
                            customerId: selectedCustomer!.id!,
                            code: code,
                            accountant: accountant,
                            source: 'manual',
                            amount: amt,
                            type: storedType,
                            items: extraText,
                            createdAt: DateTime.now().toIso8601String(),
                          ));

                          // 🆕 تسجيل الحدث
                          final typeLabel = {
                            'debt': 'دين',
                            'payment': 'سداد',
                            'return': 'مرتجع',
                          }[type]!;
                          await LoggerService.logTransactionAdded(
                            typeLabel: typeLabel,
                            customerName: selectedCustomer!.name,
                            amount: amt,
                            currency: 'YER',
                            code: code,
                            accountant: accountant,
                            source: 'manual',
                          );

                          if (!dialogContext.mounted) return;
                          Navigator.pop(dialogContext);

                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                  'تم تسجيل $typeLabel بقيمة ${amt.toStringAsFixed(0)} ريال'),
                              backgroundColor: Colors.green,
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        } finally {
                          if (mounted) {
                            setStateDialog(() => isSaving = false);
                          }
                        }
                      },
                icon: isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check),
                label: Text(isSaving ? 'جاري الحفظ...' : 'حفظ'),
                style: FilledButton.styleFrom(backgroundColor: Colors.teal),
              ),
            ],
          ),
        ),
      ),
    );

    await _refresh();
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

class _SegmentLabel extends StatelessWidget {
  final String text;
  final IconData icon;
  const _SegmentLabel(this.text, this.icon);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text, style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 2),
          Icon(icon, size: 16),
        ],
      ),
    );
  }
}
