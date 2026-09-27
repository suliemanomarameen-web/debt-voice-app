import 'dart:io';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../db/database_helper.dart';
import '../models/account_type.dart';

class ExportService {
  /// تصدير كل الحسابات إلى CSV
  static Future<File> exportAllToCsv() async {
    final db = DatabaseHelper.instance;
    final customers = await db.allCustomers();
    final rows = <List<dynamic>>[];

    rows.add(['الاسم', 'النوع', 'الهاتف', 'الرصيد المتبقي', 'العملة', 'ملاحظة']);

    for (final c in customers) {
      final bal = await db.customerBalance(c.id!);
      rows.add([
        c.name,
        AccountType.labelsAr[c.accountType] ?? '',
        c.phone ?? '',
        bal.toStringAsFixed(2),
        'YER',
        c.note ?? '',
      ]);
    }

    final csv = const ListToCsvConverter().convert(rows);
    final dir = await getApplicationDocumentsDirectory();
    final file = File(
      '${dir.path}/debts_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.csv',
    );
    await file.writeAsString('\uFEFF$csv');
    return file;
  }

  /// تصدير كل الحسابات إلى Excel
  static Future<File> exportAllToExcel() async {
    final db = DatabaseHelper.instance;
    final customers = await db.allCustomers();
    final excel = Excel.createExcel();
    final sheet = excel['الحسابات'];

    sheet.appendRow([
      TextCellValue('الاسم'),
      TextCellValue('النوع'),
      TextCellValue('الهاتف'),
      TextCellValue('الرصيد المتبقي'),
      TextCellValue('ملاحظة'),
    ]);

    for (final c in customers) {
      final bal = await db.customerBalance(c.id!);
      sheet.appendRow([
        TextCellValue(c.name),
        TextCellValue(AccountType.labelsAr[c.accountType] ?? ''),
        TextCellValue(c.phone ?? ''),
        DoubleCellValue(bal),
        TextCellValue(c.note ?? ''),
      ]);
    }

    final dir = await getApplicationDocumentsDirectory();
    final file = File(
      '${dir.path}/debts_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.xlsx',
    );
    final bytes = excel.encode();
    if (bytes != null) await file.writeAsBytes(bytes);
    return file;
  }

  /// تصدير كشف حساب زبون
  static Future<File> exportCustomerStatement(int customerId) async {
    final db = DatabaseHelper.instance;
    final customers = await db.allCustomers();
    final customer = customers.firstWhere((c) => c.id == customerId);
    final tx = await db.customerTransactions(customerId);
    final bal = await db.customerBalance(customerId);

    final excel = Excel.createExcel();
    final sheet = excel['كشف حساب'];

    sheet.appendRow([TextCellValue('الاسم'), TextCellValue(customer.name)]);
    sheet.appendRow([TextCellValue('الرصيد'), DoubleCellValue(bal)]);
    sheet.appendRow([]);
    sheet.appendRow([
      TextCellValue('التاريخ'),
      TextCellValue('النوع'),
      TextCellValue('المبلغ'),
      TextCellValue('الأصناف'),
    ]);

    for (final t in tx) {
      sheet.appendRow([
        TextCellValue(t.createdAt.substring(0, 10)),
        TextCellValue(t.type == 'debt' ? 'دين' : 'سداد'),
        DoubleCellValue(t.amount),
        TextCellValue(t.items),
      ]);
    }

    final dir = await getApplicationDocumentsDirectory();
    final safeName = customer.name.replaceAll(RegExp(r'[^\w\u0600-\u06FF]'), '_');
    final file = File('${dir.path}/statement_$safeName.xlsx');
    final bytes = excel.encode();
    if (bytes != null) await file.writeAsBytes(bytes);
    return file;
  }

  static Future<void> shareFile(File file, {String? text}) async {
    await Share.shareXFiles([XFile(file.path)], text: text);
  }
}
