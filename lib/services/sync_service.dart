import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../db/database_helper.dart';
import '../config/app_settings.dart';
import 'gdrive_service.dart';
import 'logger_service.dart';
import 'settings_service.dart';
import '../models/log_event.dart';

enum SyncStatus {
  idle,
  uploading,
  downloading,
  syncing,
  conflict,
  error,
}

class SyncResult {
  final bool success;
  final String message;
  final int customersAdded;
  final int transactionsAdded;
  final int customersUpdated;
  final int transactionsUpdated;
  final int customersRestored;
  final int transactionsRestored;
  final int logsAdded;
  final int conflictsCount;
  final bool hasConflict;
  final DateTime? timestamp;

  SyncResult({
    required this.success,
    required this.message,
    this.customersAdded = 0,
    this.transactionsAdded = 0,
    this.customersUpdated = 0,
    this.transactionsUpdated = 0,
    this.customersRestored = 0,
    this.transactionsRestored = 0,
    this.logsAdded = 0,
    this.conflictsCount = 0,
    this.hasConflict = false,
    this.timestamp,
  });
}

class SyncService {
  static const String _keyLastSyncTime = 'sync_last_time';
  static const String _keyLastUpload = 'sync_last_upload';
  static const String _keyLastDownload = 'sync_last_download';
  static const String _keyLastLocalChange = 'sync_last_local_change';
  static const String _keyHasPendingChanges = 'sync_has_pending';

  static const Duration _autoSyncThreshold = Duration(minutes: 5);

  static SyncStatus _status = SyncStatus.idle;
  static SyncStatus get status => _status;

  static Timer? _debounceTimer;
  static Timer? _periodicTimer;

  static bool _isSyncing = false;
  static bool get isSyncing => _isSyncing;

  static Future<SyncResult>? _currentSyncFuture;

  static final _statusController = StreamController<SyncStatus>.broadcast();
  static Stream<SyncStatus> get statusStream => _statusController.stream;

  static final _resultController = StreamController<SyncResult>.broadcast();
  static Stream<SyncResult> get resultStream => _resultController.stream;

  static bool get isSyncAvailable => GDriveService.isSignedIn;

  static Future<void> init() async {
    DatabaseHelper.onDataChanged = _onLocalDataChanged;

    Future.delayed(const Duration(seconds: 3), () {
      if (SettingsService.getBool(AppSettings.syncOnAppOpen)) {
        initialSync();
      }
    });

    final interval = SettingsService.getInt(
      AppSettings.syncIntervalMinutes,
      defaultValue: 5,
    );

    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(
      Duration(minutes: interval),
      (_) => silentSync(),
    );

    debugPrint('✅ [Sync] Initialized (interval: ${interval}min)');
  }

  static void dispose() {
    _debounceTimer?.cancel();
    _periodicTimer?.cancel();
    _statusController.close();
    _resultController.close();
  }

  static void _setStatus(SyncStatus s) {
    _status = s;
    if (!_statusController.isClosed) {
      _statusController.add(s);
    }
  }

