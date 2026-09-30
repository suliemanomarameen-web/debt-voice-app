import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../db/database_helper.dart';
import '../models/customer.dart';
import '../models/transaction.dart';

class BackupResult {
  final bool success;
  final String message;
  final String? filePath;
  final int customersCount;
  final int transactionsCount;

  BackupResult({
    required this.success,
    required this.message,
    this.filePath,
    this.customersCount = 0,
    this.transactionsCount = 0,
  });
}

class RestoreResult {
  final bool success;
  final String message;
  final int customersAdded;
  final int transactionsAdded;

  RestoreResult({
    required this.success,
    required this.message,
    this.customersAdded = 0,
    this.transactionsAdded = 0,
  });
}

class BackupService {
  /// مجلد النسخ الاحتياطي
  static Future<Directory> _getBackupDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/debt_book_backups');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// إنشاء نسخة احتياطية محلية
  static Future<BackupResult> createBackup() async {
    try {
      final db = DatabaseHelper.instance.database;
      final dbi = await db;

      // قراءة كل البيانات
      final customersRaw = await dbi.query('customers');
      final transactionsRaw = await dbi.query('transactions');

      final data = {
        'app': 'debt_voice_app',
        'version': 1,
        'created_at': DateTime.now().toIso8601String(),
        'customers': customersRaw,
        'transactions': transactionsRaw,
      };

      final jsonStr = jsonEncode(data);

      // اسم الملف
      final now = DateTime.now();
      final stamp =
          '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
      final dir = await _getBackupDir();
      final file = File('${dir.path}/backup_$stamp.json');
      await file.writeAsString(jsonStr);

      return BackupResult(
        success: true,
        message: 'تم إنشاء النسخة بنجاح',
        filePath: file.path,
        customersCount: customersRaw.length,
        transactionsCount: transactionsRaw.length,
      );
    } catch (e) {
      debugPrint('Backup error: $e');
      return BackupResult(
        success: false,
        message: 'فشل النسخ: $e',
      );
    }
  }

  /// مشاركة آخر نسخة احتياطية
  static Future<void> shareBackup(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await Share.shareXFiles([XFile(filePath)],
            text: 'نسخة احتياطية من دفتر الديون');
      }
    } catch (e) {
      debugPrint('Share error: $e');
    }
  }

  /// قائمة النسخ المتوفرة
  static Future<List<FileSystemEntity>> listBackups() async {
    try {
      final dir = await _getBackupDir();
      final files = await dir.list().toList();
      files.sort((a, b) {
        return b.path.compareTo(a.path);
      });
      return files.where((f) => f.path.endsWith('.json')).toList();
    } catch (e) {
      debugPrint('List backups error: $e');
      return [];
    }
  }

  /// حذف نسخة احتياطية
  static Future<bool> deleteBackup(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
        return true;
      }
    } catch (e) {
      debugPrint('Delete backup error: $e');
    }
    return false;
  }

  /// استعادة من ملف
  /// mode: 'replace' (استبدال كامل) أو 'merge' (دمج)
  static Future<RestoreResult> restoreFromFile(
    String filePath, {
    String mode = 'merge',
  }) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return RestoreResult(
          success: false,
          message: 'الملف غير موجود',
        );
      }

      final content = await file.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;

      if (data['app'] != 'debt_voice_app') {
        return RestoreResult(
          success: false,
          message: 'الملف ليس نسخة احتياطية صالحة',
        );
      }

      final customers = (data['customers'] as List).cast<Map>();
      final transactions = (data['transactions'] as List).cast<Map>();

      final dbi = await DatabaseHelper.instance.database;

      int addedCustomers = 0;
      int addedTransactions = 0;

      if (mode == 'replace') {
        // حذف كل شيء
        await dbi.delete('transactions');
        await dbi.delete('customers');
      }

      // خريطة المعرفات القديمة → الجديدة
      final idMap = <int, int>{};

      // استيراد الزبائن
      for (final c in customers) {
        final oldId = c['id'] as int;
        final name = c['name'] as String;
        final accountType = c['account_type'] as String? ?? 'customer';
        final phone = c['phone'] as String?;
        final note = c['note'] as String?;
        final createdAt = c['created_at'] as String;

        if (mode == 'merge') {
          // ابحث عن زبون بنفس الاسم
          final existing = await dbi.query('customers',
              where: 'name = ?', whereArgs: [name], limit: 1);
          if (existing.isNotEmpty) {
            // موجود → لا نضيفه، نحفظ الـ mapping
            idMap[oldId] = existing.first['id'] as int;
            continue;
          }
        }

        final newId = await dbi.insert('customers', {
          'name': name,
          'phone': phone,
          'account_type': accountType,
          'note': note,
          'created_at': createdAt,
        });
        idMap[oldId] = newId;
        addedCustomers++;
      }

      // استيراد المعاملات
      for (final t in transactions) {
        final oldCustomerId = t['customer_id'] as int;
        final newCustomerId = idMap[oldCustomerId];
        if (newCustomerId == null) continue; // الزبون غير موجود

        if (mode == 'merge') {
          // تحقق من وجود معاملة مطابقة
          final amount = (t['amount'] as num).toDouble();
          final createdAt = t['created_at'] as String;
          final existing = await dbi.query('transactions',
              where: 'customer_id = ? AND amount = ? AND created_at = ?',
              whereArgs: [newCustomerId, amount, createdAt],
              limit: 1);
          if (existing.isNotEmpty) continue;
        }

        await dbi.insert('transactions', {
          'customer_id': newCustomerId,
          'amount': (t['amount'] as num).toDouble(),
          'currency': t['currency'] as String? ?? 'YER',
          'type': t['type'] as String,
          'items': t['items'] as String? ?? '',
          'created_at': t['created_at'] as String,
        });
        addedTransactions++;
      }

      return RestoreResult(
        success: true,
        message: mode == 'replace'
            ? 'تم استبدال البيانات بنجاح'
            : 'تم الدمج بنجاح',
        customersAdded: addedCustomers,
        transactionsAdded: addedTransactions,
      );
    } catch (e) {
      debugPrint('Restore error: $e');
      return RestoreResult(
        success: false,
        message: 'فشل الاستعادة: $e',
      );
    }
  }

  /// فحص ملف قبل الاستعادة
  static Future<Map<String, dynamic>?> peekFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;

      final content = await file.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;

      if (data['app'] != 'debt_voice_app') return null;

      return {
        'created_at': data['created_at'],
        'customers_count': (data['customers'] as List).length,
        'transactions_count': (data['transactions'] as List).length,
      };
    } catch (e) {
      debugPrint('Peek error: $e');
      return null;
    }
  }
}
