import 'dart:io';
import 'package:flutter/material.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/customer.dart';
import '../models/transaction.dart';
import '../db/database_helper.dart';

class ShareReceiptScreen extends StatefulWidget {
  final Customer customer;
  const ShareReceiptScreen({super.key, required this.customer});
  @override
  State<ShareReceiptScreen> createState() => _ShareReceiptScreenState();
}

class _ShareReceiptScreenState extends State<ShareReceiptScreen> {
  final ScreenshotController _controller = ScreenshotController();
  double _balance = 0;
  List<Transaction> _allTx = [];
  List<Transaction> _tx = [];
  bool _loading = true;
  DateTime? _fromDate;
  DateTime? _toDate;

  // ===== إعدادات العرض =====
  bool _hideCategory = false;
  bool _hideAccountType = false;
  bool _showCodes = true;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _load();
  }

  Future<void> _loadPrefs() async {
    final sp = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _hideCategory = sp.getBool('pdf_hide_category') ?? false;
      _hideAccountType = sp.getBool('pdf_hide_account_type') ?? false;
      _showCodes = sp.getBool('pdf_show_codes') ?? true;
    });
  }

  Future<void> _load() async {
    final db = DatabaseHelper.instance;
    final bal = await db.customerBalance(widget.customer.id!);
    final allTx = await db.customerTransactions(widget.customer.id!);
    if (!mounted) return;
    setState(() {
      _balance = bal;
      _allTx = allTx;
      _applyFilter();
      _loading = false;
    });
  }

  void _applyFilter() {
    List<Transaction> filtered = _allTx;

    if (_fromDate != null) {
      final fromStart = DateTime(
        _fromDate!.year,
        _fromDate!.month,
        _fromDate!.day,
      );
      filtered = filtered.where((t) {
        final d = DateTime.parse(t.createdAt);
        return !d.isBefore(fromStart);
      }).toList();
    }

    if (_toDate != null) {
      final toEnd = DateTime(
        _toDate!.year,
        _toDate!.month,
        _toDate!.day,
        23,
        59,
        59,
      );
      filtered = filtered.where((t) {
        final d = DateTime.parse(t.createdAt);
        return !d.isAfter(toEnd);
      }).toList();
    }

    _tx = filtered;
  }

  // ========== نافذة فلترة التاريخ ==========
  Future<void> _showFilterDialog() async {
    DateTime? tempFrom = _fromDate;
    DateTime? tempTo = _toDate;

    final result = await showDialog<Map<String, DateTime?>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('فلترة بالتاريخ'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.calendar_today),
                  title: Text(
                    tempFrom == null
                        ? 'من تاريخ: الكل'
                        : 'من: ${tempFrom!.year}/${tempFrom!.month}/${tempFrom!.day}',
                  ),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: tempFrom ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      setStateDialog(() => tempFrom = picked);
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.event),
                  title: Text(
                    tempTo == null
                        ? 'إلى تاريخ: الكل'
                        : 'إلى: ${tempTo!.year}/${tempTo!.month}/${tempTo!.day}',
                  ),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: tempTo ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      setStateDialog(() => tempTo = picked);
                    }
                  },
                ),
                if (tempFrom != null || tempTo != null)
                  TextButton.icon(
                    icon: const Icon(Icons.clear, size: 16),
                    label: const Text('مسح الفلتر'),
                    onPressed: () {
                      setStateDialog(() {
                        tempFrom = null;
                        tempTo = null;
                      });
                    },
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, {
                  'from': tempFrom,
                  'to': tempTo,
                }),
                child: const Text('تطبيق'),
              ),
            ],
          ),
        ),
      ),
    );

    if (result == null) return;

    setState(() {
      _fromDate = result['from'];
      _toDate = result['to'];
      _applyFilter();
    });
  }

  Future<void> _shareImage() async {
    try {
      final bytes = await _controller.capture();
      if (bytes == null) return;

      final dir = await getTemporaryDirectory();
      final safeName = widget.customer.name
          .replaceAll(RegExp(r'[^\w\u0600-\u06FF]'), '_');
      final file = File(
        '${dir.path}/receipt_${safeName}_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(bytes);

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'كشف حساب ${widget.customer.name}',
      );
    } catch (e) {
      debugPrint('Share image error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل المشاركة: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('مشاركة كصورة'),
          actions: [
            IconButton(
              icon: Icon(
                (_fromDate == null && _toDate == null)
                    ? Icons.filter_alt_outlined
                    : Icons.filter_alt,
                color: (_fromDate == null && _toDate == null)
                    ? null
                    : theme.colorScheme.primary,
              ),
              tooltip: 'فلترة بالتاريخ',
              onPressed: _loading ? null : _showFilterDialog,
            ),
            IconButton(
              icon: const Icon(Icons.share),
              tooltip: 'مشاركة',
              onPressed: _loading ? null : _shareImage,
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    if (_fromDate != null || _toDate != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.filter_alt,
                                size: 18, color: theme.colorScheme.primary),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'الفترة: ${_fromDate != null ? _formatDate(_fromDate!) : "البداية"} - ${_toDate != null ? _formatDate(_toDate!) : "اليوم"}',
                                style: TextStyle(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () {
                                setState(() {
                                  _fromDate = null;
                                  _toDate = null;
                                  _applyFilter();
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    Screenshot(
                      controller: _controller,
                      child: _buildReceipt(theme, isDark),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _shareImage,
                      icon: const Icon(Icons.share),
                      label: const Text('مشاركة كصورة'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(double.infinity, 50),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'يتم إنشاء صورة PNG جاهزة للإرسال عبر واتساب',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? Colors.grey.shade400
                            : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildReceipt(ThemeData theme, bool isDark) {
    const bgColor = Color(0xFFFAFAFA);
    const cardColor = Colors.white;
    const primaryGreen = Color(0xFF1B6B3A);
    const textDark = Color(0xFF1F2937);
    const textGray = Color(0xFF6B7280);

    double totalDebt = 0;
    double totalPaid = 0;
    for (final t in _tx) {
      if (t.type == 'debt') {
        totalDebt += t.amount;
      } else {
        totalPaid += t.amount;
      }
    }
    final filteredBalance = totalDebt - totalPaid;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ===== Header =====
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: primaryGreen,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                const Text(
                  'كشف حساب',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.customer.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _formatDate(DateTime.now()),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
                if (_fromDate != null || _toDate != null) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'الفترة: ${_fromDate != null ? _formatDate(_fromDate!) : "البداية"} - ${_toDate != null ? _formatDate(_toDate!) : "اليوم"}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ===== معلومات العميل =====
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Column(
              children: [
                _receiptRow('الهاتف',
                    widget.customer.phone ?? 'غير محدد', textDark, textGray),
                if (!_hideCategory)
                  _receiptRow('التصنيف',
                      _categoryLabel(widget.customer.category), textDark, textGray),
                if (!_hideAccountType)
                  _receiptRow('النوع',
                      _accountTypeLabel(widget.customer.accountType),
                      textDark, textGray),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ===== الرصيد =====
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: filteredBalance > 0
                  ? const Color(0xFFFEF2F2)
                  : const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: filteredBalance > 0
                    ? const Color(0xFFFCA5A5)
                    : const Color(0xFF86EFAC),
                width: 2,
              ),
            ),
            child: Column(
              children: [
                Text(
                  (_fromDate != null || _toDate != null)
                      ? 'الرصيد في الفترة'
                      : 'الرصيد المتبقي',
                  style: TextStyle(fontSize: 13, color: textGray),
                ),
                const SizedBox(height: 6),
                Text(
                  '${filteredBalance.toStringAsFixed(0)} ريال',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: filteredBalance > 0
                        ? const Color(0xFFB91C1C)
                        : const Color(0xFF15803D),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ===== الإجماليات =====
          Row(
            children: [
              Expanded(
                child: _miniStatCard('ديون', totalDebt,
                    const Color(0xFFDC2626), cardColor, textDark, textGray),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _miniStatCard('مدفوع', totalPaid,
                    const Color(0xFF16A34A), cardColor, textDark, textGray),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ===== آخر العمليات =====
          if (_tx.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'آخر العمليات (${_tx.length})',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: textDark,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ..._tx.take(10).map((t) {
                    final isDebt = t.type == 'debt';
                    final isReturn = t.items.startsWith('مرتجع');
                    String prefix;
                    if (isReturn) {
                      prefix = 'مرتجع';
                    } else if (isDebt) {
                      prefix = 'دين';
                    } else {
                      prefix = 'سداد';
                    }

                    final items = t.items.isEmpty
                        ? ''
                        : t.items
                            .replaceFirst(RegExp(r'^مرتجع:?\s*'), '')
                            .trim();

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isReturn
                                      ? const Color(0xFFF59E0B)
                                      : (isDebt
                                          ? const Color(0xFFDC2626)
                                          : const Color(0xFF16A34A)),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '$prefix - ${t.amount.toStringAsFixed(0)} ريال',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: textDark,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              if (_showCodes &&
                                  t.code != null &&
                                  t.code!.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 5, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEFF6FF),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: const Color(0xFF93C5FD),
                                      width: 0.5,
                                    ),
                                  ),
                                  child: Text(
                                    t.code!,
                                    style: const TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF2563EB),
                                    ),
                                  ),
                                ),
                              const SizedBox(width: 6),
                              Text(
                                _formatDateShort(t.createdAt),
                                style:
                                    TextStyle(fontSize: 10, color: textGray),
                              ),
                            ],
                          ),
                          if (items.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(
                                  right: 16, top: 2),
                              child: Row(
                                children: [
                                  Icon(
                                    isReturn || isDebt
                                        ? Icons.inventory_2_outlined
                                        : Icons.description_outlined,
                                    size: 12,
                                    color: textGray,
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      items,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: textGray,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),

          // ===== Footer =====
          Center(
            child: Column(
              children: [
                const Text('🌟', style: TextStyle(fontSize: 24)),
                const SizedBox(height: 4),
                Text(
                  'شكراً لتعاملكم معنا',
                  style: TextStyle(fontSize: 13, color: textGray),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _receiptRow(
      String label, String value, Color textColor, Color labelColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(
              '$label:',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: labelColor,
              ),
            ),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(fontSize: 12, color: textColor)),
          ),
        ],
      ),
    );
  }

  Widget _miniStatCard(String label, double value, Color color, Color bg,
      Color textColor, Color labelColor) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: labelColor)),
          const SizedBox(height: 4),
          Text(
            '${value.toStringAsFixed(0)} ريال',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}';
  }

  String _formatDateShort(String iso) {
    try {
      final dt = DateTime.parse(iso);
      return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }

  String _categoryLabel(String cat) {
    return {
      'normal': 'عادي',
      'vip': 'VIP',
      'new': 'جديد',
      'blocked': 'محظور',
      'family': 'عائلة',
    }[cat] ?? 'عادي';
  }

  String _accountTypeLabel(String t) {
    return {
      'customer': 'عميل',
      'supplier': 'مورد',
      'other': 'أخرى',
    }[t] ?? 'عميل';
  }
}
