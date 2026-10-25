import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../db/database_helper.dart';
import '../config/app_settings.dart';
import 'gdrive_service.dart';
import 'logger_service.dart';
import 'settings_service.dart';
import 'accountants_service.dart';
import 'device_service.dart';
import '../models/log_event.dart';

enum SyncStatus { idle, uploading, downloading, syncing, conflict, error }

class SyncResult {
  final bool success;
  final String message;
  final int customersAdded;
  final int transactionsAdded;
  final int customersUpdated;
  final int transactionsUpdated;
  final int customersRestored;
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
    this.logsAdded = 0,
    this.conflictsCount = 0,
    this.hasConflict = false,
    this.timestamp,
  });
}

class SyncConflict {
  final String type;
  final String itemName;
  final List<String> fields;
  final DateTime localTime;
  final DateTime cloudTime;

  SyncConflict({
    required this.type,
    required this.itemName,
    required this.fields,
    required this.localTime,
    required this.cloudTime,
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

  static SyncConflict? _lastConflict;
  static SyncConflict? get lastConflict => _lastConflict;

  static bool get isSyncAvailable => GDriveService.isSignedIn;

  // ═══════════════════════════════════════════════════════════
  static Future<void> init() async {
    await DeviceService.getDeviceId();
    await AccountantsService.init();

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
    if (!_statusController.isClosed) _statusController.add(s);
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
    if (elapsed >= _autoSyncThreshold) await silentSync();
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
      return SyncResult(success: false, message: 'غير متصل بـ Google Drive');
    }

    return _runSync(silent: false);
  }

  static Future<SyncResult> manualSync() async {
    if (!GDriveService.isSignedIn) {
      final err = await GDriveService.signInWithError();
      if (err != null) return SyncResult(success: false, message: err);
    }
    return _runSync(silent: false);
  }

  static Future<SyncResult> _runSync({required bool silent}) async {
    if (_isSyncing && _currentSyncFuture != null) {
      try {
        return await _currentSyncFuture!;
      } catch (e) {
        return SyncResult(success: false, message: 'فشل المزامنة السابقة: $e');
      }
    }

    try {
      _isSyncing = true;
      final future = _performSync(silent: silent);
      _currentSyncFuture = future;
      return await future;
    } finally {
      _isSyncing = false;
      _currentSyncFuture = null;
    }
  }

  static Future<SyncResult> _performSync({required bool silent}) async {
    if (!silent) _setStatus(SyncStatus.syncing);

    try {
      if (!await AccountantsService.hasAnyAccountants()) {
        final deviceId = await DeviceService.getDeviceId();
        final primaryId = await DeviceService.getPrimaryDeviceId();
        if (primaryId == null || primaryId.isEmpty) {
          await DeviceService.setPrimaryDeviceId(deviceId);
          await DeviceService.setDeviceStatus(DeviceService.statusAuthorized);
          debugPrint('👑 [Sync] This device became primary automatically');
        }
      }

      final prefs = await SharedPreferences.getInstance();
      final lastSyncStr = prefs.getString(_keyLastSyncTime);
      final lastLocalStr = prefs.getString(_keyLastLocalChange);

      final lastSync =
          lastSyncStr != null ? DateTime.parse(lastSyncStr) : null;
      final lastLocal =
          lastLocalStr != null ? DateTime.parse(lastLocalStr) : null;

      final cloudModified = await GDriveService.getSyncFileModifiedTime();
      final cloudData = await GDriveService.downloadSyncFile();

      final hasLocalChanges =
          lastLocal != null && (lastSync == null || lastLocal.isAfter(lastSync));
      final hasCloudChanges = cloudModified != null &&
          (lastSync == null || cloudModified.isAfter(lastSync));

      if (!hasLocalChanges && !hasCloudChanges) {
        final now = DateTime.now();
        await prefs.setString(_keyLastSyncTime, now.toIso8601String());
        if (!silent) _setStatus(SyncStatus.idle);

        final r = SyncResult(
          success: true,
          message: 'لا توجد تغييرات',
          timestamp: now,
        );
        if (!_resultController.isClosed) _resultController.add(r);
        return r;
      }

      int addedCustomers = 0;
      int addedTransactions = 0;
      int updatedCustomers = 0;
      int updatedTransactions = 0;
      int restoredCustomers = 0;
      int addedLogs = 0;
      int conflictsCount = 0;

      if (hasCloudChanges && cloudData != null) {
        if (!silent) _setStatus(SyncStatus.downloading);
        final result = await _mergeCloudData(cloudData);
        addedCustomers = result['customers_added'] ?? 0;
        addedTransactions = result['transactions_added'] ?? 0;
        updatedCustomers = result['customers_updated'] ?? 0;
        updatedTransactions = result['transactions_updated'] ?? 0;
        restoredCustomers = result['customers_restored'] ?? 0;
        addedLogs = result['logs_added'] ?? 0;
        conflictsCount = result['conflicts'] ?? 0;
      }

      if (hasLocalChanges || hasCloudChanges) {
        if (!silent) _setStatus(SyncStatus.uploading);
        final uploadOk = await _uploadCurrentState();

        if (!uploadOk) {
          if (!silent) _setStatus(SyncStatus.error);
          final errResult = SyncResult(
            success: false,
            message: 'فشل رفع البيانات إلى Drive',
          );
          if (!_resultController.isClosed) _resultController.add(errResult);
          return errResult;
        }
      }

      final now = DateTime.now();
      await prefs.setString(_keyLastSyncTime, now.toIso8601String());
      await prefs.setString(_keyLastUpload, now.toIso8601String());
      if (hasCloudChanges) {
        await prefs.setString(_keyLastDownload, now.toIso8601String());
      }
      await _saveHasPendingChanges(false);

      if (!silent) _setStatus(SyncStatus.idle);

      if (!silent) {
        await LoggerService.logSyncSuccess(
          transactionsAdded: addedTransactions,
          customersAdded: addedCustomers + restoredCustomers,
          customersUpdated: updatedCustomers + updatedTransactions,
          hasConflict: conflictsCount > 0,
        );
      }

      final finalResult = SyncResult(
        success: true,
        message: conflictsCount > 0
            ? 'تمت المزامنة مع $conflictsCount تعارض'
            : 'تمت المزامنة بنجاح',
        customersAdded: addedCustomers,
        transactionsAdded: addedTransactions,
        customersUpdated: updatedCustomers,
        transactionsUpdated: updatedTransactions,
        customersRestored: restoredCustomers,
        logsAdded: addedLogs,
        conflictsCount: conflictsCount,
        hasConflict: conflictsCount > 0,
        timestamp: now,
      );

      if (!_resultController.isClosed) _resultController.add(finalResult);
      return finalResult;
    } catch (e) {
      debugPrint('❌ [Sync] Error: $e');
      if (!silent) _setStatus(SyncStatus.error);
      if (!silent) await LoggerService.logSyncError(e.toString());

      final errResult = SyncResult(
        success: false,
        message: 'فشل المزامنة: $e',
      );
      if (!_resultController.isClosed) _resultController.add(errResult);
      return errResult;
    }
  }

  static Future<void> _applyCloudTombstones(
      Map<String, dynamic> cloudData) async {
    if (!SettingsService.getBool(
      AppSettings.syncDeletedBin,
      defaultValue: true,
    )) {
      return;
    }

    final tombstones = cloudData['tombstones'] as List?;
    if (tombstones == null || tombstones.isEmpty) return;

    final db = DatabaseHelper.instance;
    int applied = 0;
    int deletedLocal = 0;

    for (final tomb in tombstones) {
      if (tomb is! Map) continue;
      final cloudId = tomb['cloud_id'] as String?;
      final type = tomb['type'] as String?;
      if (cloudId == null || cloudId.isEmpty || type == null) continue;

      await db.addTombstone(cloudId: cloudId, type: type);
      applied++;

      try {
        if (type == 'customer') {
          final dbi = await db.database;
          final rows = await dbi.query('customers',
              where: 'cloud_id = ?', whereArgs: [cloudId], limit: 1);
          if (rows.isNotEmpty) {
            final localId = rows.first['id'] as int;
            await dbi.delete('transactions',
                where: 'customer_id = ?', whereArgs: [localId]);
            await dbi.delete('customers',
                where: 'id = ?', whereArgs: [localId]);
            deletedLocal++;
          }
        } else if (type == 'transaction') {
          final dbi = await db.database;
          final rows = await dbi.query('transactions',
              where: 'cloud_id = ?', whereArgs: [cloudId], limit: 1);
          if (rows.isNotEmpty) {
            final localId = rows.first['id'] as int;
            await dbi.delete('transactions',
                where: 'id = ?', whereArgs: [localId]);
            deletedLocal++;
          }
        }
      } catch (e) {
        debugPrint('⚠️ [Sync] Apply tombstone error ($cloudId): $e');
      }
    }

    if (applied > 0) {
      debugPrint(
          '🪦 [Sync] Applied $applied tombstones, deleted $deletedLocal local records');
    }
  }

  static Future<Map<String, int>> _mergeCloudData(
      Map<String, dynamic> cloudData) async {
    final db = DatabaseHelper.instance;

    final cloudPrimaryId = cloudData['primary_device_id'] as String?;
    if (cloudPrimaryId != null && cloudPrimaryId.isNotEmpty) {
      final localPrimaryId = await DeviceService.getPrimaryDeviceId();
      if (localPrimaryId == null || localPrimaryId.isEmpty) {
        await DeviceService.setPrimaryDeviceId(cloudPrimaryId);
        debugPrint('👑 [Sync] Primary device set from cloud: $cloudPrimaryId');
      }
    }

    await _applyCloudTombstones(cloudData);

    int addedCustomers = 0;
    int addedTransactions = 0;
    int updatedCustomers = 0;
    int updatedTransactions = 0;
    int restoredCustomers = 0;
    int addedLogs = 0;
    int conflicts = 0;

    try {
      if (cloudData['accountants'] != null ||
          cloudData['devices'] != null) {
        await AccountantsService.loadFromSync(cloudData);
        debugPrint('✅ [Sync] Accountants merged from cloud');
      }

      final cloudCustomers = (cloudData['customers'] as List?) ?? [];
      final cloudTransactions = (cloudData['transactions'] as List?) ?? [];
      final cloudUsedCodes = (cloudData['used_codes'] as List?) ?? [];
      final cloudLogs = (cloudData['log_events'] as List?) ?? [];

      for (final uc in cloudUsedCodes) {
        final code = uc['code'] as String?;
        final type = uc['type'] as String?;
        if (code == null || type == null) continue;
        final exists = await db.codeExists(code);
        if (!exists) await db.addUsedCode(code: code, type: type);
      }

      final Map<int, int> cloudIdToLocalId = {};

      for (final cc in cloudCustomers) {
        final cloudId = cc['cloud_id'] as String?;
        final cloudName = cc['name'] as String? ?? '';

        if (cloudId != null && cloudId.isNotEmpty) {
          if (await db.hasTombstone(cloudId)) continue;
        }

        if (cloudId == null || cloudId.isEmpty) {
          final cloudCreated = cc['created_at'] as String? ?? '';
          final localId =
              await db.findCustomerIdByNameAndDate(cloudName, cloudCreated);
          if (localId != null) {
            final oldCloudId = cc['id'] as int?;
            if (oldCloudId != null) cloudIdToLocalId[oldCloudId] = localId;
          }
          continue;
        }

        final localRows = await db.database.then((d) => d.query('customers',
            where: 'cloud_id = ?', whereArgs: [cloudId], limit: 1));

        final oldCloudId = cc['id'] as int?;

        if (localRows.isEmpty) {
          final newMap = Map<String, dynamic>.from(cc);
          newMap.remove('id');
          final newId = await db.insertCustomerRaw(newMap);
          addedCustomers++;
          if (oldCloudId != null) cloudIdToLocalId[oldCloudId] = newId;

          if (SettingsService.getBool(AppSettings.logRemoteActivity)) {
            await _logRemoteActivity(
              item: 'حساب "$cloudName"',
              action: 'إضافة من جهاز آخر',
              by: cc['created_by'] as String?,
            );
          }
        } else {
          final localId = localRows.first['id'] as int;
          if (oldCloudId != null) cloudIdToLocalId[oldCloudId] = localId;

          final resolution = await _resolveCustomerConflict(
            localRow: localRows.first,
            cloudRow: cc,
          );

          if (resolution.action == 'updated') {
            updatedCustomers++;
          } else if (resolution.action == 'restored') {
            restoredCustomers++;
          } else if (resolution.action == 'conflict') {
            conflicts++;
          }
        }
      }

      for (final ct in cloudTransactions) {
        final cloudId = ct['cloud_id'] as String?;
        final cloudCustomerId = ct['customer_id'] as int?;

        if (cloudCustomerId == null) continue;

        if (cloudId != null && cloudId.isNotEmpty) {
          if (await db.hasTombstone(cloudId)) continue;
        }

        final localCustomerId = cloudIdToLocalId[cloudCustomerId];
        if (localCustomerId == null) continue;

        if (cloudId == null || cloudId.isEmpty) {
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
            final newMap = Map<String, dynamic>.from(ct);
            newMap.remove('id');
            newMap['customer_id'] = localCustomerId;
            await db.insertTransactionRaw(newMap);
            addedTransactions++;
          }
          continue;
        }

        final localRows = await db.database.then((d) => d.query('transactions',
            where: 'cloud_id = ?', whereArgs: [cloudId], limit: 1));

        if (localRows.isEmpty) {
          final newMap = Map<String, dynamic>.from(ct);
          newMap.remove('id');
          newMap['customer_id'] = localCustomerId;
          await db.insertTransactionRaw(newMap);
          addedTransactions++;

          if (SettingsService.getBool(AppSettings.logRemoteActivity)) {
            await _logRemoteActivity(
              item: 'عملية بمبلغ ${(ct['amount'] as num).toStringAsFixed(0)}',
              action: 'إضافة من جهاز آخر',
              by: ct['accountant'] as String?,
            );
          }
        } else {
          final resolution = await _resolveTransactionConflict(
            localRow: localRows.first,
            cloudRow: ct,
          );

          if (resolution.action == 'updated') {
            updatedTransactions++;
          } else if (resolution.action == 'conflict') {
            conflicts++;
          }
        }
      }

      if (SettingsService.getBool(AppSettings.syncLogs)) {
        for (final cl in cloudLogs) {
          final action = cl['action'] as String? ?? '';
          final createdAt = cl['created_at'] as String? ?? '';
          if (action.isEmpty || createdAt.isEmpty) continue;

          final accountant = cl['accountant'] as String?;
          final exists = await db.logEventExists(
            action: action,
            createdAt: createdAt,
            accountant: accountant,
          );

          if (!exists) {
            final newMap = Map<String, dynamic>.from(cl);
            newMap.remove('id');
            await db.insertLogEventRaw(newMap);
            addedLogs++;
          }
        }
      }

      debugPrint(
          '✅ [Sync] Merged: +$addedCustomers customers, ~$updatedCustomers updated, ~$restoredCustomers restored, +$addedTransactions transactions, ~$updatedTransactions updated, +$addedLogs logs, $conflicts conflicts');
    } catch (e) {
      debugPrint('❌ [Sync] Merge error: $e');
    }

    return {
      'customers_added': addedCustomers,
      'customers_updated': updatedCustomers,
      'customers_restored': restoredCustomers,
      'transactions_added': addedTransactions,
      'transactions_updated': updatedTransactions,
      'logs_added': addedLogs,
      'conflicts': conflicts,
    };
  }

