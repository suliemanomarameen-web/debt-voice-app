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
      final dbi = await DatabaseHelper.instance.database;

      // قراءة كل البيانات
      final customersRaw = await dbi.query('customers');
      final transactionsRaw = await dbi.query('transactions');
      final usedCodesRaw = await dbi.query('used_codes');

      final data = {
        'app': 'debt_voice_app',
        'version': 2,
        'created_at': DateTime.now().toIso8601String(),
        'customers': customersRaw,
        'transactions': transactionsRaw,
        'used_codes': usedCodesRaw, // 🆕
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

  /// 🆕 استعادة من ملف — مع إصلاح مشكلة الرموز
  ///
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

      // ═══════════════════════════════════════════════════════════
      // 🆕 إصلاح: امسح used_codes و log_events القديمة عند replace
      // ═══════════════════════════════════════════════════════════
      if (mode == 'replace') {
        debugPrint('🔄 [Restore] Replace mode - clearing all tables');

        // امسح كل شيء (بما فيها used_codes و log_events)
        await dbi.delete('transactions');
        await dbi.delete('customers');
        await dbi.delete('used_codes'); // 🆕 مهم جداً
        await dbi.delete('log_events'); // 🆕 لمنع تكرار الأحداث
      }

      // خريطة المعرفات القديمة → الجديدة
      final idMap = <int, int>{};

      // ═══════════════════════════════════════════════════════════
      // استيراد الزبائن
      // ═══════════════════════════════════════════════════════════
      for (final c in customers) {
        final oldId = c['id'] as int;
        final name = c['name'] as String;
        final accountType = c['account_type'] as String? ?? 'customer';
        final phone = c['phone'] as String?;
        final note = c['note'] as String?;
        final category = c['category'] as String? ?? 'normal';
        final maxBalance = c['max_balance'];
        final isActive = c['is_active'] ?? 1;
        final createdAt = c['created_at'] as String;
        final cloudId = c['cloud_id'] as String?;
        final createdBy = c['created_by'] as String?;

        if (mode == 'merge') {
          // ابحث عن زبون بنفس الاسم
          final existing = await dbi.query('customers',
              where: 'name = ?', whereArgs: [name], limit: 1);
          if (existing.isNotEmpty) {
            idMap[oldId] = existing.first['id'] as int;
            continue;
          }
        }

        final newId = await dbi.insert('customers', {
          'cloud_id': cloudId,
          'name': name,
          'phone': phone,
          'account_type': accountType,
          'note': note,
          'category': category,
          'max_balance': maxBalance,
          'is_active': isActive,
          'created_by': createdBy,
          'created_at': createdAt,
        });
        idMap[oldId] = newId;
        addedCustomers++;
      }

      // ═══════════════════════════════════════════════════════════
      // استيراد المعاملات
      // ═══════════════════════════════════════════════════════════
      for (final t in transactions) {
        final oldCustomerId = t['customer_id'] as int;
        final newCustomerId = idMap[oldCustomerId];
        if (newCustomerId == null) continue;

        if (mode == 'merge') {
          final amount = (t['amount'] as num).toDouble();
          final createdAt = t['created_at'] as String;
          final existing = await dbi.query('transactions',
              where: 'customer_id = ? AND amount = ? AND created_at = ?',
              whereArgs: [newCustomerId, amount, createdAt],
              limit: 1);
          if (existing.isNotEmpty) continue;
        }

        final cloudId = t['cloud_id'] as String?;

        await dbi.insert('transactions', {
          'cloud_id': cloudId,
          'customer_id': newCustomerId,
          'code': t['code'] as String?,
          'accountant': t['accountant'] as String?,
          'source': t['source'] as String?,
          'amount': (t['amount'] as num).toDouble(),
          'currency': t['currency'] as String? ?? 'YER',
          'type': t['type'] as String,
          'items': t['items'] as String? ?? '',
          'created_at': t['created_at'] as String,
        });

        // 🆕 إعادة إضافة الرمز المستخدم
        final code = t['code'] as String?;
        if (code != null && code.isNotEmpty) {
          try {
            await dbi.insert('used_codes', {
              'code': code,
              'type': t['type'] as String? ?? 'debt',
              'created_at':
                  t['created_at'] as String? ?? DateTime.now().toIso8601String(),
            });
          } catch (e) {
            // الرمز موجود مسبقاً — تجاهل
            debugPrint('⚠️ [Restore] Code exists: $code');
          }
        }

        addedTransactions++;
      }

      // ═══════════════════════════════════════════════════════════
      // 🆕 استيراد الرموز المحفوظة (احتياطي)
      // ═══════════════════════════════════════════════════════════
      final savedCodes = (data['used_codes'] as List?)?.cast<Map>() ?? [];
      for (final uc in savedCodes) {
        final code = uc['code'] as String?;
        if (code == null) continue;
        try {
          await dbi.insert('used_codes', {
            'code': code,
            'type': uc['type'] as String? ?? 'debt',
            'created_at': uc['created_at'] as String? ??
                DateTime.now().toIso8601String(),
          });
        } catch (e) {
          // موجود مسبقاً — تجاهل
        }
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
        'used_codes_count': (data['used_codes'] as List?)?.length ?? 0,
      };
    } catch (e) {
      debugPrint('Peek error: $e');
      return null;
    }
  }
}
