import 'dart:async';
import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import '../models/customer.dart';
import '../models/transaction.dart';
import '../services/code_service.dart';
import '../services/date_filter.dart';
import '../services/sync_service.dart';
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

  // ===== حالة المزامنة =====
  SyncStatus _syncStatus = SyncStatus.idle;
  DateTime? _lastSync;
  StreamSubscription<SyncStatus>? _statusSub;

  @override
  void initState() {
    super.initState();
    _refresh();
    _loadSyncInfo();
    _statusSub = SyncService.statusStream.listen((s) {
      if (mounted) setState(() => _syncStatus = s);
    });
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    super.dispose();
  }

  Future<void> _loadSyncInfo() async {
    final last = await SyncService.getLastSyncTime();
    if (!mounted) return;
    setState(() => _lastSync = last);
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

  String _fmtRelative(DateTime? dt) {
    if (dt == null) return 'لم تحدث بعد';
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'قبل ${diff.inSeconds} ثانية';
    if (diff.inMinutes < 60) return 'قبل ${diff.inMinutes} دقيقة';
    if (diff.inHours < 24) return 'قبل ${diff.inHours} ساعة';
    if (diff.inDays < 30) return 'قبل ${diff.inDays} يوم';
    return _formatDateTime(dt.toIso8601String());
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

    _loadSyncInfo();
  }

  // ============ مزامنة يدوية ============
  Future<void> _manualSync() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('جاري المزامنة...'),
        duration: Duration(seconds: 1),
      ),
    );

    final result = await SyncService.manualSync();

    if (!mounted) return;

    final bgColor = result.success ? Colors.green : Colors.red;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: bgColor,
        duration: const Duration(seconds: 2),
      ),
    );

    await _loadSyncInfo();
  }

  // ============================================================
  // ============ نافذة عملية جديدة (موحدة) ====================
  // ============================================================
  Future<void> _addTransactionQuick() async {
    final all = await db.allCustomers();
    if (all.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا يوجد عملاء. أضف حساباً أولاً'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // ===== متغيرات النافذة =====
    String type = 'debt';
    Customer? selectedCustomer;
    final amountCtrl = TextEditingController();
    final itemsCtrl = TextEditingController();
    final noteCtrl = TextEditingController(); // للبيان في السداد
    final searchCtrl = TextEditingController();
    List<Customer> filtered = List.from(all);

    await showDialog(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (ctx, setStateDialog) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.add_card, color: Colors.teal),
                SizedBox(width: 8),
                Text('عملية جديدة'),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ===== 1. نوع العملية =====
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
                          label: Text('دين'),
                          icon: Icon(Icons.arrow_upward, size: 16),
                        ),
                        ButtonSegment(
                          value: 'payment',
                          label: Text('سداد'),
                          icon: Icon(Icons.payments, size: 16),
                        ),
                        ButtonSegment(
                          value: 'return',
                          label: Text('مرتجع'),
                          icon: Icon(Icons.keyboard_return, size: 16),
                        ),
                      ],
                      selected: {type},
                      onSelectionChanged: (v) {
                        setStateDialog(() => type = v.first);
                      },
                    ),

                    const Divider(height: 24),

                    // ===== 2. العميل =====
                    const Text(
                      'العميل:',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 6),

                    // عرض العميل المختار
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

                    // حقل البحث
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
                      // قائمة العملاء
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

                    // ===== 3. المبلغ =====
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

                    // ===== 4. الحقل الإضافي حسب النوع =====
                    const SizedBox(height: 16),

                    // إذا "سداد" → البيان
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
                          prefixIcon: const Icon(Icons.description_outlined),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                        ),
                      ),
                    ],

                    // إذا "دين" أو "مرتجع" → الأصناف
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
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('إلغاء'),
              ),
              FilledButton.icon(
                onPressed: () async {
                  // تحقق من العميل
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

                  // تحقق من المبلغ
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

                  // توليد الرمز
                  String? code;
                  try {
                    code = await CodeService.generateCode(type);
                  } catch (_) {
                    code = null;
                  }

                  // تحديد محتوى الحقل الإضافي
                  String extraText;
                  if (type == 'payment') {
                    extraText = noteCtrl.text.trim(); // البيان
                  } else if (type == 'return') {
                    extraText = itemsCtrl.text.trim().isEmpty
                        ? 'مرتجع'
                        : 'مرتجع: ${itemsCtrl.text.trim()}';
                  } else {
                    extraText = itemsCtrl.text.trim();
                  }

                  // حفظ العملية
                  await db.insertTransaction(Transaction(
                    customerId: selectedCustomer!.id!,
                    code: code,
                    amount: amt,
                    type: type == 'return' ? 'payment' : type,
                    items: extraText,
                    createdAt: DateTime.now().toIso8601String(),
                  ));

                  if (!dialogContext.mounted) return;

                  // إغلاق النافذة
                  Navigator.pop(dialogContext);

                  // إشعار النجاح
                  final typeLabel = {
                    'debt': 'دين',
                    'payment': 'سداد',
                    'return': 'مرتجع',
                  }[type]!;

                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          'تم تسجيل $typeLabel بقيمة ${amt.toStringAsFixed(0)} ريال'),
                      backgroundColor: Colors.green,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
                icon: const Icon(Icons.check),
                label: const Text('حفظ'),
                style: FilledButton.styleFrom(backgroundColor: Colors.teal),
              ),
            ],
          ),
        ),
      ),
    );

    // تحديث البيانات
    await _refresh();
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

  // ============ شريط المزامنة ============
  Widget _buildSyncBar(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;

    IconData icon;
    Color color;
    String text;
    bool spinning = false;

    switch (_syncStatus) {
      case SyncStatus.idle:
        icon = Icons.cloud_done;
        color = Colors.green;
        text = _lastSync == null
            ? 'اضغط للمزامنة'
            : 'آخر مزامنة: ${_fmtRelative(_lastSync)}';
        break;
      case SyncStatus.syncing:
        icon = Icons.sync;
        color = Colors.blue;
        text = 'جاري المزامنة...';
        spinning = true;
        break;
      case SyncStatus.uploading:
        icon = Icons.cloud_upload;
        color = Colors.blue;
        text = 'جاري الرفع...';
        spinning = true;
        break;
      case SyncStatus.downloading:
        icon = Icons.cloud_download;
        color = Colors.blue;
        text = 'جاري التنزيل...';
        spinning = true;
        break;
      case SyncStatus.conflict:
        icon = Icons.warning_amber;
        color = Colors.orange;
        text = 'يوجد تعارض - اضغط للمزامنة';
        break;
      case SyncStatus.error:
        icon = Icons.error_outline;
        color = Colors.red;
        text = 'فشل المزامنة - اضغط لإعادة المحاولة';
        break;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isDark ? color.withOpacity(0.15) : color.withOpacity(0.08),
      child: InkWell(
        onTap: (_syncStatus == SyncStatus.syncing ||
                _syncStatus == SyncStatus.uploading ||
                _syncStatus == SyncStatus.downloading)
            ? null
            : _manualSync,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              if (spinning)
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: color,
                  ),
                )
              else
                Icon(icon, color: color, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
              Icon(
                Icons.refresh,
                size: 18,
                color: color.withOpacity(0.6),
              ),
            ],
          ),
        ),
      ),
    );
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
                MaterialPageRoute(builder: (_) => const VoiceScreen()),
              );
              _refresh();
            },
            backgroundColor: Colors.deepOrange,
            tooltip: 'تسجيل صوتي',
            child: const Icon(Icons.mic, color: Colors.white),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FloatingActionButton.extended(
                heroTag: 'add_customer',
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const AddAccountScreen()),
                  );
                  _refresh();
                },
                icon: const Icon(Icons.person_add),
                label: const Text('حساب جديد'),
              ),
              const SizedBox(width: 12),
              FloatingActionButton.extended(
                heroTag: 'add_transaction',
                onPressed: _addTransactionQuick,
                icon: const Icon(Icons.add_card),
                label: const Text('عملية جديدة'),
                backgroundColor: Colors.teal,
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            _buildSyncBar(theme),
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
                    title: Row(
                      children: [
                        Expanded(child: Text(c.name)),
                        if (t.code != null && t.code!.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: Colors.blue.withOpacity(0.4),
                                width: 0.5,
                              ),
                            ),
                            child: Text(
                              t.code!,
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue,
                              ),
                            ),
                          ),
                      ],
                    ),
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
                      const SizedBox(height: 8),
                      const Text(
                        'اضغط "عملية جديدة" أو "حساب جديد" للبدء',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
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