  // ═══════════════════════════════════════════════════════════
  // 🆕 حل تعارض العميل — الأحدث يفوز في الحذف أيضاً
  // ═══════════════════════════════════════════════════════════
  static Future<_ResolutionResult> _resolveCustomerConflict({
    required Map<String, dynamic> localRow,
    required Map<String, dynamic> cloudRow,
  }) async {
    final db = DatabaseHelper.instance;
    final localId = localRow['id'] as int;
    final name = localRow['name'] as String? ?? '';

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
      return _ResolutionResult('no_change');
    }

    // 🆕 تعارض حذف: الأحدث يفوز
    if (localDeleted != cloudDeleted) {
      if (localDeleted && !cloudDeleted) {
        // المحلي محذوف، السحابي نشط
        final localDelTime =
            DateTime.tryParse(localRow['deleted_at'] as String? ?? '') ??
                localTime;

        if (cloudTime.isAfter(localDelTime)) {
          // السحابة أحدث → استعادة محلياً (حدث شيء بعد الحذف)
          await db.restoreCustomer(localId, by: 'المزامنة');
          await _logDeletionConflict(
            item: 'حساب "$name"',
            deletedBy: localRow['deleted_by'] as String?,
            deletedAt: localRow['deleted_at'] as String?,
            restoredBy: 'المزامنة',
            reason: 'آخر تعديل سحابي أحدث من وقت الحذف المحلي',
          );
          return _ResolutionResult('restored');
        } else {
          // الحذف المحلي أحدث أو متساوٍ → احتفظ بالحذف (سيُرفع للسحابة)
          return _ResolutionResult('no_change');
        }
      }

      if (!localDeleted && cloudDeleted) {
        // المحلي نشط، السحابي محذوف
        final cloudDelTime =
            DateTime.tryParse(cloudRow['deleted_at'] as String? ?? '') ??
                cloudTime;

        if (cloudDelTime.isAfter(localTime)) {
          // السحابة أحدث → احذف محلياً
          await db.softDeleteCustomer(localId, by: 'المزامنة');
          await _logDeletionConflict(
            item: 'حساب "$name"',
            deletedBy: cloudRow['deleted_by'] as String?,
            deletedAt: cloudRow['deleted_at'] as String?,
            restoredBy: 'المزامنة',
            reason: 'حذف سحابي أحدث من آخر تعديل محلي',
          );
          return _ResolutionResult('conflict');
        } else {
          // المحلي أحدث → احتفظ بالنشاط (سيُرفع للسحابة)
          return _ResolutionResult('no_change');
        }
      }
    }

