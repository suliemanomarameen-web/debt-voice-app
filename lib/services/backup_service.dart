import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../db/database_helper.dart';

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
  static Future<Directory> _getBackupDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/debt_book_backups');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<BackupResult> createBackup() async {
    try {
      final dbi = await DatabaseHelper.instance.database;

      final customersRaw = await dbi.query('customers');
      final transactionsRaw = await dbi.query('transactions');
      final usedCodesRaw = await dbi.query('used_codes');

      final data = {
        'app': 'debt_voice_app',
        'version': 2, // 🆕 v2 — يحفظ used_codes
        'created_at': DateTime.now().toIso8601String(),
        'customers': customersRaw,
        'transactions': transactionsRaw,
        'used_codes': usedCodesRaw, // 🆕
      };

      final jsonStr = jsonEncode(data);

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
      return BackupResult(success: false, message: 'فشل النسخ: $e');
    }
  }

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

  static Future<List<FileSystemEntity>> listBackups() async {
    try {
      final dir = await _getBackupDir();
      final files = await dir.list().toList();
      files.sort((a, b) => b.path.compareTo(a.path));
      return files.where((f) => f.path.endsWith('.json')).toList();
    } catch (e) {
      debugPrint('List backups error: $e');
      return [];
    }
  }

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
  /// mode: 'replace' (استبدال كامل) أو 'merge' (دمج ذكي)
  static Future<RestoreResult> restoreFromFile(
    String filePath, {
    String mode = 'merge',
  }) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return RestoreResult(success: false, message: 'الملف غير موجود');
      }

      final content = await file.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;

      if (data['app'] != 'debt_voice_app') {
        return RestoreResult(
            success: false, message: 'الملف ليس نسخة احتياطية صالحة');
      }

      final customers = (data['customers'] as List).cast<Map>();
      final transactions = (data['transactions'] as List).cast<Map>();
      final usedCodes =
          (data['used_codes'] as List?)?.cast<Map>() ?? <Map>[];

      final dbi = await DatabaseHelper.instance.database;

      int addedCustomers = 0;
      int addedTransactions = 0;

      if (mode == 'replace') {
        await dbi.delete('transactions');
        await dbi.delete('customers');
        await dbi.delete('used_codes');
      }

      final idMap = <int, int>{};

      // ═══════════════════════════════════════════════════
      // 1) العملاء
      // ═══════════════════════════════════════════════════
      for (final c in customers) {
        final oldId = c['id'] as int;
        final cloudId = c['cloud_id'] as String?;
        final name = c['name'] as String? ?? '';
        final createdAt = c['created_at'] as String? ?? '';

        int? existingLocalId;

        if (mode == 'merge') {
          // 🆕 المطابقة بـ cloud_id (أدق طريقة)
          if (cloudId != null && cloudId.isNotEmpty) {
            final byCloud = await dbi.query('customers',
                where: 'cloud_id = ?', whereArgs: [cloudId], limit: 1);
            if (byCloud.isNotEmpty) {
              existingLocalId = byCloud.first['id'] as int;
            }
          }

          // fallback: الاسم + created_at (للنسخ القديمة v1)
          if (existingLocalId == null && createdAt.isNotEmpty) {
            final byNameDate = await dbi.query('customers',
                where: 'name = ? AND created_at = ?',
                whereArgs: [name, createdAt],
                limit: 1);
            if (byNameDate.isNotEmpty) {
              existingLocalId = byNameDate.first['id'] as int;
            }
          }
        }

        if (existingLocalId != null) {
          idMap[oldId] = existingLocalId;
          continue;
        }

        // 🆕 إدخال كامل — يحافظ على cloud_id وكل الحقول
        final newMap = Map<String, dynamic>.from(c);
        newMap.remove('id'); // نترك AUTOINCREMENT يولّد

        // إن لم يكن في النسخة cloud_id → insertCustomerRaw سيولّد واحداً
        if (newMap['cloud_id'] == null ||
            (newMap['cloud_id'] as String?)?.isEmpty == true) {
          newMap.remove('cloud_id');
        }

        final newId = await DatabaseHelper.instance.insertCustomerRaw(newMap);
        idMap[oldId] = newId;
        addedCustomers++;
      }

      // ═══════════════════════════════════════════════════
      // 2) المعاملات
      // ═══════════════════════════════════════════════════
      for (final t in transactions) {
        final oldCustomerId = t['customer_id'] as int;
        final newCustomerId = idMap[oldCustomerId];
        if (newCustomerId == null) continue;

        final cloudId = t['cloud_id'] as String?;
        final amount = (t['amount'] as num).toDouble();
        final createdAt = t['created_at'] as String? ?? '';

        if (mode == 'merge') {
          if (cloudId != null && cloudId.isNotEmpty) {
            final byCloud = await dbi.query('transactions',
                where: 'cloud_id = ?', whereArgs: [cloudId], limit: 1);
            if (byCloud.isNotEmpty) continue;
          } else if (createdAt.isNotEmpty) {
            final byMatch = await dbi.query('transactions',
                where: 'customer_id = ? AND amount = ? AND created_at = ?',
                whereArgs: [newCustomerId, amount, createdAt],
                limit: 1);
            if (byMatch.isNotEmpty) continue;
          }
        }

        // 🆕 إدخال كامل — يحافظ على cloud_id
        final newMap = Map<String, dynamic>.from(t);
        newMap.remove('id');
        newMap['customer_id'] = newCustomerId;

        if (newMap['cloud_id'] == null ||
            (newMap['cloud_id'] as String?)?.isEmpty == true) {
          newMap.remove('cloud_id');
        }

        await DatabaseHelper.instance.insertTransactionRaw(newMap);
        addedTransactions++;
      }

      // ═══════════════════════════════════════════════════
      // 3) 🆕 used_codes — إعادة بناء آمنة
      // ═══════════════════════════════════════════════════
      // insertTransactionRaw يضيف رمز كل عملية تلقائياً،
      // لكن قد تكون هناك رموز محفوظة في النسخة ليست ضمن عمليات
      // (مثلاً من عمليات محذوفة نهائياً سابقاً). نضيفها بأمان.
      for (final uc in usedCodes) {
        try {
          await dbi.insert('used_codes', {
            'code': uc['code'],
            'type': uc['type'],
            'created_at': uc['created_at'],
          });
        } catch (_) {
          // مكرر — تجاهل
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
      return RestoreResult(success: false, message: 'فشل الاستعادة: $e');
    }
  }

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
        'version': data['version'] ?? 1,
        'has_used_codes':
            data['used_codes'] != null && (data['used_codes'] as List).isNotEmpty,
      };
    } catch (e) {
      debugPrint('Peek error: $e');
      return null;
    }
  }
}
