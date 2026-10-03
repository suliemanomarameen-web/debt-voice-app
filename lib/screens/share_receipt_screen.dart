import 'dart:io';
import 'package:flutter/material.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
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
  List<Transaction> _tx = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = DatabaseHelper.instance;
    final bal = await db.customerBalance(widget.customer.id!);
    final tx = await db.customerTransactions(widget.customer.id!);
    if (!mounted) return;
    setState(() {
      _balance = bal;
      _tx = tx.take(10).toList();
      _loading = false;
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

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
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
              ],
            ),
          ),
          const SizedBox(height: 16),

          // معلومات
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
                _receiptRow('التصنيف',
                    _categoryLabel(widget.customer.category), textDark, textGray),
                _receiptRow('النوع',
                    _accountTypeLabel(widget.customer.accountType),
                    textDark, textGray),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // الرصيد
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _balance > 0
                  ? const Color(0xFFFEF2F2)
                  : const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _balance > 0
                    ? const Color(0xFFFCA5A5)
                    : const Color(0xFF86EFAC),
                width: 2,
              ),
            ),
            child: Column(
              children: [
                Text(
                  'الرصيد المتبقي',
                  style: TextStyle(fontSize: 13, color: textGray),
                ),
                const SizedBox(height: 6),
                Text(
                  '${_balance.toStringAsFixed(0)} ريال',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: _balance > 0
                        ? const Color(0xFFB91C1C)
                        : const Color(0xFF15803D),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // إجماليات
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

          // آخر العمليات
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
                  ..._tx.take(5).map((t) {
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
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
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
                              style: TextStyle(fontSize: 12, color: textDark),
                            ),
                          ),
                          Text(
                            _formatDateShort(t.createdAt),
                            style: TextStyle(fontSize: 10, color: textGray),
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

          // Footer
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
            child: Text(value, style: TextStyle(fontSize: 12, color: textColor)),
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