    // تعارض تعديل
    if (localUpdatedAt != cloudUpdatedAt) {
      final localIsNewer = localTime.isAfter(cloudTime);

      if (localIsNewer) {
        return _ResolutionResult('no_change');
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

        return _ResolutionResult('conflict');
      }
    }

    return _ResolutionResult('no_change');
  }

  // ═══════════════════════════════════════════════════════════
  // 🆕 حل تعارض المعاملة — الأحدث يفوز في الحذف أيضاً
  // ═══════════════════════════════════════════════════════════
  static Future<_ResolutionResult> _resolveTransactionConflict({
    required Map<String, dynamic> localRow,
    required Map<String, dynamic> cloudRow,
  }) async {
    final db = DatabaseHelper.instance;
    final localId = localRow['id'] as int;

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
      return _ResolutionResult('no_change');
    }

    // 🆕 تعارض حذف: الأحدث يفوز
    if (localDeleted != cloudDeleted) {
      if (localDeleted && !cloudDeleted) {
        final localDelTime =
            DateTime.tryParse(localRow['deleted_at'] as String? ?? '') ??
                localTime;

        if (cloudTime.isAfter(localDelTime)) {
          await db.restoreTransaction(localId, by: 'المزامنة');
          await _logDeletionConflict(
            item:
                'عملية ${code.isNotEmpty ? "($code)" : ""} بمبلغ ${amount.toStringAsFixed(0)}',
            deletedBy: localRow['deleted_by'] as String?,
            deletedAt: localRow['deleted_at'] as String?,
            restoredBy: 'المزامنة',
            reason: 'آخر تعديل سحابي أحدث من وقت الحذف المحلي',
          );
          return _ResolutionResult('restored');
        } else {
          return _ResolutionResult('no_change');
        }
      }

      if (!localDeleted && cloudDeleted) {
        final cloudDelTime =
            DateTime.tryParse(cloudRow['deleted_at'] as String? ?? '') ??
                cloudTime;

        if (cloudDelTime.isAfter(localTime)) {
          await db.softDeleteTransaction(localId, by: 'المزامنة');
          await _logDeletionConflict(
            item:
                'عملية ${code.isNotEmpty ? "($code)" : ""} بمبلغ ${amount.toStringAsFixed(0)}',
            deletedBy: cloudRow['deleted_by'] as String?,
            deletedAt: cloudRow['deleted_at'] as String?,
            restoredBy: 'المزامنة',
            reason: 'حذف سحابي أحدث من آخر تعديل محلي',
          );
          return _ResolutionResult('conflict');
        } else {
          return _ResolutionResult('no_change');
        }
      }
    }

    // تعارض تعديل
    if (localUpdatedAt != cloudUpdatedAt) {
      final localIsNewer = localTime.isAfter(cloudTime);

      if (localIsNewer) return _ResolutionResult('no_change');

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

        return _ResolutionResult('conflict');
      }
    }

    return _ResolutionResult('no_change');
  }

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
        if (dt != null) desc.write('وقت الحذف: ${_fmtDt(dt)}\n');
      }
      if (restoredBy != null) desc.write('أعاد: $restoredBy\n');
      if (reason != null) desc.write('السبب: $reason');

      await LoggerService.log(
        action: '⚠️ تعارض حذف — تم حلّه',
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

  static Future<void> _ensureCloudIds() async {
    try {
      final db = await DatabaseHelper.instance.database;

      final customers = await db.query(
        'customers',
        where: 'cloud_id IS NULL OR cloud_id = ?',
        whereArgs: [''],
      );
      for (final row in customers) {
        await db.update(
          'customers',
          {'cloud_id': const Uuid().v4()},
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      }
      if (customers.isNotEmpty) {
        debugPrint(
            '✅ [Sync] Generated cloud_id for ${customers.length} customers');
      }

      final transactions = await db.query(
        'transactions',
        where: 'cloud_id IS NULL OR cloud_id = ?',
        whereArgs: [''],
      );
      for (final row in transactions) {
        await db.update(
          'transactions',
          {'cloud_id': const Uuid().v4()},
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      }
      if (transactions.isNotEmpty) {
        debugPrint(
            '✅ [Sync] Generated cloud_id for ${transactions.length} transactions');
      }
    } catch (e) {
      debugPrint('⚠️ [Sync] _ensureCloudIds error: $e');
    }
  }

  static Future<bool> _uploadCurrentState() async {
    try {
      await _ensureCloudIds();

      final db = DatabaseHelper.instance;
      final customers = await db.allCustomersRaw();
      final transactions = await db.allTransactionsRaw();
      final usedCodes = await db.allUsedCodesRaw();
      final logEvents = await db.allLogEventsRaw();

      final accountantsData = AccountantsService.getForSync();

      final primaryDeviceId = await DeviceService.getPrimaryDeviceId();

      final tombstones = SettingsService.getBool(
        AppSettings.syncDeletedBin,
        defaultValue: true,
      )
          ? await db.allTombstonesRaw()
          : <Map<String, dynamic>>[];

      final data = {
        'app': 'debt_voice_app',
        'version': 6,
        'created_at': DateTime.now().toIso8601String(),
        'primary_device_id': primaryDeviceId,
        'customers': customers,
        'transactions': transactions,
        'used_codes': usedCodes,
        'log_events': logEvents,
        'tombstones': tombstones,
        ...accountantsData,
      };

      return await GDriveService.uploadSyncFile(data);
    } catch (e) {
      debugPrint('❌ [Sync] Upload state error: $e');
      return false;
    }
  }

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

class _ResolutionResult {
  final String action;
  _ResolutionResult(this.action);
}
