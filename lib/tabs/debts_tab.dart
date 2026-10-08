import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../db/database_helper.dart';
import '../models/customer.dart';
import '../models/transaction.dart';
import '../services/accountant_service.dart';
import '../services/code_service.dart';
import '../services/date_filter.dart';
import '../services/sync_service.dart';
import '../screens/add_account_screen.dart';
import '../screens/customer_screen.dart';
import '../screens/voice_screen.dart';

/// نوع فلتر أعلى المدينين
enum DebtorFilter {
  all,
  today,
  week,
  month,
  year,
  custom,
}

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

  // ===== فلتر أعلى المدينين =====
  DebtorFilter _debtorFilter = DebtorFilter.all;
  DateTime? _debtorFrom;
  DateTime? _debtorTo;
  bool _showTopDebtors = true;

  // ===== حالة المزامنة =====
  SyncStatus _syncStatus = SyncStatus.idle;
  DateTime? _lastSync;
  StreamSubscription<SyncStatus>? _statusSub;
  StreamSubscription<SyncResult>? _resultSub;

  // ===== منع التحديث المتزامن =====
  bool _isRefreshing = false;

  // ===== التنبيه (لمرة واحدة) =====
  final Set<int> _alertedCustomers = {};

  @override
  void initState() {
    super.initState();
    _refresh();
    _loadSyncInfo();

    _statusSub = SyncService.statusStream.listen((s) {
      if (mounted) setState(() => _syncStatus = s);
    });

    _resultSub = SyncService.resultStream.listen(_onSyncResult);
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _resultSub?.cancel();
    super.dispose();
  }

  Future<void> _onSyncResult(SyncResult result) async {
    if (!mounted) return;

    await _refresh();

    if (!mounted) return;

    if (!result.success) return;

    if (result.transactionsAdded > 0 || result.customersAdded > 0) {
      final parts = <String>[];
      if (result.transactionsAdded > 0) {
        parts.add('+${result.transactionsAdded} عملية');
      }
      if (result.customersAdded > 0) {
        parts.add('+${result.customersAdded} حساب');
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.cloud_done, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '☁️ تمت المزامنة: ${parts.join(" و ")}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    }
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

  // ============ نسخ الرمز ============
  Future<void> _copyCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text('تم نسخ الرمز: $code'),
          ],
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ============ الفلتر على أعلى المدينين ============
  DateTime? _getDebtorFrom() {
    final now = DateTime.now();
    switch (_debtorFilter) {
      case DebtorFilter.all:
        return null;
      case DebtorFilter.today:
        return DateTime(now.year, now.month, now.day);
      case DebtorFilter.week:
        return now.subtract(const Duration(days: 7));
      case DebtorFilter.month:
        return DateTime(now.year, now.month - 1, now.day);
      case DebtorFilter.year:
        return DateTime(now.year - 1, now.month, now.day);
      case DebtorFilter.custom:
        return _debtorFrom;
    }
  }

  DateTime? _getDebtorTo() {
    switch (_debtorFilter) {
      case DebtorFilter.today:
        final now = DateTime.now();
        return DateTime(now.year, now.month, now.day, 23, 59, 59);
      case DebtorFilter.custom:
        if (_debtorTo == null) return null;
        return DateTime(
          _debtorTo!.year,
          _debtorTo!.month,
          _debtorTo!.day,
          23,
          59,
          59,
        );
      default:
        return null;
    }
  }

  String _debtorFilterLabel() {
    switch (_debtorFilter) {
      case DebtorFilter.all:
        return 'الكل';
      case DebtorFilter.today:
        return 'اليوم';
      case DebtorFilter.week:
        return 'آخر 7 أيام';
      case DebtorFilter.month:
        return 'آخر 30 يوم';
      case DebtorFilter.year:
        return 'آخر سنة';
      case DebtorFilter.custom:
        if (_debtorFrom != null && _debtorTo != null) {
          return '${_debtorFrom!.year}/${_debtorFrom!.month}/${_debtorFrom!.day} - ${_debtorTo!.year}/${_debtorTo!.month}/${_debtorTo!.day}';
        }
        return 'تاريخ مخصص';
    }
  }

  Future<void> _setDebtorFilter(DebtorFilter f) async {
    if (f == DebtorFilter.custom) {
      final range = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: DateTime(2100),
        initialDateRange: (_debtorFrom != null && _debtorTo != null)
            ? DateTimeRange(start: _debtorFrom!, end: _debtorTo!)
            : null,
        builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: child!,
        ),
      );
      if (range == null) return;
      setState(() {
        _debtorFilter = DebtorFilter.custom;
        _debtorFrom = range.start;
        _debtorTo = range.end;
      });
      await _refresh();
      return;
    }
    setState(() {
      _debtorFilter = f;
      _debtorFrom = null;
      _debtorTo = null;
    });
    await _refresh();
  }

  Future<void> _showDebtorFilterSheet() async {
    showModalBottomSheet(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'فلترة أعلى المدينين',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              _debtorTile(DebtorFilter.all, Icons.all_inclusive, 'الكل'),
              _debtorTile(DebtorFilter.today, Icons.today, 'اليوم'),
              _debtorTile(DebtorFilter.week, Icons.date_range, 'آخر 7 أيام'),
              _debtorTile(
                  DebtorFilter.month, Icons.calendar_month, 'آخر 30 يوم'),
              _debtorTile(
                  DebtorFilter.year, Icons.calendar_today, 'آخر سنة'),
              _debtorTile(DebtorFilter.custom, Icons.event, 'تحديد تاريخ'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _debtorTile(DebtorFilter f, IconData icon, String label) {
    final selected = _debtorFilter == f;
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      trailing: selected ? const Icon(Icons.check, color: Colors.green) : null,
      onTap: () {
        Navigator.pop(context);
        _setDebtorFilter(f);
      },
    );
  }

  // ============ تحديث البيانات المحلي ============
  Future<void> _refresh() async {
    if (_isRefreshing) return;
    _isRefreshing = true;

    try {
      final t = await db.totalDebts();
      final all = await db.allCustomers();

      final debtorFrom = _getDebtorFrom();
      final debtorTo = _getDebtorTo();

      final withBalance = <MapEntry<Customer, double>>[];
      for (final c in all) {
        final tx = await db.customerTransactions(c.id!);

        double balance = 0;
        for (final t in tx) {
          final tDate = DateTime.tryParse(t.createdAt);
          if (tDate == null) continue;

          if (debtorFrom != null && tDate.isBefore(debtorFrom)) continue;
          if (debtorTo != null && tDate.isAfter(debtorTo)) continue;

          if (t.type == 'debt') {
            balance += t.amount;
          } else {
            balance -= t.amount;
          }
        }

        if (balance > 0) withBalance.add(MapEntry(c, balance));
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
    } finally {
      _isRefreshing = false;
    }
  }

  // ============ السحب للتحديث + المزامنة ============
  Future<void> _refreshAndSync() async {
    await _refresh();

    if (SyncService.isSyncAvailable) {
      try {
        await SyncService.manualSync();
      } catch (e) {
        debugPrint('Sync error during refresh: $e');
      }
    }
  }

  // ============ مزامنة يدوية ============
  Future<void> _manualSync() async {
    if (!SyncService.isSyncAvailable) {
      final result = await SyncService.manualSync();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor: result.success ? Colors.green : Colors.red,
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('جاري المزامنة...'),
        duration: Duration(seconds: 1),
      ),
    );

    final result = await SyncService.manualSync();

    if (!mounted) return;

    if (!result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    } else if (result.transactionsAdded == 0 &&
        result.customersAdded == 0 &&
        result.message == 'لا توجد تغييرات') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا توجد تغييرات'),
          duration: Duration(seconds: 1),
        ),
      );
    }

    await _loadSyncInfo();
  }

  // ============================================================
  // ============ نافذة عملية جديدة ============================
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
                      border: Border.all(color: Colors.teal.withOpacity(0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.person, size: 12, color: Colors.teal),
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
                            amount: amt,
                            type: storedType,
                            items: extraText,
                            createdAt: DateTime.now().toIso8601String(),
                          ));

                          if (!dialogContext.mounted) return;
                          Navigator.pop(dialogContext);

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

  // ============ قسم أعلى المدينين ============
  Widget _buildTopDebtorsSection(ThemeData theme) {
    if (_topDebtors.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              IconButton(
                icon: Icon(
                  _showTopDebtors ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                ),
                tooltip: _showTopDebtors ? 'إخفاء' : 'إظهار',
                onPressed: () {
                  setState(() => _showTopDebtors = !_showTopDebtors);
                },
              ),
              Expanded(
                child: Text(
                  'أعلى المدينين (${_topDebtors.length})',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
              TextButton.icon(
                onPressed: _showDebtorFilterSheet,
                icon: Icon(
                  _debtorFilter == DebtorFilter.all
                      ? Icons.filter_alt_outlined
                      : Icons.filter_alt,
                  size: 16,
                  color: _debtorFilter == DebtorFilter.all
                      ? null
                      : theme.colorScheme.primary,
                ),
                label: Text(
                  _debtorFilterLabel(),
                  style: TextStyle(
                    fontSize: 11,
                    color: _debtorFilter == DebtorFilter.all
                        ? null
                        : theme.colorScheme.primary,
                    fontWeight: _debtorFilter == DebtorFilter.all
                        ? FontWeight.normal
                        : FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_showTopDebtors) ...[
          const SizedBox(height: 8),
          ..._topDebtors.map((c) => _buildDebtorCard(c, theme)),
          const SizedBox(height: 20),
        ],
      ],
    );
  }

  Widget _buildDebtorCard(Customer c, ThemeData theme) {
    return FutureBuilder<double>(
      future: _computeFilteredBalance(c.id!),
      builder: (context, snap) {
        final balance = snap.data ?? 0;
        final overLimit = c.isOverLimit(balance);

        // 🆕 تنبيه (لمرة واحدة)
        if (overLimit && !_alertedCustomers.contains(c.id)) {
          _alertedCustomers.add(c.id);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.warning_amber,
                        color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '⚠️ رصيد "${c.name}" تجاوز الحد الأقصى (${c.maxBalance!.toStringAsFixed(0)} ريال)',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 3),
              ),
            );
          });
        }

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          color: overLimit
              ? Colors.red.withOpacity(0.08)
              : null,
          shape: overLimit
              ? RoundedRectangleBorder(
                  side: BorderSide(
                    color: Colors.red.withOpacity(0.5),
                    width: 1,
                  ),
                  borderRadius: BorderRadius.circular(12),
                )
              : null,
          child: ListTile(
            dense: true,
            leading: overLimit
                ? Stack(
                    children: [
                      CircleAvatar(
                        backgroundColor: Colors.red,
                        child: Text(c.name.characters.first,
                            style: const TextStyle(color: Colors.white)),
                      ),
                      Positioned(
                        bottom: -2,
                        right: -2,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.warning_amber,
                            color: Colors.red,
                            size: 14,
                          ),
                        ),
                      ),
                    ],
                  )
                : CircleAvatar(
                    backgroundColor: theme.colorScheme.primary,
                    child: Text(c.name.characters.first,
                        style: const TextStyle(color: Colors.white)),
                  ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    c.name,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: overLimit ? Colors.red : null,
                    ),
                  ),
                ),
                if (overLimit)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: Colors.red.withOpacity(0.5), width: 0.5),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.warning_amber,
                            size: 10, color: Colors.red),
                        const SizedBox(width: 2),
                        Text(
                          'تجاوز الحد',
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: Colors.red,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            subtitle: overLimit && c.maxBalance != null
                ? Text(
                    'الحد الأقصى: ${c.maxBalance!.toStringAsFixed(0)} ريال',
                    style: const TextStyle(fontSize: 11, color: Colors.red),
                  )
                : null,
            trailing: Text(
              '${balance.toStringAsFixed(0)} ريال',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: overLimit ? Colors.red : theme.colorScheme.error,
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
        );
      },
    );
  }

  Future<double> _computeFilteredBalance(int customerId) async {
    final tx = await db.customerTransactions(customerId);
    final from = _getDebtorFrom();
    final to = _getDebtorTo();

    double balance = 0;
    for (final t in tx) {
      final tDate = DateTime.tryParse(t.createdAt);
      if (tDate == null) continue;
      if (from != null && tDate.isBefore(from)) continue;
      if (to != null && tDate.isAfter(to)) continue;

      if (t.type == 'debt') {
        balance += t.amount;
      } else {
        balance -= t.amount;
      }
    }
    return balance;
  }

  // ============ بطاقة عملية (آخر العمليات) ============
  Widget _buildTransactionCard(
      Customer c, Transaction t, ThemeData theme) {
    final isDebt = t.type == 'debt';
    final isReturn = t.items.startsWith('مرتجع');
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            Row(
              children: [
                // 🆕 الأيقونة
                Icon(
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
                const SizedBox(width: 8),

                // 🆕 الاسم (يأخذ المساحة)
                Expanded(
                  child: Text(
                    c.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

                // 🆕 شارات المحاسب والرمز (في أعلى اليسار)
                if (t.accountant != null && t.accountant!.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  _badge(
                    icon: Icons.person,
                    text: t.accountant!,
                    color: Colors.teal,
                  ),
                ],
                if (t.code != null && t.code!.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  _badgeWithCopy(
                    icon: Icons.qr_code,
                    text: t.code!,
                    color: Colors.blue,
                    onCopy: () => _copyCode(t.code!),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const SizedBox(width: 32),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (t.items.isNotEmpty)
                        Text(
                          t.items,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                      const SizedBox(height: 2),
                      Text(
                        _formatDateTime(t.createdAt),
                        style: TextStyle(
                          fontSize: 10,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${t.amount.toStringAsFixed(0)} ${t.currency}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _badge({
    required IconData icon,
    required String text,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.4), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 2),
          Text(
            text,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _badgeWithCopy({
    required IconData icon,
    required String text,
    required Color color,
    required VoidCallback onCopy,
  }) {
    return InkWell(
      onTap: onCopy,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.4), width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 10, color: color),
            const SizedBox(width: 2),
            Text(
              text,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(width: 3),
            Icon(Icons.copy, size: 9, color: color.withOpacity(0.7)),
          ],
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
            onPressed: _refreshAndSync,
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
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
              const SizedBox(width: 10),
              FloatingActionButton.extended(
                heroTag: 'add_transaction',
                onPressed: _addTransactionQuick,
                icon: const Icon(Icons.add_card),
                label: const Text('عملية'),
                backgroundColor: Colors.teal,
              ),
              const SizedBox(width: 10),
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
                label: const Text('حساب'),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshAndSync,
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
            _buildTopDebtorsSection(theme),
            if (_recent.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Text('آخر العمليات',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 8),
              ..._recent.map((entry) =>
                  _buildTransactionCard(entry.key, entry.value, theme)),
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
                        'اضغط "عملية" أو "حساب" للبدء',
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

/// ويدجت صغير لعرض كلمة فوق وأيقونة تحت في SegmentedButton
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