  static void _onLocalDataChanged() {
    if (!SettingsService.getBool(AppSettings.syncOnDataChange)) return;

    _saveLastLocalChange(DateTime.now());
    _saveHasPendingChanges(true);

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 5), () {
      silentSync();
    });
  }

  static Future<void> checkAndSyncIfNeeded() async {
    if (!SettingsService.getBool(AppSettings.syncEnabled)) return;

    if (!GDriveService.isSignedIn) {
      final ok = await GDriveService.trySilentSignIn();
      if (!ok) return;
    }

    if (_isSyncing) return;

    final lastSync = await getLastSyncTime();
    final now = DateTime.now();

    if (lastSync == null) {
      await silentSync();
      return;
    }

    final elapsed = now.difference(lastSync);
    if (elapsed >= _autoSyncThreshold) {
      await silentSync();
    }
  }

  static Future<void> silentSync() async {
    if (!SettingsService.getBool(AppSettings.syncEnabled)) return;
    if (_isSyncing) return;
    if (!GDriveService.isSignedIn) return;

    try {
      _isSyncing = true;
      _currentSyncFuture = _performSync(silent: true);
      await _currentSyncFuture;
    } catch (e) {
      debugPrint('❌ [Sync] Silent error: $e');
    } finally {
      _isSyncing = false;
      _currentSyncFuture = null;
    }
  }

  static Future<SyncResult> initialSync() async {
    if (!GDriveService.isSignedIn) {
      await GDriveService.trySilentSignIn();
    }

    if (!GDriveService.isSignedIn) {
      return SyncResult(
        success: false,
        message: 'غير متصل بـ Google Drive',
      );
    }

    return _runSync(silent: false, force: false);
  }

  static Future<SyncResult> manualSync() async {
    if (!GDriveService.isSignedIn) {
      final err = await GDriveService.signInWithError();
      if (err != null) {
        return SyncResult(success: false, message: err);
      }
    }

    return _runSync(silent: false, force: false);
  }

  static Future<SyncResult> forceSync() async {
    if (!GDriveService.isSignedIn) {
      final err = await GDriveService.signInWithError();
      if (err != null) {
        return SyncResult(success: false, message: err);
      }
    }

    return _runSync(silent: false, force: true);
  }

  static Future<bool> forceUpload() async {
    try {
      _setStatus(SyncStatus.uploading);

      Map<String, dynamic>? existingCloud;
      try {
        existingCloud = await GDriveService.downloadSyncFile();
      } catch (e) {
        debugPrint('⚠️ [ForceUpload] No cloud data: $e');
      }

      final merged = await _mergeForUpload(existingCloud);
      final ok = await GDriveService.uploadSyncFile(merged);

      _setStatus(ok ? SyncStatus.idle : SyncStatus.error);

      if (ok) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
            _keyLastSyncTime, DateTime.now().toIso8601String());
        await prefs.setString(
            _keyLastUpload, DateTime.now().toIso8601String());
      }

      return ok;
    } catch (e) {
      debugPrint('❌ forceUpload: $e');
      _setStatus(SyncStatus.error);
      return false;
    }
  }

  static Future<SyncResult> forceDownload() async {
    try {
      _setStatus(SyncStatus.downloading);
      final cloudData = await GDriveService.downloadSyncFile();

      if (cloudData == null) {
        _setStatus(SyncStatus.error);
        return SyncResult(
          success: false,
          message: 'لا توجد بيانات في السحابة',
        );
      }

      final result = await _mergeCloudData(cloudData);
      _setStatus(SyncStatus.idle);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _keyLastSyncTime, DateTime.now().toIso8601String());
      await prefs.setString(
          _keyLastDownload, DateTime.now().toIso8601String());

      return SyncResult(
        success: true,
        message: 'تم التنزيل',
        customersAdded: result['customers_added'] ?? 0,
        transactionsAdded: result['transactions_added'] ?? 0,
        customersUpdated: result['customers_updated'] ?? 0,
        transactionsUpdated: result['transactions_updated'] ?? 0,
        customersRestored: result['customers_restored'] ?? 0,
        transactionsRestored: result['transactions_restored'] ?? 0,
        logsAdded: result['logs_added'] ?? 0,
        conflictsCount: result['conflicts'] ?? 0,
        timestamp: DateTime.now(),
      );
    } catch (e) {
      debugPrint('❌ forceDownload: $e');
      _setStatus(SyncStatus.error);
      return SyncResult(success: false, message: 'فشل: $e');
    }
  }

  static Future<SyncResult> _runSync({
    required bool silent,
    required bool force,
  }) async {
    if (_isSyncing && _currentSyncFuture != null) {
      try {
        return await _currentSyncFuture!;
      } catch (e) {
        return SyncResult(
          success: false,
          message: 'فشل المزامنة السابقة: $e',
        );
      }
    }

    try {
      _isSyncing = true;
      final future = _performSync(silent: silent, force: force);
      _currentSyncFuture = future;
      final result = await future;
      return result;
    } finally {
      _isSyncing = false;
      _currentSyncFuture = null;
    }
  }

  static Future<SyncResult> _performSync({
    required bool silent,
    bool force = false,
  }) async {
    if (!silent) _setStatus(SyncStatus.syncing);

    try {
      final prefs = await SharedPreferences.getInstance();
      final db = DatabaseHelper.instance;

      Map<String, dynamic>? cloudData;
      try {
        cloudData = await GDriveService.downloadSyncFile();
      } catch (e) {
        debugPrint('⚠️ [Sync] Download error: $e');
      }

      final cloudCustomers =
          (cloudData?['customers'] as List?)?.cast<Map>() ?? [];
      final cloudTransactions =
          (cloudData?['transactions'] as List?)?.cast<Map>() ?? [];

      final localCustomers = await db.allCustomersRaw();
      final localTransactions = await db.allTransactionsRaw();

      debugPrint(
          '📊 [Sync] Before: Local ${localTransactions.length} tx, Cloud ${cloudTransactions.length} tx');

      final customersDiff =
          localCustomers.length - cloudCustomers.length;
      final transactionsDiff =
          localTransactions.length - cloudTransactions.length;

      final pendingRaw = prefs.getBool(_keyHasPendingChanges) ?? false;
      final hasCountMismatch =
          customersDiff != 0 || transactionsDiff != 0;
      final shouldSync = force || pendingRaw || hasCountMismatch;

      debugPrint(
          '🔍 [Sync] Diffs: customers=$customersDiff, transactions=$transactionsDiff, pending=$pendingRaw, force=$force');

      int conflictsCount = 0;
      int customersRestored = 0;
      int transactionsRestored = 0;
      int customersUpdated = 0;
      int transactionsUpdated = 0;
      int customersAdded = 0;
      int transactionsAdded = 0;
      int logsAdded = 0;

      if (cloudData != null) {
        final result = await _mergeCloudData(cloudData);
        customersAdded = result['customers_added'] ?? 0;
        transactionsAdded = result['transactions_added'] ?? 0;
        customersUpdated = result['customers_updated'] ?? 0;
        transactionsUpdated = result['transactions_updated'] ?? 0;
        customersRestored = result['customers_restored'] ?? 0;
        transactionsRestored = result['transactions_restored'] ?? 0;
        logsAdded = result['logs_added'] ?? 0;
        conflictsCount = result['conflicts'] ?? 0;
      }

      bool uploadOk = true;

      if (shouldSync || customersAdded > 0 || transactionsAdded > 0) {
        if (!silent) _setStatus(SyncStatus.uploading);
        uploadOk = await _uploadCurrentState();

        if (!uploadOk) {
          if (!silent) _setStatus(SyncStatus.error);
          return SyncResult(
            success: false,
            message: 'فشل رفع البيانات إلى Drive',
          );
        }
      }

      int? verifyLocalCount;
      int? verifyCloudCount;

      if (shouldSync) {
        try {
          final verifyCloud = await GDriveService.downloadSyncFile();
          verifyCloudCount =
              (verifyCloud?['transactions'] as List?)?.length ?? 0;
          final verifyLocal = await db.allTransactionsRaw();
          verifyLocalCount = verifyLocal.length;

          debugPrint(
              '🔍 [Sync] Verify: Local $verifyLocalCount, Cloud $verifyCloudCount');
        } catch (e) {
          debugPrint('⚠️ [Sync] Verify error: $e');
        }
      }

      final now = DateTime.now();
      await prefs.setString(_keyLastSyncTime, now.toIso8601String());
      await prefs.setString(_keyLastUpload, now.toIso8601String());
      if (cloudData != null) {
        await prefs.setString(_keyLastDownload, now.toIso8601String());
      }
      await _saveHasPendingChanges(false);

      if (!silent) _setStatus(SyncStatus.idle);

      if (!silent) {
        await LoggerService.logSyncSuccess(
          transactionsAdded: transactionsAdded + transactionsRestored,
          customersAdded: customersAdded + customersRestored,
          customersUpdated: customersUpdated + transactionsUpdated,
          hasConflict: conflictsCount > 0,
        );
      }

      final message = _buildResultMessage(
        shouldSync: shouldSync,
        customersDiff: customersDiff,
        transactionsDiff: transactionsDiff,
        conflictsCount: conflictsCount,
        verifyLocalCount: verifyLocalCount,
        verifyCloudCount: verifyCloudCount,
      );

      final finalResult = SyncResult(
        success: true,
        message: message,
        customersAdded: customersAdded,
        transactionsAdded: transactionsAdded,
        customersUpdated: customersUpdated,
        transactionsUpdated: transactionsUpdated,
        customersRestored: customersRestored,
        transactionsRestored: transactionsRestored,
        logsAdded: logsAdded,
        conflictsCount: conflictsCount,
        hasConflict: conflictsCount > 0,
        timestamp: now,
      );

      if (!_resultController.isClosed) {
        _resultController.add(finalResult);
      }

      return finalResult;
    } catch (e) {
      debugPrint('❌ [Sync] Error: $e');
      if (!silent) _setStatus(SyncStatus.error);
      if (!silent) {
        await LoggerService.logSyncError(e.toString());
      }
      return SyncResult(
        success: false,
        message: 'فشل المزامنة: $e',
      );
    }
  }

  static String _buildResultMessage({
    required bool shouldSync,
    required int customersDiff,
    required int transactionsDiff,
    required int conflictsCount,
    int? verifyLocalCount,
    int? verifyCloudCount,
  }) {
    if (!shouldSync) return '✅ لا توجد تغييرات';

    final parts = <String>[];

    if (conflictsCount > 0) parts.add('⚠️ $conflictsCount تعارض');

    if (verifyLocalCount != null &&
        verifyCloudCount != null &&
        verifyLocalCount != verifyCloudCount) {
      parts.add(
          '⚠️ عدم تطابق: محلي $verifyLocalCount ≠ سحابة $verifyCloudCount');
    } else {
      parts.add('✅ تمت المزامنة');
      if (verifyLocalCount != null) {
        parts.add('($verifyLocalCount عملية متطابقة)');
      }
    }

    return parts.join(' — ');
  }
