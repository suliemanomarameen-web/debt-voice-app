import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import '../models/customer.dart';
import '../models/transaction.dart';
import '../screens/customer_screen.dart';

/// نوع فلتر التاريخ
enum TxDateFilter {
  all,
  today,
  week,
  month,
  year,
  custom,
}

class TransactionsTab extends StatefulWidget {
  const TransactionsTab({super.key});
  @override
  State<TransactionsTab> createState() => _TransactionsTabState();
}

class _TransactionsTabState extends State<TransactionsTab> {
  final db = DatabaseHelper.instance;
  final searchCtrl = TextEditingController();

  // ===== البيانات =====
  List<MapEntry<Customer, Transaction>> _allTx = [];
  List<MapEntry<Customer, Transaction>> _filtered = [];
  bool _loading = true;

  // ===== الفلتر =====
  TxDateFilter _dateFilter = TxDateFilter.all;
  DateTime? _customFrom;
  DateTime? _customTo;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    final customers = await db.allCustomers();
    final list = <MapEntry<Customer, Transaction>>[];

    for (final c in customers) {
      final tx = await db.customerTransactions(c.id!);
      for (final t in tx) {
        list.add(MapEntry(c, t));
      }
    }

    list.sort((a, b) => b.value.createdAt.compareTo(a.value.createdAt));

