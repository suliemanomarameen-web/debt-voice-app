import 'dart:async';
import 'package:flutter/foundation.dart';
import '../db/database_helper.dart';
import '../models/log_event.dart';
import 'accountant_service.dart';

class LoggerService {
  static final LoggerService _instance = LoggerService._internal();
  factory LoggerService() => _instance;
  LoggerService._internal();

  static const int _maxLogs = 5000;
  static const int _retentionDays = 30;

  static final _eventController = StreamController<LogEvent>.broadcast();
  static Stream<LogEvent> get eventStream => _eventController.stream;

  static final _pendingCountController = StreamController<int>.broadcast();
  static Stream<int> get pendingCountStream => _pendingCountController.stream;

  static const String _keyRetentionDays = 'log_retention_days';

  static Future<void> setRetentionDays(int days) async {
    try {
      final db = await DatabaseHelper.instance.database;
      await db.rawInsert(
        'INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)',
        [_keyRetentionDays, days.toString()],
      );
    } catch (_) {}
  }

  static Future<int> getRetentionDays() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final r = await db.query('settings',
          where: 'key = ?', whereArgs: [_keyRetentionDays], limit: 1);
      if (r.isEmpty) return _retentionDays;
      return int.tryParse(r.first['value'] as String? ?? '30') ?? 30;
    } catch (_) {
      return _retentionDays;
    }
  }

  // ============ 🆕 اسم المصدر بالعربي ============
  static String _sourceLabel(String? source) {
    switch (source) {
      case 'voice':
        return '🎤 التسجيل الصوتي';
      case 'overlay':
        return '🖼️ الزر العائم';
      case 'customer_screen':
        return '👤 شاشة العميل';
      case 'manual':
        return '➕ إضافة يدوية';
      default:
        return '';
    }
  }

  // ============ حفظ حدث ============
  static Future<int> log({
    required String action,
    required String description,
    LogLevel level = LogLevel.info,
    LogCategory category = LogCategory.system,
    String? accountant,
    String? relatedId,
    Map<String, dynamic>? metadata,
    String? audioPath,
  }) async {
    try {
      if (accountant == null) {
        try {
          accountant = await AccountantService.getAccountantName();
        } catch (_) {}
      }

      final event = LogEvent(
        action: action,
        description: description,
        level: level,
        category: category,
        accountant: accountant,
        relatedId: relatedId,
        metadata: LogEvent.encodeMetadata(metadata),
        audioPath: audioPath,
        isAcknowledged:
            !(level == LogLevel.error || level == LogLevel.warning),
        createdAt: DateTime.now().toIso8601String(),
      );

      final db = await DatabaseHelper.instance.database;
      final id = await db.insert('log_events', event.toMap());

      final saved = event.copyWith(id: id);
      if (!_eventController.isClosed) {
        _eventController.add(saved);
      }

      _notifyPendingCount();

      if (id % 50 == 0) {
        unawaited(_autoCleanup());
      }

      return id;
    } catch (e) {
      debugPrint('❌ [Logger] Failed to log: $e');
      return -1;
    }
  }

  // ============ دوال مختصرة ============
  static Future<void> info(
    String action,
    String description, {
    LogCategory category = LogCategory.system,
    String? relatedId,
    Map<String, dynamic>? metadata,
    String? audioPath,
  }) =>
      log(
        action: action,
        description: description,
        level: LogLevel.info,
        category: category,
        relatedId: relatedId,
        metadata: metadata,
        audioPath: audioPath,
      );

  static Future<void> success(
    String action,
    String description, {
    LogCategory category = LogCategory.system,
    String? relatedId,
    Map<String, dynamic>? metadata,
    String? audioPath,
  }) =>
      log(
        action: action,
        description: description,
        level: LogLevel.success,
        category: category,
        relatedId: relatedId,
        metadata: metadata,
        audioPath: audioPath,
      );

  static Future<void> warning(
    String action,
    String description, {
    LogCategory category = LogCategory.system,
    String? relatedId,
    Map<String, dynamic>? metadata,
    String? audioPath,
  }) =>
      log(
        action: action,
        description: description,
        level: LogLevel.warning,
        category: category,
        relatedId: relatedId,
        metadata: metadata,
        audioPath: audioPath,
      );

  static Future<void> logError(
    String action,
    String description, {
    LogCategory category = LogCategory.system,
    String? relatedId,
    Map<String, dynamic>? metadata,
    String? audioPath,
  }) =>
      log(
        action: action,
        description: description,
        level: LogLevel.error,
        category: category,
        relatedId: relatedId,
        metadata: metadata,
        audioPath: audioPath,
      );

  // ============ قراءة ============
  static Future<List<LogEvent>> getLogs({
    LogLevel? level,
    LogCategory? category,
    DateTime? fromDate,
    DateTime? toDate,
    String? searchQuery,
    bool onlyPending = false,
    int limit = 500,
    int offset = 0,
  }) async {
    try {
      final db = await DatabaseHelper.instance.database;
      final where = <String>[];
      final args = <dynamic>[];

      if (level != null) {
        where.add('level = ?');
        args.add(level.name);
      }
      if (category != null) {
        where.add('category = ?');
        args.add(category.name);
      }
      if (fromDate != null) {
        where.add('created_at >= ?');
        args.add(fromDate.toIso8601String());
      }
      if (toDate != null) {
        where.add('created_at <= ?');
        args.add(toDate.toIso8601String());
      }
      if (onlyPending) {
        where.add('is_acknowledged = 0');
        where.add("(level = 'error' OR level = 'warning')");
      }
      if (searchQuery != null && searchQuery.trim().isNotEmpty) {
        where.add('(action LIKE ? OR description LIKE ? OR accountant LIKE ?)');
        final q = '%${searchQuery.trim()}%';
        args.add(q);
        args.add(q);
        args.add(q);
      }

      final r = await db.query(
        'log_events',
        where: where.isEmpty ? null : where.join(' AND '),
        whereArgs: args.isEmpty ? null : args,
        orderBy: 'created_at DESC',
        limit: limit,
        offset: offset,
      );

      return r.map((e) => LogEvent.fromMap(e)).toList();
    } catch (e) {
      debugPrint('❌ [Logger] getLogs error: $e');
      return [];
    }
  }

  static Future<List<LogEvent>> getAllLogs({int limit = 2000}) async {
    return getLogs(limit: limit);
  }

  static Future<int> getPendingCount() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final r = await db.rawQuery('''
        SELECT COUNT(*) AS cnt FROM log_events
        WHERE is_acknowledged = 0
          AND (level = 'error' OR level = 'warning')
      ''');
      return (r.first['cnt'] as int?) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  static Future<Map<String, int>> getPendingCountByCategory() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final r = await db.rawQuery('''
        SELECT category, COUNT(*) AS cnt FROM log_events
        WHERE is_acknowledged = 0
          AND (level = 'error' OR level = 'warning')
        GROUP BY category
      ''');
      final map = <String, int>{};
      for (final row in r) {
        map[row['category'] as String? ?? 'system'] =
            (row['cnt'] as int?) ?? 0;
      }
      return map;
    } catch (_) {
      return {};
    }
  }

  // ============ الاعتراف ============
  static Future<bool> acknowledge(int id) async {
    try {
      final db = await DatabaseHelper.instance.database;
      final r = await db.update(
        'log_events',
        {'is_acknowledged': 1},
        where: 'id = ?',
        whereArgs: [id],
      );
      if (r > 0) {
        _notifyPendingCount();
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  static Future<int> acknowledgeAll() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final r = await db.update(
        'log_events',
        {'is_acknowledged': 1},
        where: 'is_acknowledged = 0',
      );
      _notifyPendingCount();
      return r;
    } catch (_) {
      return 0;
    }
  }

  // ============ إحصائيات ============
  static Future<Map<String, dynamic>> getStats() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final total = await db.rawQuery('SELECT COUNT(*) AS c FROM log_events');
      final errors = await db.rawQuery(
          "SELECT COUNT(*) AS c FROM log_events WHERE level = 'error'");
      final warnings = await db.rawQuery(
          "SELECT COUNT(*) AS c FROM log_events WHERE level = 'warning'");
      final today = await db.rawQuery(
          "SELECT COUNT(*) AS c FROM log_events WHERE created_at >= ?", [
        DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day)
            .toIso8601String()
      ]);
      final pending = await db.rawQuery('''
        SELECT COUNT(*) AS c FROM log_events
        WHERE is_acknowledged = 0
          AND (level = 'error' OR level = 'warning')
      ''');

      return {
        'total': (total.first['c'] as int?) ?? 0,
        'errors': (errors.first['c'] as int?) ?? 0,
        'warnings': (warnings.first['c'] as int?) ?? 0,
        'today': (today.first['c'] as int?) ?? 0,
        'pending': (pending.first['c'] as int?) ?? 0,
      };
    } catch (_) {
      return {'total': 0, 'errors': 0, 'warnings': 0, 'today': 0, 'pending': 0};
    }
  }

  // ============ حذف ============
  static Future<bool> deleteLog(int id) async {
    try {
      final db = await DatabaseHelper.instance.database;
      await db.delete('log_events', where: 'id = ?', whereArgs: [id]);
      _notifyPendingCount();
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> clearAll() async {
    try {
      final db = await DatabaseHelper.instance.database;
      await db.delete('log_events');
      _notifyPendingCount();
    } catch (e) {
      debugPrint('❌ [Logger] clearAll error: $e');
    }
  }

  static Future<int> deleteOlderThan(int days) async {
    try {
      final cutoff =
          DateTime.now().subtract(Duration(days: days)).toIso8601String();
      final db = await DatabaseHelper.instance.database;
      final r = await db.delete('log_events',
          where: 'created_at < ?', whereArgs: [cutoff]);
      _notifyPendingCount();
      return r;
    } catch (_) {
      return 0;
    }
  }

  // ============ تنظيف تلقائي ============
  static Future<void> _autoCleanup() async {
    try {
      final days = await getRetentionDays();
      if (days > 0) {
        await deleteOlderThan(days);
      }

      final db = await DatabaseHelper.instance.database;
      final count = await db.rawQuery('SELECT COUNT(*) AS c FROM log_events');
      final total = (count.first['c'] as int?) ?? 0;

      if (total > _maxLogs) {
        final excess = total - _maxLogs;
        await db.rawQuery('''
          DELETE FROM log_events WHERE id IN (
            SELECT id FROM log_events ORDER BY created_at ASC LIMIT $excess
          )
        ''');
        _notifyPendingCount();
      }
    } catch (e) {
      debugPrint('⚠️ [Logger] autoCleanup error: $e');
    }
  }

  static Future<void> cleanup() async {
    await _autoCleanup();
  }

  static Future<void> _notifyPendingCount() async {
    try {
      final count = await getPendingCount();
      if (!_pendingCountController.isClosed) {
        _pendingCountController.add(count);
      }
    } catch (_) {}
  }

  static Future<void> refreshPendingCount() async {
    await _notifyPendingCount();
  }

  // ============ دوال مختصرة للأحداث ============

  // 🆕 إضافة عملية (مع عرض المصدر)
  static Future<void> logTransactionAdded({
    required String typeLabel,
    required String customerName,
    required double amount,
    required String currency,
    String? code,
    String? accountant,
    String? source,
    String? relatedId,
    String? audioPath,
  }) {
    // 🆕 بناء وصف يظهر فيه المصدر
    final sourceText = _sourceLabel(source);
    final sourcePart = sourceText.isNotEmpty ? ' • المصدر: $sourceText' : '';

    return success(
      'إضافة $typeLabel',
      'تم تسجيل $typeLabel بمبلغ ${amount.toStringAsFixed(0)} $currency للعميل "$customerName"$sourcePart',
      category: LogCategory.transaction,
      relatedId: relatedId,
      audioPath: audioPath,
      metadata: {
        'customer': customerName,
        'amount': amount,
        'currency': currency,
        'type': typeLabel,
        'code': code,
        'accountant': accountant,
        'source': source,
      },
    );
  }

  static Future<void> logTransactionDeleted({
    required String customerName,
    required double amount,
    String? code,
  }) =>
      warning(
        'حذف عملية',
        'تم حذف عملية بمبلغ ${amount.toStringAsFixed(0)} للعميل "$customerName"${code != null ? " (رمز: $code)" : ""}',
        category: LogCategory.transaction,
      );

  static Future<void> logCustomerAdded(String name) => success(
        'إضافة عميل',
        'تم إنشاء حساب جديد: "$name"',
        category: LogCategory.customer,
      );

  static Future<void> logCustomerDeleted(String name) => warning(
        'حذف عميل',
        'تم حذف الحساب: "$name"',
        category: LogCategory.customer,
      );

  static Future<void> logCustomerStatusChanged({
    required String name,
    required bool isActive,
  }) =>
      isActive
          ? success('تفعيل حساب', 'تم تفعيل حساب "$name"',
              category: LogCategory.customer)
          : warning('إيقاف حساب', 'تم إيقاف حساب "$name"',
              category: LogCategory.customer);

  static Future<void> logCustomerLimitExceeded({
    required String name,
    required double balance,
    required double maxBalance,
  }) =>
      warning(
        'تجاوز الحد الأقصى',
        'العميل "$name" تجاوز الحد. الرصيد: ${balance.toStringAsFixed(0)} / الحد: ${maxBalance.toStringAsFixed(0)}',
        category: LogCategory.customer,
      );

  // ============ المزامنة ============
  static Future<void> logSyncSuccess({
    int transactionsAdded = 0,
    int customersAdded = 0,
    int customersUpdated = 0,
    bool hasConflict = false,
  }) =>
      success(
        hasConflict ? 'مزامنة مع تعارض' : 'مزامنة ناجحة',
        'تمت المزامنة:'
            '${transactionsAdded > 0 ? " +$transactionsAdded عملية" : ""}'
            '${customersAdded > 0 ? " +$customersAdded حساب" : ""}'
            '${customersUpdated > 0 ? " ~$customersUpdated حساب محدّث" : ""}'
            '${transactionsAdded == 0 && customersAdded == 0 && customersUpdated == 0 ? " (لا تغييرات)" : ""}',
        category: LogCategory.sync,
      );

  static Future<void> logSyncError(String errMsg) => logError(
        'فشل المزامنة',
        'خطأ: $errMsg',
        category: LogCategory.sync,
      );

  static Future<void> logSyncUpload(String fileName) => info(
        'رفع مزامنة',
        'تم رفع ملف المزامنة: $fileName',
        category: LogCategory.sync,
      );

  static Future<void> logSyncDownload(String fileName) => info(
        'تنزيل مزامنة',
        'تم تنزيل ملف المزامنة: $fileName',
        category: LogCategory.sync,
      );

  // ============ النسخ الاحتياطي ============
  static Future<void> logBackupCreated({
    required int customersCount,
    required int transactionsCount,
    bool cloud = false,
  }) =>
      success(
        cloud ? 'نسخة سحابية' : 'نسخة محلية',
        'تم إنشاء نسخة احتياطية (${cloud ? "Drive" : "محلية"}): $customersCount حساب، $transactionsCount عملية',
        category: LogCategory.backup,
      );

  static Future<void> logBackupRestored({
    required int customersAdded,
    required int transactionsAdded,
    required String mode,
  }) =>
      warning(
        'استعادة نسخة',
        'تمت الاستعادة ($mode): +$customersAdded حساب، +$transactionsAdded عملية',
        category: LogCategory.backup,
      );

  // ============ الصوت ============
  static Future<void> logVoiceSuccess({
    required String text,
    String? audioPath,
    String? parsedAction,
  }) =>
      success(
        'تسجيل صوتي ناجح',
        'تم التعرف: "$text"${parsedAction != null ? " → $parsedAction" : ""}',
        category: LogCategory.voice,
        audioPath: audioPath,
      );

  static Future<void> logVoiceFail({
    required String reason,
    required String text,
    String? audioPath,
  }) =>
      warning(
        'تسجيل صوتي فاشل',
        'لم يتم التعرف: $reason\nالنص: "$text"',
        category: LogCategory.voice,
        audioPath: audioPath,
      );

  static Future<void> logVoiceEmpty({String? audioPath}) => warning(
        'تسجيل صوتي فارغ',
        'لم أسمع شيئاً',
        category: LogCategory.voice,
        audioPath: audioPath,
      );

  // ============ الإعدادات ============
  static Future<void> logSettingChanged({
    required String settingName,
    required String oldValue,
    required String newValue,
  }) =>
      info(
        'تغيير إعداد',
        '$settingName: "$oldValue" → "$newValue"',
        category: LogCategory.settings,
      );

  // ============ الأمان ============
  static Future<void> logSecurityEvent({
    required String action,
    required String description,
  }) =>
      info(action, description, category: LogCategory.security);

  // ============ الرموز ============
  static Future<void> logCodeChanged({
    required String type,
    required String oldPrefix,
    required String newPrefix,
    required int updatedCount,
  }) =>
      info(
        'تغيير رموز',
        '$type: "$oldPrefix" → "$newPrefix" (تم تحديث $updatedCount)',
        category: LogCategory.code,
      );
}