// ═══════════════════════════════════════════════════════════
// دمج السحابة مع المحلي — مع إصلاح العملاء بدون cloud_id
// ═══════════════════════════════════════════════════════════
static Future<Map<String, int>> _mergeCloudData(
    Map<String, dynamic> cloudData) async {
  final db = DatabaseHelper.instance;
  const uuid = Uuid();

  int addedCustomers = 0;
  int addedTransactions = 0;
  int updatedCustomers = 0;
  int updatedTransactions = 0;
  int restoredCustomers = 0;
  int restoredTransactions = 0;
  int addedLogs = 0;
  int conflicts = 0;
  int failedCustomers = 0;
  int failedTransactions = 0;

  try {
    final cloudCustomers =
        (cloudData['customers'] as List?)?.cast<Map>() ?? [];
    final cloudTransactions =
        (cloudData['transactions'] as List?)?.cast<Map>() ?? [];
    final cloudUsedCodes =
        (cloudData['used_codes'] as List?)?.cast<Map>() ?? [];
    final cloudLogs =
        (cloudData['log_events'] as List?)?.cast<Map>() ?? [];

    debugPrint(
        '🔄 [Merge] Starting: ${cloudCustomers.length} customers, ${cloudTransactions.length} transactions, ${cloudLogs.length} logs');

    // ═══════════════════════════════════════════════════════════
    // 1. الرموز
    // ═══════════════════════════════════════════════════════════
    for (final uc in cloudUsedCodes) {
      final code = uc['code'] as String?;
      final type = uc['type'] as String?;
      if (code == null || type == null) continue;

      try {
        final exists = await db.codeExists(code);
        if (!exists) {
          await db.addUsedCode(code: code, type: type);
        }
      } catch (e) {
        debugPrint('❌ [Merge] Failed to add code "$code": $e');
      }
    }

    // ═══════════════════════════════════════════════════════════
    // 2. العملاء — مع إصلاح cloud_id = null
    // ═══════════════════════════════════════════════════════════
    final Map<int, int> cloudIdToLocalId = {};

    for (final ccMap in cloudCustomers) {
      final cc = Map<String, dynamic>.from(ccMap);
      final cloudId = cc['cloud_id'] as String?;
      final cloudName = cc['name'] as String? ?? '';
      final oldCloudId = cc['id'] as int?;

      try {
        // ─────────────────────────────────────────────────────
        // حالة A: cloud_id فارغ (قديم) → ابحث بالاسم + تاريخ، وإلا أضف
        // ─────────────────────────────────────────────────────
        if (cloudId == null || cloudId.isEmpty) {
          final cloudCreated = cc['created_at'] as String? ?? '';
          final localId =
              await db.findCustomerIdByNameAndDate(cloudName, cloudCreated);

          if (localId != null) {
            // موجود محلياً → اربطه فقط
            if (oldCloudId != null) {
              cloudIdToLocalId[oldCloudId] = localId;
            }
            debugPrint('🔗 [Merge] Linked existing customer "$cloudName"');
          } else {
            // 🆕 غير موجود → أضفه بـ cloud_id جديد
            final newMap = Map<String, dynamic>.from(cc);
            newMap.remove('id');
            newMap['cloud_id'] = uuid.v4();

            try {
              final newId = await db.insertCustomerRaw(newMap);
              addedCustomers++;
              if (oldCloudId != null) {
                cloudIdToLocalId[oldCloudId] = newId;
              }
              debugPrint(
                  '✅ [Merge] Inserted customer "$cloudName" (null cloud_id → new UUID)');
            } catch (e) {
              debugPrint(
                  '❌ [Merge] Failed to insert customer "$cloudName": $e');
              failedCustomers++;
            }
          }
          continue;
        }

        // ─────────────────────────────────────────────────────
        // حالة B: cloud_id موجود → ابحث به
        // ─────────────────────────────────────────────────────
        final localRows = await db.database.then((d) => d.query(
            'customers',
            where: 'cloud_id = ?',
            whereArgs: [cloudId],
            limit: 1));

        if (localRows.isEmpty) {
          // جديد من السحابة
          if (cc['is_permanently_deleted'] == 1) continue;

          final newMap = Map<String, dynamic>.from(cc);
          newMap.remove('id');

          try {
            final newId = await db.insertCustomerRaw(newMap);
            addedCustomers++;
            if (oldCloudId != null) {
              cloudIdToLocalId[oldCloudId] = newId;
            }

            if (SettingsService.getBool(AppSettings.logRemoteActivity)) {
              await _logRemoteActivity(
                item: 'حساب "$cloudName"',
                action: 'إضافة من جهاز آخر',
                by: cc['created_by'] as String?,
              );
            }
          } catch (e) {
            debugPrint(
                '❌ [Merge] Failed to insert customer "$cloudName": $e');
            failedCustomers++;
          }
        } else {
          final localId = localRows.first['id'] as int;
          if (oldCloudId != null) {
            cloudIdToLocalId[oldCloudId] = localId;
          }

          // إذا السحابة محذوف نهائياً → احذفه محلياً
          if (cc['is_permanently_deleted'] == 1) {
            try {
              await db.database.then((d) => d.update(
                    'customers',
                    {'is_deleted': 1, 'is_permanently_deleted': 1},
                    where: 'id = ?',
                    whereArgs: [localId],
                  ));
            } catch (e) {
              debugPrint(
                  '❌ [Merge] Failed to hard delete customer: $e');
            }
            continue;
          }

          try {
            final localMap = Map<String, dynamic>.from(localRows.first);
            final resolution = await _resolveCustomerConflict(
              localRow: localMap,
              cloudRow: cc,
            );

            if (resolution == 'updated') {
              updatedCustomers++;
            } else if (resolution == 'restored') {
              restoredCustomers++;
            } else if (resolution == 'conflict') {
              conflicts++;
            }
          } catch (e) {
            debugPrint('❌ [Merge] Customer conflict error: $e');
            failedCustomers++;
          }
        }
      } catch (e) {
        debugPrint('❌ [Merge] Customer loop error: $e');
        failedCustomers++;
      }
    }

    debugPrint(
        '📋 [Merge] Customers done: +$addedCustomers added, cloudIdToLocalId has ${cloudIdToLocalId.length} mappings');

    // ═══════════════════════════════════════════════════════════
    // 3. المعاملات — مع إصلاح cloud_id = null
    // ═══════════════════════════════════════════════════════════
    for (final ctMap in cloudTransactions) {
      final ct = Map<String, dynamic>.from(ctMap);
      final cloudId = ct['cloud_id'] as String?;
      final cloudCustomerId = ct['customer_id'] as int?;

      if (cloudCustomerId == null) continue;

      final localCustomerId = cloudIdToLocalId[cloudCustomerId];
      if (localCustomerId == null) {
        debugPrint(
            '⚠️ [Merge] Transaction skipped: no local customer for cloud #$cloudCustomerId');
        continue;
      }

      try {
        // ─────────────────────────────────────────────────────
        // حالة A: cloud_id فارغ (قديم) → ابحث بالمعرفات، وإلا أضف
        // ─────────────────────────────────────────────────────
        if (cloudId == null || cloudId.isEmpty) {
          if (ct['is_permanently_deleted'] == 1) continue;

          final amount = (ct['amount'] as num?)?.toDouble() ?? 0;
          final type = ct['type'] as String? ?? 'debt';
          final createdAt = ct['created_at'] as String? ?? '';

          final exists = await db.transactionExists(
            customerId: localCustomerId,
            amount: amount,
            type: type,
            createdAt: createdAt,
          );

          if (!exists) {
            // 🆕 غير موجود → أضفه بـ cloud_id جديد
            final newMap = Map<String, dynamic>.from(ct);
            newMap.remove('id');
            newMap['customer_id'] = localCustomerId;
            newMap['cloud_id'] = uuid.v4();

            // تجاوز الرمز المكرر
            final code = newMap['code'] as String?;
            if (code != null && code.isNotEmpty) {
              try {
                if (await db.codeExists(code)) {
                  newMap['code'] = null;
                }
              } catch (_) {}
            }

            try {
              await db.insertTransactionRaw(newMap);
              addedTransactions++;
              debugPrint(
                  '✅ [Merge] Inserted transaction (null cloud_id → new UUID)');
            } catch (e) {
              debugPrint('❌ [Merge] Failed to insert tx: $e');
              failedTransactions++;
            }
          }
          continue;
        }

        // ─────────────────────────────────────────────────────
        // حالة B: cloud_id موجود → ابحث به
        // ─────────────────────────────────────────────────────
        final localRows = await db.database.then((d) => d.query(
            'transactions',
            where: 'cloud_id = ?',
            whereArgs: [cloudId],
            limit: 1));

        if (localRows.isEmpty) {
          if (ct['is_permanently_deleted'] == 1) continue;

          final newMap = Map<String, dynamic>.from(ct);
          newMap.remove('id');
          newMap['customer_id'] = localCustomerId;

          // تجاوز الرمز المكرر
          final code = newMap['code'] as String?;
          if (code != null && code.isNotEmpty) {
            try {
              if (await db.codeExists(code)) {
                newMap['code'] = null;
              }
            } catch (_) {}
          }

          try {
            await db.insertTransactionRaw(newMap);
            addedTransactions++;

            if (SettingsService.getBool(AppSettings.logRemoteActivity)) {
              await _logRemoteActivity(
                item:
                    'عملية بمبلغ ${(ct['amount'] as num).toStringAsFixed(0)}',
                action: 'إضافة من جهاز آخر',
                by: ct['accountant'] as String?,
              );
            }
          } catch (e) {
            debugPrint('❌ [Merge] Failed to insert tx: $e');
            failedTransactions++;
          }
        } else {
          final localId = localRows.first['id'] as int;

          // إذا السحابة محذوف نهائياً → احذفه محلياً
          if (ct['is_permanently_deleted'] == 1) {
            try {
              await db.database.then((d) => d.update(
                    'transactions',
                    {'is_deleted': 1, 'is_permanently_deleted': 1},
                    where: 'id = ?',
                    whereArgs: [localId],
                  ));
            } catch (e) {
              debugPrint('❌ [Merge] Failed to hard delete tx: $e');
            }
            continue;
          }

          try {
            final localMap = Map<String, dynamic>.from(localRows.first);
            final resolution = await _resolveTransactionConflict(
              localRow: localMap,
              cloudRow: ct,
            );

            if (resolution == 'updated') {
              updatedTransactions++;
            } else if (resolution == 'restored') {
              restoredTransactions++;
            } else if (resolution == 'conflict') {
              conflicts++;
            }
          } catch (e) {
            debugPrint('❌ [Merge] Tx conflict error: $e');
            failedTransactions++;
          }
        }
      } catch (e) {
        debugPrint('❌ [Merge] Tx loop error: $e');
        failedTransactions++;
      }
    }

    // ═══════════════════════════════════════════════════════════
    // 4. الأحداث
    // ═══════════════════════════════════════════════════════════
    if (SettingsService.getBool(AppSettings.syncLogs)) {
      for (final cl in cloudLogs) {
        final action = cl['action'] as String? ?? '';
        final createdAt = cl['created_at'] as String? ?? '';
        if (action.isEmpty || createdAt.isEmpty) continue;

        try {
          final accountant = cl['accountant'] as String?;
          final exists = await db.logEventExists(
            action: action,
            createdAt: createdAt,
            accountant: accountant,
          );

          if (!exists) {
            final newMap = Map<String, dynamic>.from(cl);
            newMap.remove('id');

            try {
              await db.insertLogEventRaw(newMap);
              addedLogs++;
            } catch (e) {
              debugPrint('❌ [Merge] Failed to insert log: $e');
            }
          }
        } catch (e) {
          debugPrint('❌ [Merge] Log loop error: $e');
        }
      }
    }

    debugPrint(
        '✅ [Merge] Done: +$addedCustomers c, ~$updatedCustomers u, ~$restoredCustomers r, +$addedTransactions t, ~$updatedTransactions ut, ~$restoredTransactions rt, +$addedLogs l, $conflicts conflicts, ✗$failedCustomers cf, ✗$failedTransactions tf');
  } catch (e) {
    debugPrint('❌ [Merge] Fatal error: $e');
  }

  return {
    'customers_added': addedCustomers,
    'customers_updated': updatedCustomers,
    'customers_restored': restoredCustomers,
    'transactions_added': addedTransactions,
    'transactions_updated': updatedTransactions,
    'transactions_restored': restoredTransactions,
    'logs_added': addedLogs,
    'conflicts': conflicts,
    'failed_customers': failedCustomers,
    'failed_transactions': failedTransactions,
  };
}
  // ═══════════════════════════════════════════════════════════
  // دمج للسحابة عند الرفع — _mergeForUpload
  // ═══════════════════════════════════════════════════════════
  static Future<Map<String, dynamic>> _mergeForUpload(
      Map<String, dynamic>? existingCloud) async {
    final db = DatabaseHelper.instance;

    final localCustomers = await db.allCustomersRaw();
    final localTransactions = await db.allTransactionsRaw();
    final localUsedCodes = await db.allUsedCodesRaw();
    final localLogs = await db.allLogEventsRaw();

    // 🆕 جمع tombstones (المحذوف نهائياً محلياً)
    final Set<String> permanentlyDeletedCustomerKeys = {};
    for (final c in localCustomers) {
      if (c['is_permanently_deleted'] == 1) {
        final k = _customerKey(c);
        if (k.isNotEmpty) permanentlyDeletedCustomerKeys.add(k);
      }
    }

    final Set<String> permanentlyDeletedTransactionKeys = {};
    for (final t in localTransactions) {
      if (t['is_permanently_deleted'] == 1) {
        final k = _transactionKey(t);
        if (k.isNotEmpty) permanentlyDeletedTransactionKeys.add(k);
      }
    }

    // ═══════════════════════════════════════════════════════════
    // العملاء
    // ═══════════════════════════════════════════════════════════
    final Map<String, Map<String, dynamic>> mergedCustomers = {};

    if (existingCloud != null) {
      for (final c in (existingCloud['customers'] as List?) ?? []) {
        final cm = Map<String, dynamic>.from(c);
        final key = _customerKey(cm);
        if (key.isEmpty) continue;
        // 🆕 لا تحتفظ بنسخة السحابة إذا كان محذوفاً نهائياً محلياً
        if (permanentlyDeletedCustomerKeys.contains(key)) continue;
        mergedCustomers[key] = cm;
      }
    }

    for (final c in localCustomers) {
      final key = _customerKey(c);
      if (key.isEmpty) continue;

      // 🆕 احتفظ بالـ tombstone
      if (c['is_permanently_deleted'] == 1) {
        mergedCustomers[key] = c;
        continue;
      }

      if (mergedCustomers.containsKey(key)) {
        final existing = mergedCustomers[key]!;
        final existingUpdated = existing['updated_at'] as String? ?? '';
        final localUpdated = c['updated_at'] as String? ?? '';

        if (localUpdated.compareTo(existingUpdated) > 0) {
          mergedCustomers[key] = c;
        }
      } else {
        mergedCustomers[key] = c;
      }
    }

    // ═══════════════════════════════════════════════════════════
    // المعاملات
    // ═══════════════════════════════════════════════════════════
    final Map<String, Map<String, dynamic>> mergedTransactions = {};

    if (existingCloud != null) {
      for (final t in (existingCloud['transactions'] as List?) ?? []) {
        final tm = Map<String, dynamic>.from(t);
        final key = _transactionKey(tm);
        if (key.isEmpty) continue;
        if (permanentlyDeletedTransactionKeys.contains(key)) continue;
        mergedTransactions[key] = tm;
      }
    }

    for (final t in localTransactions) {
      final key = _transactionKey(t);
      if (key.isEmpty) continue;

      if (t['is_permanently_deleted'] == 1) {
        mergedTransactions[key] = t;
        continue;
      }

      if (mergedTransactions.containsKey(key)) {
        final existing = mergedTransactions[key]!;
        final existingUpdated = existing['updated_at'] as String? ?? '';
        final localUpdated = t['updated_at'] as String? ?? '';

        if (localUpdated.compareTo(existingUpdated) > 0) {
          mergedTransactions[key] = t;
        }
      } else {
        mergedTransactions[key] = t;
      }
    }

    // ═══════════════════════════════════════════════════════════
    // الرموز
    // ═══════════════════════════════════════════════════════════
    final Set<String> codesSet = {};
    if (existingCloud != null) {
      for (final u in (existingCloud['used_codes'] as List?) ?? []) {
        final code = u['code'] as String?;
        if (code != null) codesSet.add(code);
      }
    }
    for (final u in localUsedCodes) {
      final code = u['code'] as String?;
      if (code != null) codesSet.add(code);
    }

    final mergedCodes = codesSet.map((code) {
      final localMatch = localUsedCodes.firstWhere(
        (u) => u['code'] == code,
        orElse: () => {
          'code': code,
          'type': 'debt',
          'created_at': DateTime.now().toIso8601String()
        },
      );
      return {
        'code': localMatch['code'],
        'type': localMatch['type'] ?? 'debt',
        'created_at':
            localMatch['created_at'] ?? DateTime.now().toIso8601String(),
      };
    }).toList();

    // ═══════════════════════════════════════════════════════════
    // الأحداث
    // ═══════════════════════════════════════════════════════════
    final Set<String> logsSet = {};
    final List<Map<String, dynamic>> mergedLogs = [];

    if (existingCloud != null) {
      for (final l in (existingCloud['log_events'] as List?) ?? []) {
        final lm = Map<String, dynamic>.from(l);
        final key = _logKey(lm);
        if (key.isNotEmpty && !logsSet.contains(key)) {
          logsSet.add(key);
          mergedLogs.add(lm);
        }
      }
    }

    for (final l in localLogs) {
      final key = _logKey(l);
      if (key.isNotEmpty && !logsSet.contains(key)) {
        logsSet.add(key);
        mergedLogs.add(l);
      }
    }

    debugPrint(
        '🔀 [MergeForUpload] ${mergedCustomers.length} c, ${mergedTransactions.length} t, ${mergedCodes.length} codes, ${mergedLogs.length} logs');

    return {
      'app': 'debt_voice_app',
      'version': 4,
      'created_at': DateTime.now().toIso8601String(),
      'customers': mergedCustomers.values.toList(),
      'transactions': mergedTransactions.values.toList(),
      'used_codes': mergedCodes,
      'log_events': mergedLogs,
    };
  }

  // ═══════════════════════════════════════════════════════════
  // مفاتيح موحدة
  // ═══════════════════════════════════════════════════════════
  static String _customerKey(Map<String, dynamic> c) {
    final cloudId = c['cloud_id'] as String?;
    if (cloudId != null && cloudId.isNotEmpty) return 'cloud_$cloudId';
    final name = c['name'] as String? ?? '';
    final created = c['created_at'] as String? ?? '';
    return 'name_${name}_$created';
  }

  static String _transactionKey(Map<String, dynamic> t) {
    final cloudId = t['cloud_id'] as String?;
    if (cloudId != null && cloudId.isNotEmpty) return 'cloud_$cloudId';
    final code = t['code'] as String? ?? '';
    final customerId = t['customer_id']?.toString() ?? '';
    final amount = t['amount']?.toString() ?? '';
    final created = t['created_at'] as String? ?? '';
    return 'code_${code}_${customerId}_${amount}_$created';
  }

  static String _logKey(Map<String, dynamic> l) {
    final action = l['action'] as String? ?? '';
    final createdAt = l['created_at'] as String? ?? '';
    final accountant = l['accountant'] as String? ?? '';
    return '${action}_${createdAt}_$accountant';
  }

  // ═══════════════════════════════════════════════════════════
  // حل تعارض العميل — الأحدث يفوز
  // ═══════════════════════════════════════════════════════════
  static Future<String> _resolveCustomerConflict({
    required Map<String, dynamic> localRow,
    required Map<String, dynamic> cloudRow,
  }) async {
    final db = DatabaseHelper.instance;
    final localId = localRow['id'] as int;
    final name = localRow['name'] as String? ?? '';

    // 🆕 إذا أي منهما محذوف نهائياً → احذف
    final localPermanent = localRow['is_permanently_deleted'] == 1;
    final cloudPermanent = cloudRow['is_permanently_deleted'] == 1;
    if (localPermanent || cloudPermanent) {
      await db.database.then((d) => d.update(
            'customers',
            {'is_deleted': 1, 'is_permanently_deleted': 1},
            where: 'id = ?',
            whereArgs: [localId],
          ));
      return 'updated';
    }

    final localDeleted = localRow['is_deleted'] == 1;
    final cloudDeleted = cloudRow['is_deleted'] == 1;

    final localUpdatedAt = localRow['updated_at'] as String? ??
        localRow['created_at'] as String? ??
        '';
    final cloudUpdatedAt = cloudRow['updated_at'] as String? ??
        cloudRow['created_at'] as String? ??
        '';

    final localTime = DateTime.tryParse(localUpdatedAt) ?? DateTime(2000);
    final cloudTime = DateTime.tryParse(cloudUpdatedAt) ?? DateTime(2000);

    if (localUpdatedAt == cloudUpdatedAt && localDeleted == cloudDeleted) {
      return 'no_change';
    }

    // تعارض حذف
    if (localDeleted != cloudDeleted) {
      if (localTime.isAfter(cloudTime)) {
        if (localDeleted) {
          await _logDeletionConflict(
            item: 'حساب "$name"',
            deletedBy: localRow['deleted_by'] as String?,
            deletedAt: localRow['deleted_at'] as String?,
            restoredBy: 'لا أحد',
            reason: 'حذفت الحساب مؤخراً — السحابة ستتبعه',
          );
          return 'no_change';
        } else {
          await _logDeletionConflict(
            item: 'حساب "$name"',
            deletedBy: cloudRow['deleted_by'] as String?,
            deletedAt: cloudRow['deleted_at'] as String?,
            restoredBy: 'المزامنة',
            reason: 'تعديل محلي أحدث من الحذف السحابي',
          );
          return 'restored';
        }
      } else {
        if (cloudDeleted) {
          await db.softDeleteCustomer(localId,
              by: cloudRow['deleted_by'] as String? ?? 'المزامنة');
          await _logDeletionConflict(
            item: 'حساب "$name"',
            deletedBy: cloudRow['deleted_by'] as String?,
            deletedAt: cloudRow['deleted_at'] as String?,
            restoredBy: 'المزامنة',
            reason: 'حُذف من جهاز آخر (أحدث)',
          );
          return 'updated';
        } else {
          await db.restoreCustomer(localId, by: 'المزامنة');
          await _logDeletionConflict(
            item: 'حساب "$name"',
            deletedBy: localRow['deleted_by'] as String?,
            deletedAt: localRow['deleted_at'] as String?,
            restoredBy: 'المزامنة',
            reason: 'تعديل سحابي أحدث من الحذف المحلي',
          );
          return 'restored';
        }
      }
    }

    // تعارض تعديل
    if (localUpdatedAt != cloudUpdatedAt) {
      final localIsNewer = localTime.isAfter(cloudTime);

      if (localIsNewer) {
        return 'no_change';
      }

      final changedFields = <String>[];
      final updateData = <String, dynamic>{};

      final fields = [
        'name',
        'phone',
        'account_type',
        'note',
        'photo_path',
        'category',
        'max_balance',
        'is_active',
      ];

      for (final f in fields) {
        final localVal = localRow[f];
        final cloudVal = cloudRow[f];
        if (localVal != cloudVal) {
          updateData[f] = cloudVal;
          changedFields.add(f);
        }
      }

      if (updateData.isNotEmpty) {
        updateData['updated_at'] = cloudUpdatedAt;
        updateData['updated_by'] = cloudRow['updated_by'];

        await db.updateCustomerFields(localId, updateData);

        await _logFieldConflict(
          item: 'حساب "$name"',
          fields: changedFields,
          localUpdatedAt: localUpdatedAt,
          cloudUpdatedAt: cloudUpdatedAt,
          by: cloudRow['updated_by'] as String?,
        );

        return 'conflict';
      }
    }

    return 'no_change';
  }

  // ═══════════════════════════════════════════════════════════
  // حل تعارض المعاملة — الأحدث يفوز
  // ═══════════════════════════════════════════════════════════
  static Future<String> _resolveTransactionConflict({
    required Map<String, dynamic> localRow,
    required Map<String, dynamic> cloudRow,
  }) async {
    final db = DatabaseHelper.instance;
    final localId = localRow['id'] as int;

    // 🆕 إذا أي منهما محذوف نهائياً → احذف
    final localPermanent = localRow['is_permanently_deleted'] == 1;
    final cloudPermanent = cloudRow['is_permanently_deleted'] == 1;
    if (localPermanent || cloudPermanent) {
      await db.database.then((d) => d.update(
            'transactions',
            {'is_deleted': 1, 'is_permanently_deleted': 1},
            where: 'id = ?',
            whereArgs: [localId],
          ));
      return 'updated';
    }

    final localDeleted = localRow['is_deleted'] == 1;
    final cloudDeleted = cloudRow['is_deleted'] == 1;

    final localUpdatedAt = localRow['updated_at'] as String? ??
        localRow['created_at'] as String? ??
        '';
    final cloudUpdatedAt = cloudRow['updated_at'] as String? ??
        cloudRow['created_at'] as String? ??
        '';

    final localTime = DateTime.tryParse(localUpdatedAt) ?? DateTime(2000);
    final cloudTime = DateTime.tryParse(cloudUpdatedAt) ?? DateTime(2000);

    final code = localRow['code'] as String? ?? '';
    final amount = (localRow['amount'] as num?)?.toDouble() ?? 0;

    if (localUpdatedAt == cloudUpdatedAt && localDeleted == cloudDeleted) {
      return 'no_change';
    }

    // تعارض حذف
    if (localDeleted != cloudDeleted) {
      if (localTime.isAfter(cloudTime)) {
        if (localDeleted) {
          await _logDeletionConflict(
            item:
                'عملية ${code.isNotEmpty ? "($code)" : ""} بمبلغ ${amount.toStringAsFixed(0)}',
            deletedBy: localRow['deleted_by'] as String?,
            deletedAt: localRow['deleted_at'] as String?,
            restoredBy: 'لا أحد',
            reason: 'حذفت العملية مؤخراً — السحابة ستتبعها',
          );
          return 'no_change';
        } else {
          await _logDeletionConflict(
            item:
                'عملية ${code.isNotEmpty ? "($code)" : ""} بمبلغ ${amount.toStringAsFixed(0)}',
            deletedBy: cloudRow['deleted_by'] as String?,
            deletedAt: cloudRow['deleted_at'] as String?,
            restoredBy: 'المزامنة',
            reason: 'تعديل محلي أحدث من الحذف السحابي',
          );
          return 'restored';
        }
      } else {
        if (cloudDeleted) {
          await db.softDeleteTransaction(localId,
              by: cloudRow['deleted_by'] as String? ?? 'المزامنة');
          await _logDeletionConflict(
            item:
                'عملية ${code.isNotEmpty ? "($code)" : ""} بمبلغ ${amount.toStringAsFixed(0)}',
            deletedBy: cloudRow['deleted_by'] as String?,
            deletedAt: cloudRow['deleted_at'] as String?,
            restoredBy: 'المزامنة',
            reason: 'حُذفت من جهاز آخر (أحدث)',
          );
          return 'updated';
        } else {
          await db.restoreTransaction(localId, by: 'المزامنة');
          await _logDeletionConflict(
            item:
                'عملية ${code.isNotEmpty ? "($code)" : ""} بمبلغ ${amount.toStringAsFixed(0)}',
            deletedBy: localRow['deleted_by'] as String?,
            deletedAt: localRow['deleted_at'] as String?,
            restoredBy: 'المزامنة',
            reason: 'تعديل سحابي أحدث من الحذف المحلي',
          );
          return 'restored';
        }
      }
    }

    // تعارض تعديل
    if (localUpdatedAt != cloudUpdatedAt) {
      final localIsNewer = localTime.isAfter(cloudTime);

      if (localIsNewer) {
        return 'no_change';
      }

      final changedFields = <String>[];
      final updateData = <String, dynamic>{};

      final fields = ['amount', 'items', 'type', 'currency'];

      for (final f in fields) {
        final localVal = localRow[f];
        final cloudVal = cloudRow[f];
        if (localVal != cloudVal) {
          updateData[f] = cloudVal;
          changedFields.add(f);
        }
      }

      if (updateData.isNotEmpty) {
        updateData['updated_at'] = cloudUpdatedAt;
        updateData['updated_by'] = cloudRow['updated_by'];
        updateData['last_modified_by'] = cloudRow['last_modified_by'];
        updateData['last_modified_from'] = cloudRow['last_modified_from'];

        await db.updateTransactionFields(localId, updateData);

        await _logFieldConflict(
          item: 'عملية ${code.isNotEmpty ? "($code)" : ""}',
          fields: changedFields,
          localUpdatedAt: localUpdatedAt,
          cloudUpdatedAt: cloudUpdatedAt,
          by: cloudRow['last_modified_by'] as String? ??
              cloudRow['updated_by'] as String?,
        );

        return 'conflict';
      }
    }

    return 'no_change';
  }

  // ═══════════════════════════════════════════════════════════
  // تسجيل الأنشطة
  // ═══════════════════════════════════════════════════════════

  static Future<void> _logRemoteActivity({
    required String item,
    required String action,
    String? by,
  }) async {
    try {
      await LoggerService.log(
        action: '📡 $action',
        description: '$item — بواسطة ${by ?? "محاسب آخر"}',
        level: LogLevel.info,
        category: LogCategory.sync,
        needsAck: false,
      );
    } catch (_) {}
  }

  static Future<void> _logDeletionConflict({
    required String item,
    String? deletedBy,
    String? deletedAt,
    String? restoredBy,
    String? reason,
  }) async {
    try {
      final desc = StringBuffer();
      desc.write('$item\n');
      if (deletedBy != null) desc.write('حذفه: $deletedBy\n');
      if (deletedAt != null) {
        final dt = DateTime.tryParse(deletedAt);
        if (dt != null) {
          desc.write('وقت الحذف: ${_fmtDt(dt)}\n');
        }
      }
      if (restoredBy != null) desc.write('أعاده: $restoredBy\n');
      if (reason != null) desc.write('السبب: $reason');

      await LoggerService.log(
        action: '⚠️ تعارض حذف',
        description: desc.toString(),
        level: LogLevel.warning,
        category: LogCategory.sync,
        needsAck: true,
        metadata: {
          'item': item,
          'deleted_by': deletedBy,
          'deleted_at': deletedAt,
          'restored_by': restoredBy,
          'reason': reason,
          'type': 'deletion_conflict',
        },
      );
    } catch (_) {}
  }

  static Future<void> _logFieldConflict({
    required String item,
    required List<String> fields,
    required String localUpdatedAt,
    required String cloudUpdatedAt,
    String? by,
  }) async {
    try {
      final fieldNames = fields.map(_fieldNameAr).join('، ');

      final desc = StringBuffer();
      desc.write('$item\n');
      desc.write('الحقول المتعارضة: $fieldNames\n');
      desc.write('آخر تعديل محلي: ${_fmtIso(localUpdatedAt)}\n');
      desc.write('آخر تعديل سحابي: ${_fmtIso(cloudUpdatedAt)}\n');
      if (by != null) desc.write('بواسطة: $by\n');
      desc.write('✅ تم الاحتفاظ بالأحدث');

      await LoggerService.log(
        action: '⚠️ تعارض تعديل — الأحدث فاز',
        description: desc.toString(),
        level: LogLevel.warning,
        category: LogCategory.sync,
        needsAck: true,
        metadata: {
          'item': item,
          'fields': fields,
          'local_updated_at': localUpdatedAt,
          'cloud_updated_at': cloudUpdatedAt,
          'by': by,
          'type': 'field_conflict',
        },
      );
    } catch (_) {}
  }

  static String _fieldNameAr(String field) {
    const map = {
      'name': 'الاسم',
      'phone': 'الهاتف',
      'account_type': 'نوع الحساب',
      'note': 'ملاحظة',
      'photo_path': 'الصورة',
      'category': 'التصنيف',
      'max_balance': 'الحد الأقصى',
      'is_active': 'الحالة',
      'amount': 'المبلغ',
      'items': 'الأصناف',
      'type': 'نوع العملية',
      'currency': 'العملة',
    };
    return map[field] ?? field;
  }

  static String _fmtIso(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    return _fmtDt(dt);
  }

  static String _fmtDt(DateTime dt) {
    return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  // ═══════════════════════════════════════════════════════════
  // رفع الحالة الحالية — مع الدمج
  // ═══════════════════════════════════════════════════════════
  static Future<bool> _uploadCurrentState() async {
    try {
      Map<String, dynamic>? existingCloud;
      try {
        existingCloud = await GDriveService.downloadSyncFile();
      } catch (e) {
        debugPrint('⚠️ [Upload] No existing cloud: $e');
      }

      final merged = await _mergeForUpload(existingCloud);
      final ok = await GDriveService.uploadSyncFile(merged);
      debugPrint('⬆️ [Upload] Result: $ok');

      return ok;
    } catch (e) {
      debugPrint('❌ [Sync] Upload state error: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // أدوات
  // ═══════════════════════════════════════════════════════════
  static Future<void> _saveLastLocalChange(DateTime dt) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastLocalChange, dt.toIso8601String());
  }

  static Future<void> _saveHasPendingChanges(bool has) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyHasPendingChanges, has);
  }

  static Future<DateTime?> getLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_keyLastSyncTime);
    return s != null ? DateTime.parse(s) : null;
  }

  static Future<DateTime?> getLastUploadTime() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_keyLastUpload);
    return s != null ? DateTime.parse(s) : null;
  }

  static Future<DateTime?> getLastDownloadTime() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_keyLastDownload);
    return s != null ? DateTime.parse(s) : null;
  }

  static Future<bool> hasPendingChanges() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyHasPendingChanges) ?? false;
  }
}
