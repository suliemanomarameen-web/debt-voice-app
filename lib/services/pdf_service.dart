import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../models/customer.dart';
import '../models/transaction.dart';
import '../db/database_helper.dart';

class PdfService {
  /// إنشاء كشف حساب PDF
  static Future<File> generateStatement(
    Customer customer, {
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    final db = DatabaseHelper.instance;
    List<Transaction> tx = await db.customerTransactions(customer.id!);

    // فلترة حسب التاريخ
    if (fromDate != null) {
      tx = tx.where((t) {
        final d = DateTime.parse(t.createdAt);
        return d.isAfter(fromDate.subtract(const Duration(days: 1)));
      }).toList();
    }
    if (toDate != null) {
      tx = tx.where((t) {
        final d = DateTime.parse(t.createdAt);
        return d.isBefore(toDate.add(const Duration(days: 1)));
      }).toList();
    }

    // تحميل الخطوط العربية
    final fontRegular = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Cairo-Regular.ttf'),
    );
    final fontBold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Cairo-Bold.ttf'),
    );

    final doc = pw.Document(
      theme: pw.ThemeData.withFont(
        base: fontRegular,
        bold: fontBold,
      ),
    );

    // حساب الإجماليات
    double totalDebt = 0;
    double totalPaid = 0;
    for (final t in tx) {
      if (t.type == 'debt') {
        totalDebt += t.amount;
      } else {
        totalPaid += t.amount;
      }
    }
    final balance = totalDebt - totalPaid;

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        margin: const pw.EdgeInsets.all(30),
        build: (context) => [
          // ========== Header ==========
          pw.Container(
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(
              color: PdfColors.green700,
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'كشف حساب',
                      style: pw.TextStyle(
                        color: PdfColors.white,
                        fontSize: 24,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      customer.name,
                      style: const pw.TextStyle(
                        color: PdfColors.white,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      _formatDate(DateTime.now()),
                      style: const pw.TextStyle(
                        color: PdfColors.white,
                        fontSize: 11,
                      ),
                    ),
                    if (fromDate != null || toDate != null) ...[
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'الفترة: ${fromDate != null ? _formatDate(fromDate) : "البداية"} - ${toDate != null ? _formatDate(toDate) : "اليوم"}',
                        style: const pw.TextStyle(
                          color: PdfColors.white,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          pw.SizedBox(height: 20),

          // ========== معلومات العميل ==========
          pw.Container(
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400),
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _row('الاسم', customer.name),
                if (customer.phone != null && customer.phone!.isNotEmpty)
                  _row('الهاتف', customer.phone!),
                _row('التصنيف', _categoryLabel(customer.category)),
                _row('النوع', _accountTypeLabel(customer.accountType)),
                if (customer.note != null && customer.note!.isNotEmpty)
                  _row('ملاحظة', customer.note!),
              ],
            ),
          ),

          pw.SizedBox(height: 16),

          // ========== الإجماليات ==========
          pw.Row(
            children: [
              pw.Expanded(
                child: _summaryBox(
                  'إجمالي الديون',
                  '${totalDebt.toStringAsFixed(0)} ريال',
                  PdfColors.red700,
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: _summaryBox(
                  'إجمالي المدفوع',
                  '${totalPaid.toStringAsFixed(0)} ريال',
                  PdfColors.green700,
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: _summaryBox(
                  'الرصيد المتبقي',
                  '${balance.toStringAsFixed(0)} ريال',
                  balance > 0 ? PdfColors.orange800 : PdfColors.green700,
                ),
              ),
            ],
          ),

          pw.SizedBox(height: 20),

          // ========== جدول المعاملات ==========
          pw.Text(
            'سجل المعاملات (${tx.length})',
            style: pw.TextStyle(
              fontSize: 15,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 8),

          if (tx.isEmpty)
            pw.Container(
              padding: const pw.EdgeInsets.all(20),
              alignment: pw.Alignment.center,
              child: pw.Text(
                'لا توجد معاملات',
                style: const pw.TextStyle(color: PdfColors.grey600),
              ),
            )
          else
            pw.Table(
              border: pw.TableBorder.all(
                color: PdfColors.grey300,
                width: 0.5,
              ),
              columnWidths: {
                0: const pw.FixedColumnWidth(75),   // التاريخ
                1: const pw.FixedColumnWidth(55),   // النوع
                2: const pw.FixedColumnWidth(75),   // المبلغ
                3: const pw.FlexColumnWidth(3),     // الأصناف
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(
                    color: PdfColors.green700,
                  ),
                  children: [
                    _headerCell('التاريخ'),
                    _headerCell('النوع'),
                    _headerCell('المبلغ'),
                    _headerCell('الأصناف'),
                  ],
                ),
                ...tx.map((t) {
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

                  return pw.TableRow(
                    children: [
                      _dataCell(_formatDateShort(t.createdAt)),
                      _dataCell(typeLabel),
                      _dataCell('${t.amount.toStringAsFixed(0)} ${t.currency}'),
                      _dataCell(items),
                    ],
                  );
                }).toList(),
              ],
            ),

          pw.SizedBox(height: 24),

          // ========== Footer ==========
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Center(
              child: pw.Text(
                'شكراً لتعاملكم معنا',
                style: const pw.TextStyle(
                  fontSize: 12,
                  color: PdfColors.grey700,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    // ========== حفظ الملف ==========
    final dir = await getApplicationDocumentsDirectory();
    final safeName =
        customer.name.replaceAll(RegExp(r'[^\w\u0600-\u06FF]'), '_');
    final file = File(
      '${dir.path}/statement_${safeName}_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
    await file.writeAsBytes(await doc.save());

    return file;
  }

  static Future<void> share(File file, String customerName) async {
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf')],
      text: 'كشف حساب $customerName',
      subject: 'كشف حساب $customerName',
    );
  }

  // ============ أدوات مساعدة ============
  static pw.Widget _headerCell(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Center(
        child: pw.Text(
          text,
          style: pw.TextStyle(
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.white,
            fontSize: 11,
          ),
        ),
      ),
    );
  }

  static pw.Widget _dataCell(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          text,
          style: const pw.TextStyle(fontSize: 10),
        ),
      ),
    );
  }

  static pw.Widget _row(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        children: [
          pw.SizedBox(
            width: 70,
            child: pw.Text(
              '$label:',
              style: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 11,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Text(value, style: const pw.TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }

  static pw.Widget _summaryBox(String label, String value, PdfColor color) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: color, width: 0.5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label,
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

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
