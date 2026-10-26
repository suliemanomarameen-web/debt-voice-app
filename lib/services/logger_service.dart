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
      case 'voice+manual':
        return '🎤✏️ صوتي + مراجَع';
      default:
        return '';
    }
  }

  static String? _extractAccountantFromMetadata(
      Map<String, dynamic>? metadata) {
    if (metadata == null) return null;
    final acc = metadata['accountant'];
    if (acc == null) return null;
    final s = acc.toString().trim();
    return s.isEmpty ? null : s;
  }

  static Future<int> log({
    required String action,
    required String description,
    LogLevel level = LogLevel.info,
    LogCategory category = LogCategory.system,
    String? accountant,
    String? relatedId,
    Map<String, dynamic>? metadata,
    String? audioPath,
    bool needsAck = false,
  }) async {
    try {
      accountant ??= _extractAccountantFromMetadata(metadata);

      if (accountant == null) {
        try {
          accountant = await AccountantService.getAccountantName();
        } catch (_) {}
      }

      final finalNeedsAck = needsAck ||
          (level == LogLevel.error || level == LogLevel.warning);

      final event = LogEvent(
        action: action,
        description: description,
        level: level,
        category: category,
        accountant: accountant,
        relatedId: relatedId,
        metadata: LogEvent.encodeMetadata(metadata),
        audioPath: audioPath,
        isAcknowledged: false,
        needsAck: finalNeedsAck,
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

  static Future<void> info(
    String action,
    String description, {
    LogCategory category = LogCategory.system,
    String? accountant,
    String? relatedId,
    Map<String, dynamic>? metadata,
    String? audioPath,
    bool needsAck = false,
  }) =>
      log(
        action: action,
        description: description,
        level: LogLevel.info,
        category: category,
        accountant: accountant,
        relatedId: relatedId,
        metadata: metadata,
        audioPath: audioPath,
        needsAck: needsAck,
      );

  static Future<void> success(
    String action,
    String description, {
    LogCategory category = LogCategory.system,
    String? accountant,
    String? relatedId,
    Map<String, dynamic>? metadata,
    String? audioPath,
    bool needsAck = false,
  }) =>
      log(
        action: action,
        description: description,
        level: LogLevel.success,
        category: category,
        accountant: accountant,
        relatedId: relatedId,
        metadata: metadata,
        audioPath: audioPath,
        needsAck: needsAck,
      );

  static Future<void> warning(
    String action,
    String description, {
    LogCategory category = LogCategory.system,
    String? accountant,
    String? relatedId,
    Map<String, dynamic>? metadata,
    String? audioPath,
    bool needsAck = false,
  }) =>
      log(
        action: action,
        description: description,
        level: LogLevel.warning,
        category: category,
        accountant: accountant,
        relatedId: relatedId,
        metadata: metadata,
        audioPath: audioPath,
        needsAck: needsAck,
      );

  static Future<void> logError(
    String action,
    String description, {
    LogCategory category = LogCategory.system,
    String? accountant,
    String? relatedId,
    Map<String, dynamic>? metadata,
    String? audioPath,
    bool needsAck = false,
  }) =>
      log(
        action: action,
        description: description,
        level: LogLevel.error,
        category: category,
        accountant: accountant,
        relatedId: relatedId,
        metadata: metadata,
        audioPath: audioPath,
        needsAck: needsAck,
      );

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

  static Future<List<LogEvent>> getPendingVoiceLogs({
    int limit = 200,
  }) async {
    try {
      final db = await DatabaseHelper.instance.database;
      final r = await db.query(
        'log_events',
        where: "category = 'voice' AND is_acknowledged = 0",
        orderBy: 'created_at DESC',
        limit: limit,
      );

      return r.map((e) => LogEvent.fromMap(e)).toList();
    } catch (e) {
      debugPrint('❌ [Logger] getPendingVoiceLogs error: $e');
      return [];
    }
  }

  static Future<int> getPendingVoiceCount() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final r = await db.rawQuery('''
        SELECT COUNT(*) AS cnt FROM log_events
        WHERE category = 'voice' AND is_acknowledged = 0
      ''');
      return (r.first['cnt'] as int?) ?? 0;
    } catch (_) {
      return 0;
    }
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

  static Future<int> getPendingAckCount() async {
    try {
      return await DatabaseHelper.instance.getPendingAckCount();
    } catch (e) {
      debugPrint('❌ [Logger] getPendingAckCount: $e');
      return 0;
    }
  }

  static Future<List<LogEvent>> getAllPendingAck({int limit = 100}) async {
    try {
      final rows =
          await DatabaseHelper.instance.getAllPendingAck(limit: limit);
      return rows.map((e) => LogEvent.fromMap(e)).toList();
    } catch (e) {
      debugPrint('❌ [Logger] getAllPendingAck: $e');
      return [];
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

      final pendingAck = await db.rawQuery('''
        SELECT COUNT(*) AS c FROM log_events
        WHERE is_acknowledged = 0
          AND needs_acknowledgement = 1
      ''');

      final pendingVoice = await db.rawQuery('''
        SELECT COUNT(*) AS c FROM log_events
        WHERE is_acknowledged = 0
          AND category = 'voice'
      ''');

      return {
        'total': (total.first['c'] as int?) ?? 0,
        'errors': (errors.first['c'] as int?) ?? 0,
        'warnings': (warnings.first['c'] as int?) ?? 0,
        'today': (today.first['c'] as int?) ?? 0,
        'pending': (pending.first['c'] as int?) ?? 0,
        'pendingAck': (pendingAck.first['c'] as int?) ?? 0,
        'pendingVoice': (pendingVoice.first['c'] as int?) ?? 0,
      };
    } catch (_) {
      return {
        'total': 0,
        'errors': 0,
        'warnings': 0,
        'today': 0,
        'pending': 0,
        'pendingAck': 0,
        'pendingVoice': 0,
      };
    }
  }

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
      final count = await getPendingAckCount();
      if (!_pendingCountController.isClosed) {
        _pendingCountController.add(count);
      }
    } catch (_) {}
  }

  static Future<void> refreshPendingCount() async {
    await _notifyPendingCount();
  }

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
    final sourceText = _sourceLabel(source);
    final sourcePart = sourceText.isNotEmpty ? ' • المصدر: $sourceText' : '';

    return success(
      'إضافة $typeLabel',
      'تم تسجيل $typeLabel بمبلغ ${amount.toStringAsFixed(0)} $currency للعميل "$customerName"$sourcePart',
      category: LogCategory.transaction,
      relatedId: relatedId,
      audioPath: audioPath,
      accountant: accountant,
      needsAck: false,
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

  // 🆕 دالة الحذف مع التفاصيل الكاملة
  static Future<void> logTransactionDeleted({
    required String customerName,
    required double amount,
    String? code,
    String? items,
    String? currency,
    String? type,
    bool isHard = false,
    String? accountant,
  }) {
    final buf = StringBuffer();
    buf.write('تم حذف عملية');
    if (type != null && type.isNotEmpty) {
      final typeLabel = {
            'debt': 'دين',
            'payment': 'سداد',
            'return': 'مرتجع',
          }[type] ??
          type;
      buf.write(' ($typeLabel)');
    }
    buf.write(' بمبلغ ${amount.toStringAsFixed(0)} ${currency ?? "YER"}');
    buf.write(' للعميل "$customerName"');
    if (code != null && code.isNotEmpty) buf.write('\nالرمز: $code');
    if (items != null && items.isNotEmpty) {
      final clean = items.replaceFirst(RegExp(r'^مرتجع:?\s*'), '').trim();
      if (clean.isNotEmpty) buf.write('\nالأصناف: $clean');
    }
    if (isHard) {
      buf.write('\n🗑️ الحذف نهائي — لا يمكن الاستعادة');
    } else {
      buf.write('\n♻️ يمكن استعادتها من سلة المحذوفات');
    }

    return warning(
      isHard ? '🗑️ حذف نهائي لعملية' : '🗑️ حذف عملية إلى السلة',
      buf.toString(),
      category: LogCategory.transaction,
      accountant: accountant,
      needsAck: false,
    );
  }

  // 🆕 دالة حذف العميل مع التفاصيل الكاملة
  static Future<void> logCustomerDeleted(
    String name, {
    String? phone,
    String? accountType,
    bool isHard = false,
    String? accountant,
  }) {
    final buf = StringBuffer();
    buf.write('تم حذف الحساب "$name"');
    if (phone != null && phone.isNotEmpty) buf.write('\nالهاتف: $phone');
    if (accountType != null && accountType.isNotEmpty) {
      final typeLabel = {
            'customer': 'عميل',
            'supplier': 'مورد',
            'other': 'أخرى',
          }[accountType] ??
          accountType;
      buf.write('\nالنوع: $typeLabel');
    }
    if (isHard) {
      buf.write('\n🗑️ الحذف نهائي — لا يمكن الاستعادة');
    } else {
      buf.write('\n♻️ يمكن استعادته من سلة المحذوفات');
    }

    return warning(
      isHard ? '🗑️ حذف نهائي لعميل' : '🗑️ حذف عميل إلى السلة',
      buf.toString(),
      category: LogCategory.customer,
      accountant: accountant,
      needsAck: false,
    );
  }

  static Future<void> logCustomerAdded(String name, {String? accountant}) =>
      success(
        'إضافة عميل',
        'تم إنشاء حساب جديد: "$name"',
        category: LogCategory.customer,
        accountant: accountant,
      );

  static Future<void> logCustomerStatusChanged({
    required String name,
    required bool isActive,
    String? accountant,
  }) =>
      isActive
          ? success('تفعيل حساب', 'تم تفعيل حساب "$name"',
              category: LogCategory.customer, accountant: accountant)
          : warning('إيقاف حساب', 'تم إيقاف حساب "$name"',
              category: LogCategory.customer, accountant: accountant);

  static Future<void> logCustomerLimitExceeded({
    required String name,
    required double balance,
    required double maxBalance,
    String? accountant,
  }) =>
      logOverLimit(
        customerName: name,
        balance: balance,
        maxBalance: maxBalance,
        accountant: accountant,
      );

  static Future<void> logSyncError(String errMsg, {String? accountant}) =>
      logError(
        'فشل المزامنة',
        'خطأ: $errMsg',
        category: LogCategory.sync,
        accountant: accountant,
      );

  static Future<void> logDebtOnInactiveAccount({
    required String customerName,
    required double amount,
    required String currency,
    String? accountant,
    String? relatedId,
  }) =>
      warning(
        '⚠️ دين على حساب موقوف',
        'تم تسجيل دين بمبلغ ${amount.toStringAsFixed(0)} $currency للعميل "$customerName" (حسابه موقوف).',
        category: LogCategory.customer,
        accountant: accountant,
        relatedId: relatedId,
        needsAck: true,
      );

  static Future<void> logAccountRestored({
    required String customerName,
    required String reason,
    String? accountant,
    String? relatedId,
  }) =>
      warning(
        '🔄 إعادة تفعيل حساب',
        'تم إعادة تفعيل الحساب "$customerName" تلقائياً. السبب: $reason',
        category: LogCategory.customer,
        accountant: accountant,
        relatedId: relatedId,
        needsAck: true,
      );

  static Future<void> logOverLimit({
    required String customerName,
    required double balance,
    required double maxBalance,
    String? accountant,
    String? relatedId,
  }) =>
      warning(
        '⚠️ تجاوز الحد الأقصى',
        'العميل "$customerName" تجاوز الحد. الرصيد: ${balance.toStringAsFixed(0)} / الحد: ${maxBalance.toStringAsFixed(0)}',
        category: LogCategory.customer,
        accountant: accountant,
        relatedId: relatedId,
        needsAck: true,
      );

  static Future<void> logSyncConflict({
    required String detail,
    String? accountant,
  }) =>
      warning(
        '⚠️ نزاع مزامنة',
        detail,
        category: LogCategory.sync,
        accountant: accountant,
        needsAck: true,
      );

  static Future<void> logSyncFailure({
    required String error,
    String? accountant,
  }) =>
      logError(
        '❌ فشل المزامنة',
        'فشلت المزامنة 3 مرات متتالية: $error',
        category: LogCategory.sync,
        accountant: accountant,
        needsAck: true,
      );

  static Future<void> logSyncSuccess({
    int transactionsAdded = 0,
    int customersAdded = 0,
    int customersUpdated = 0,
    bool hasConflict = false,
    String? accountant,
  }) =>
      success(
        hasConflict ? 'مزامنة مع تعارض' : 'مزامنة ناجحة',
        'تمت المزامنة:'
            '${transactionsAdded > 0 ? " +$transactionsAdded عملية" : ""}'
            '${customersAdded > 0 ? " +$customersAdded حساب" : ""}'
            '${customersUpdated > 0 ? " ~$customersUpdated حساب محدّث" : ""}'
            '${transactionsAdded == 0 && customersAdded == 0 && customersUpdated == 0 ? " (لا تغييرات)" : ""}',
        category: LogCategory.sync,
        accountant: accountant,
      );

  static Future<void> logSyncUpload(String fileName, {String? accountant}) =>
      info(
        'رفع مزامنة',
        'تم رفع ملف المزامنة: $fileName',
        category: LogCategory.sync,
        accountant: accountant,
      );

  static Future<void> logSyncDownload(String fileName, {String? accountant}) =>
      info(
        'تنزيل مزامنة',
        'تم تنزيل ملف المزامنة: $fileName',
        category: LogCategory.sync,
        accountant: accountant,
      );

  static Future<void> logBackupCreated({
    required int customersCount,
    required int transactionsCount,
    bool cloud = false,
    String? accountant,
  }) =>
      success(
        cloud ? 'نسخة سحابية' : 'نسخة محلية',
        'تم إنشاء نسخة احتياطية (${cloud ? "Drive" : "محلية"}): $customersCount حساب، $transactionsCount عملية',
        category: LogCategory.backup,
        accountant: accountant,
      );

  static Future<void> logBackupRestored({
    required int customersAdded,
    required int transactionsAdded,
    required String mode,
    String? accountant,
  }) =>
      warning(
        'استعادة نسخة',
        'تمت الاستعادة ($mode): +$customersAdded حساب، +$transactionsAdded عملية',
        category: LogCategory.backup,
        accountant: accountant,
      );

  static Future<void> logVoiceSuccess({
    required String text,
    String? audioPath,
    String? parsedAction,
    String? accountant,
  }) =>
      success(
        'تسجيل صوتي ناجح',
        'تم التعرف: "$text"${parsedAction != null ? " → $parsedAction" : ""}',
        category: LogCategory.voice,
        audioPath: audioPath,
        accountant: accountant,
      );

  static Future<void> logVoiceFail({
    required String reason,
    required String text,
    String? audioPath,
    String? accountant,
  }) =>
      warning(
        'تسجيل صوتي فاشل',
        'لم يتم التعرف: $reason\nالنص: "$text"',
        category: LogCategory.voice,
        audioPath: audioPath,
        accountant: accountant,
        needsAck: false,
      );

  static Future<void> logVoiceEmpty({
    String? audioPath,
    String? accountant,
  }) =>
      warning(
        'تسجيل صوتي فارغ',
        'لم أسمع شيئاً',
        category: LogCategory.voice,
        audioPath: audioPath,
        accountant: accountant,
      );

  static Future<int> logVoicePending({
    required String rawText,
    String? audioPath,
    Map<String, dynamic>? partialParse,
    String? accountant,
  }) async {
    return await log(
      action: 'تسجيل بانتظار المراجعة',
      description: rawText.isEmpty
          ? 'تسجيل صوتي بدون نص واضح'
          : 'لم يُفهم النص: "$rawText"',
      level: LogLevel.warning,
      category: LogCategory.voice,
      audioPath: audioPath,
      accountant: accountant,
      needsAck: false,
      metadata: {
        'pending': true,
        'raw_text': rawText,
        if (partialParse != null) 'partial': partialParse,
        'is_pending_voice': true,
      },
    );
  }

  static Future<void> logSettingChanged({
    required String settingName,
    required String oldValue,
    required String newValue,
    String? accountant,
  }) =>
      info(
        'تغيير إعداد',
        '$settingName: "$oldValue" → "$newValue"',
        category: LogCategory.settings,
        accountant: accountant,
      );

  static Future<void> logSecurityEvent({
    required String action,
    required String description,
    String? accountant,
  }) =>
      info(action, description,
          category: LogCategory.security, accountant: accountant);

  static Future<void> logCodeChanged({
    required String type,
    required String oldPrefix,
    required String newPrefix,
    required int updatedCount,
    String? accountant,
  }) =>
      info(
        'تغيير رموز',
        '$type: "$oldPrefix" → "$newPrefix" (تم تحديث $updatedCount)',
        category: LogCategory.code,
        accountant: accountant,
      );
}
