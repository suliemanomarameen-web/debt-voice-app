import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../models/customer.dart';
import '../models/transaction.dart';
import '../db/database_helper.dart';

class PdfService {
  /// إنشاء كشف حساب PDF (عن طريق تحويل Widget إلى صورة)
  static Future<File> generateStatement(
    Customer customer, {
    DateTime? fromDate,
    DateTime? toDate,
    String fontName = 'Tajawal',
  }) async {
    final db = DatabaseHelper.instance;
    List<Transaction> tx = await db.customerTransactions(customer.id!);

    // فلترة حسب التاريخ
    if (fromDate != null) {
      final fromStart = DateTime(fromDate.year, fromDate.month, fromDate.day);
      tx = tx.where((t) {
        final d = DateTime.parse(t.createdAt);
        return !d.isBefore(fromStart);
      }).toList();
    }
    if (toDate != null) {
      final toEnd = DateTime(
        toDate.year,
        toDate.month,
        toDate.day,
        23,
        59,
        59,
      );
      tx = tx.where((t) {
        final d = DateTime.parse(t.createdAt);
        return !d.isAfter(toEnd);
      }).toList();
    }

    // ========== 1. بناء الـ Widget ==========
    final widget = _buildStatementWidget(
      customer: customer,
      transactions: tx,
      fromDate: fromDate,
      toDate: toDate,
    );

    // ========== 2. تحويل الـ Widget إلى صورة ==========
    final imageBytes = await _widgetToImage(widget);

    // ========== 3. إنشاء PDF ووضع الصورة ==========
    final doc = pw.Document();
    final image = pw.MemoryImage(imageBytes);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        build: (context) => [
          pw.Center(
            child: pw.Image(image, fit: pw.BoxFit.contain),
          ),
        ],
      ),
    );

    // ========== 4. حفظ الملف ==========
    final dir = await getApplicationDocumentsDirectory();
    final safeName =
        customer.name.replaceAll(RegExp(r'[^\w\u0600-\u06FF]'), '_');
    final file = File(
      '${dir.path}/statement_${safeName}_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
    await file.writeAsBytes(await doc.save());

    return file;
  }

  /// تحويل Widget إلى صورة PNG
  static Future<Uint8List> _widgetToImage(Widget widget) async {
    final repaintBoundary = RenderRepaintBoundary();

    // قياس الـ Widget
    final view = ui.PlatformDispatcher.instance.views.first;
    final renderView = RenderView(
      view: view,
      child: RenderPositionedBox(
        alignment: Alignment.topCenter,
        child: repaintBoundary,
      ),
      configuration: ViewConfiguration(
        logicalConstraints: BoxConstraints(
          maxWidth: view.physicalSize.width / view.devicePixelRatio,
          maxHeight: view.physicalSize.height / view.devicePixelRatio,
        ),
        devicePixelRatio: view.devicePixelRatio,
      ),
    );

    final pipelineOwner = PipelineOwner();
    final buildOwner = BuildOwner(focusManager: FocusManager());

    pipelineOwner.rootNode = renderView;
    renderView.prepareInitialFrame();

    final rootElement = RenderObjectToWidgetAdapter<RenderBox>(
      container: repaintBoundary,
      child: widget,
    ).attachToRenderTree(buildOwner);

    buildOwner.buildScope(rootElement);
    buildOwner.finalizeTree();

    pipelineOwner.flushLayout();
    pipelineOwner.flushCompositingBits();
    pipelineOwner.flushPaint();

    // التقاط الصورة بدقة عالية
    final image = await repaintBoundary.toImage(pixelRatio: 3.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  /// بناء الإيصال كـ Widget (نفس تصميم share_receipt_screen)
  static Widget _buildStatementWidget({
    required Customer customer,
    required List<Transaction> transactions,
    DateTime? fromDate,
    DateTime? toDate,
  }) {
    const bgColor = Color(0xFFFAFAFA);
    const cardColor = Colors.white;
    const primaryGreen = Color(0xFF1B6B3A);
    const textDark = Color(0xFF1F2937);
    const textGray = Color(0xFF6B7280);

    double totalDebt = 0;
    double totalPaid = 0;
    for (final t in transactions) {
      if (t.type == 'debt') {
        totalDebt += t.amount;
      } else {
        totalPaid += t.amount;
      }
    }
    final balance = totalDebt - totalPaid;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        width: 800,
        padding: const EdgeInsets.all(20),
        color: bgColor,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
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
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    customer.name,
                    style: const TextStyle(color: Colors.white, fontSize: 18),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _formatDate(DateTime.now()),
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  if (fromDate != null || toDate != null) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'الفترة: ${fromDate != null ? _formatDate(fromDate) : "البداية"} - ${toDate != null ? _formatDate(toDate) : "اليوم"}',
                        style: const TextStyle(color: Colors.white, fontSize: 11),
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
                  _row('الاسم', customer.name, textDark, textGray),
                  if (customer.phone != null && customer.phone!.isNotEmpty)
                    _row('الهاتف', customer.phone!, textDark, textGray),
                  _row('التصنيف', _categoryLabel(customer.category), textDark,
                      textGray),
                  _row('النوع',
                      _accountTypeLabel(customer.accountType), textDark, textGray),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ===== الرصيد =====
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: balance > 0
                    ? const Color(0xFFFEF2F2)
                    : const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: balance > 0
                      ? const Color(0xFFFCA5A5)
                      : const Color(0xFF86EFAC),
                  width: 2,
                ),
              ),
              child: Column(
                children: [
                  Text('الرصيد المتبقي',
                      style: TextStyle(fontSize: 13, color: textGray)),
                  const SizedBox(height: 6),
                  Text(
                    '${balance.toStringAsFixed(0)} ريال',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: balance > 0
                          ? const Color(0xFFB91C1C)
                          : const Color(0xFF15803D),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ===== إجماليات =====
            Row(
              children: [
                Expanded(
                  child: _miniStatCard('ديون', totalDebt,
                      const Color(0xFFDC2626), textDark, textGray),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _miniStatCard('مدفوع', totalPaid,
                      const Color(0xFF16A34A), textDark, textGray),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ===== جدول المعاملات =====
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
                    'سجل المعاملات (${transactions.length})',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: textDark,
                    ),
                  ),
                  const SizedBox(height: 10),
                  // رأس الجدول
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 8),
                    decoration: BoxDecoration(
                      color: primaryGreen,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: Text('التاريخ',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12)),
                        ),
                        Expanded(
                          flex: 1,
                          child: Text('النوع',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12)),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text('المبلغ',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12)),
                        ),
                        Expanded(
                          flex: 4,
                          child: Text('الأصناف',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
                  // صفوف البيانات
                  ...transactions.asMap().entries.map((entry) {
                    final i = entry.key;
                    final t = entry.value;
                    final isDebt = t.type == 'debt';
                    final isReturn = t.items.startsWith('مرتجع');

                    String typeLabel;
                    if (isReturn) {
                      typeLabel = 'مرتجع';
                    } else if (isDebt) {
                      typeLabel = 'دين';
                    } else {
                      typeLabel = 'سداد';
                    }

                    final items = t.items.isEmpty
                        ? '-'
                        : t.items.replaceFirst(RegExp(r'^مرتجع:?\s*'), '');

                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 8),
                      decoration: BoxDecoration(
                        color: i % 2 == 0
                            ? const Color(0xFFF9FAFB)
                            : Colors.white,
                        border: const Border(
                          bottom: BorderSide(
                            color: Color(0xFFE5E7EB),
                            width: 0.5,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: Text(
                              _formatDateShort(t.createdAt),
                              style: TextStyle(fontSize: 11, color: textDark),
                            ),
                          ),
                          Expanded(
                            flex: 1,
                            child: Text(
                              typeLabel,
                              style: TextStyle(fontSize: 11, color: textDark),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              '${t.amount.toStringAsFixed(0)} ${t.currency}',
                              style: TextStyle(fontSize: 11, color: textDark),
                            ),
                          ),
                          Expanded(
                            flex: 4,
                            child: Text(
                              items,
                              style: TextStyle(fontSize: 11, color: textDark),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
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
      ),
    );
  }

  static Widget _row(
      String label, String value, Color textColor, Color labelColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 80,
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

  static Widget _miniStatCard(
      String label, double value, Color color, Color textColor, Color labelColor) {
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

  /// مشاركة PDF
  static Future<void> share(File file, String customerName) async {
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf')],
      text: 'كشف حساب $customerName',
      subject: 'كشف حساب $customerName',
    );
  }

  // ============ أدوات مساعدة ============
  static String _formatDate(DateTime dt) {
    return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}';
  }

  static String _formatDateShort(String iso) {
    try {
      final dt = DateTime.parse(iso);
      return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }

  static String _categoryLabel(String cat) {
    return {
      'normal': 'عادي',
      'vip': 'VIP',
      'new': 'جديد',
      'blocked': 'محظور',
      'family': 'عائلة',
    }[cat] ?? 'عادي';
  }

  static String _accountTypeLabel(String t) {
    return {
      'customer': 'عميل',
      'supplier': 'مورد',
      'other': 'أخرى',
    }[t] ?? 'عميل';
  }
}