    if (!mounted) return;
    setState(() {
      _allTx = list;
      _loading = false;
      _applyFilters();
    });
  }

  // ============ تطبيق الفلاتر ============
  void _applyFilters() {
    final now = DateTime.now();
    DateTime? from;
    DateTime? to;

    switch (_dateFilter) {
      case TxDateFilter.all:
        break;
      case TxDateFilter.today:
        from = DateTime(now.year, now.month, now.day);
        to = DateTime(now.year, now.month, now.day, 23, 59, 59);
        break;
      case TxDateFilter.week:
        from = now.subtract(const Duration(days: 7));
        break;
      case TxDateFilter.month:
        from = DateTime(now.year, now.month - 1, now.day);
        break;
      case TxDateFilter.year:
        from = DateTime(now.year - 1, now.month, now.day);
        break;
      case TxDateFilter.custom:
        from = _customFrom;
        to = _customTo;
        break;
    }

    final query = _searchQuery.trim().toLowerCase();

    _filtered = _allTx.where((entry) {
      // فلتر التاريخ
      if (from != null || to != null) {
        try {
          final tDate = DateTime.parse(entry.value.createdAt);
          if (from != null && tDate.isBefore(from)) return false;
          if (to != null && tDate.isAfter(to)) return false;
        } catch (_) {}
      }

      // فلتر البحث
      if (query.isNotEmpty) {
        final code = (entry.value.code ?? '').toLowerCase();
        final name = entry.key.name.toLowerCase();
        if (!code.contains(query) && !name.contains(query)) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  void _setDateFilter(TxDateFilter f) {
    if (f == TxDateFilter.custom) {
      _pickCustomDate();
      return;
    }
    setState(() {
      _dateFilter = f;
      _customFrom = null;
      _customTo = null;
      _applyFilters();
    });
  }

  Future<void> _pickCustomDate() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: (_customFrom != null && _customTo != null)
          ? DateTimeRange(start: _customFrom!, end: _customTo!)
          : null,
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child!,
      ),
    );

    if (range == null) return;
    setState(() {
      _dateFilter = TxDateFilter.custom;
      _customFrom = range.start;
      _customTo = DateTime(
        range.end.year,
        range.end.month,
        range.end.day,
        23,
        59,
        59,
      );
      _applyFilters();
    });
  }

  // ============ تنسيقات ============
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

  String _filterLabel() {
    switch (_dateFilter) {
      case TxDateFilter.all:
        return 'الكل';
      case TxDateFilter.today:
        return 'اليوم';
      case TxDateFilter.week:
        return 'آخر 7 أيام';
      case TxDateFilter.month:
        return 'آخر 30 يوم';
      case TxDateFilter.year:
        return 'آخر سنة';
      case TxDateFilter.custom:
        if (_customFrom != null && _customTo != null) {
          return '${_customFrom!.year}/${_customFrom!.month}/${_customFrom!.day} - ${_customTo!.year}/${_customTo!.month}/${_customTo!.day}';
        }
        return 'تاريخ مخصص';
    }
  }

  // ============ نافذة الفلتر ============
  void _showFilterSheet() {
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
                  'فلترة بالتاريخ',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              _filterTile(TxDateFilter.all, Icons.all_inclusive, 'الكل'),
              _filterTile(TxDateFilter.today, Icons.today, 'اليوم'),
              _filterTile(TxDateFilter.week, Icons.date_range, 'آخر 7 أيام'),
              _filterTile(
                  TxDateFilter.month, Icons.calendar_month, 'آخر 30 يوم'),
              _filterTile(
                  TxDateFilter.year, Icons.calendar_today, 'آخر سنة'),
              _filterTile(TxDateFilter.custom, Icons.event, 'تحديد تاريخ'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filterTile(TxDateFilter f, IconData icon, String label) {
    final selected = _dateFilter == f;
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      trailing:
          selected ? const Icon(Icons.check, color: Colors.green) : null,
      onTap: () {
        Navigator.pop(context);
        _setDateFilter(f);
      },
    );
  }

  // ============ الإحصائيات ============
  double get _totalDebt {
    double sum = 0;
    for (final e in _filtered) {
      if (e.value.type == 'debt' && !e.value.items.startsWith('مرتجع')) {
        sum += e.value.amount;
      }
    }
    return sum;
  }

  double get _totalPaid {
    double sum = 0;
    for (final e in _filtered) {
      if (e.value.type == 'payment' && !e.value.items.startsWith('مرتجع')) {
        sum += e.value.amount;
      }
    }
    return sum;
  }

  double get _totalReturn {
    double sum = 0;
    for (final e in _filtered) {
      if (e.value.items.startsWith('مرتجع')) {
        sum += e.value.amount;
      }
    }
    return sum;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('العمليات'),
        actions: [
          IconButton(
            icon: Icon(
              _dateFilter == TxDateFilter.all
                  ? Icons.filter_alt_outlined
                  : Icons.filter_alt,
              color: _dateFilter == TxDateFilter.all
                  ? null
                  : theme.colorScheme.primary,
            ),
            tooltip: 'فلتر: ${_filterLabel()}',
            onPressed: _showFilterSheet,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // ===== شريط البحث =====
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    controller: searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'ابحث برمز العملية أو اسم العميل...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                searchCtrl.clear();
                                setState(() {
                                  _searchQuery = '';
                                  _applyFilters();
                                });
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 14),
                    ),
                    onChanged: (v) {
                      setState(() {
                        _searchQuery = v;
                        _applyFilters();
                      });
                    },
                  ),
                ),

                // ===== شريط الفلتر النشط =====
                if (_dateFilter != TxDateFilter.all)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.filter_alt,
                            size: 18, color: theme.colorScheme.primary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'فلتر: ${_filterLabel()}',
                            style: TextStyle(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        Text(
                          '${_filtered.length} عملية',
                          style: const TextStyle(fontSize: 12),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () {
                            setState(() {
                              _dateFilter = TxDateFilter.all;
                              _customFrom = null;
                              _customTo = null;
                              _applyFilters();
                            });
                          },
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 10),

                // ===== الإحصائيات =====
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: _statCard(
                          'ديون',
                          _totalDebt,
                          Colors.red,
                          isDark,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _statCard(
                          'سداد',
                          _totalPaid,
                          Colors.green,
                          isDark,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _statCard(
                          'مرتجع',
                          _totalReturn,
                          Colors.orange,
                          isDark,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 10),

                // ===== قائمة العمليات =====
                Expanded(
                  child: _filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.inbox,
                                  size: 64,
                                  color: theme.disabledColor),
                              const SizedBox(height: 12),
                              Text(
                                'لا توجد عمليات',
                                style: TextStyle(
                                    color: theme.disabledColor,
                                    fontSize: 16),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(8),
                          itemCount: _filtered.length,
                          itemBuilder: (_, i) {
                            final entry = _filtered[i];
                            final c = entry.key;
                            final t = entry.value;
                            final isDebt = t.type == 'debt';
                            final isReturn = t.items.startsWith('مرتجع');

                            return Card(
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 4),
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
                                    Expanded(
                                      child: Text(
                                        '${t.amount.toStringAsFixed(0)} ${t.currency}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    if (t.code != null && t.code!.isNotEmpty)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color:
                                              Colors.blue.withOpacity(0.15),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          border: Border.all(
                                            color: Colors.blue
                                                .withOpacity(0.4),
                                            width: 0.5,
                                          ),
                                        ),
                                        child: Text(
                                          t.code!,
                                          style: const TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.blue,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                subtitle: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(Icons.person,
                                            size: 12,
                                            color: theme.colorScheme
                                                .onSurfaceVariant),
                                        const SizedBox(width: 4),
                                        Text(
                                          c.name,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: theme.colorScheme
                                                .onSurfaceVariant,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (t.items.isNotEmpty)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(top: 2),
                                        child: Text(
                                          t.items,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style:
                                              const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(
                                        _formatDateTime(t.createdAt),
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: theme.colorScheme
                                              .onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                onTap: () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          CustomerScreen(customer: c),
                                    ),
                                  );
                                  _load();
                                },
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _statCard(
      String label, double value, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 10,
                  color: isDark ? Colors.white70 : Colors.black54)),
          const SizedBox(height: 2),
          Text(
            value.toStringAsFixed(0),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
