import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../db/database_helper.dart';
import 'gdrive_service.dart';
import 'logger_service.dart';

/// حالة المزامنة
enum SyncStatus {
  idle,
  uploading,
  downloading,
  syncing,
  conflict,
  error,
}

/// نتيجة المزامنة
class SyncResult {
  final bool success;
  final String message;
  final int customersAdded;
  final int transactionsAdded;
  final int customersUpdated;
  final bool hasConflict;
  final DateTime? timestamp;

  SyncResult({
    required this.success,
    required this.message,
    this.customersAdded = 0,
    this.transactionsAdded = 0,
    this.customersUpdated = 0,
    this.hasConflict = false,
    this.timestamp,
  });
}

/// تعارض في المزامنة
class SyncConflict {
  final DateTime localTime;
  final DateTime cloudTime;

  SyncConflict({
    required this.localTime,
    required this.cloudTime,
  });
}

class SyncService {
  // ========== المفاتيح ==========
  static const String _keyLastSyncTime = 'sync_last_time';
  static const String _keyLastUpload = 'sync_last_upload';
  static const String _keyLastDownload = 'sync_last_download';
  static const String _keyLastLocalChange = 'sync_last_local_change';
  static const String _keyHasPendingChanges = 'sync_has_pending';

  static const Duration _autoSyncThreshold = Duration(minutes: 5);

  // ========== الحالة ==========
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

  // ========== التهيئة ==========
  static Future<void> init() async {
    DatabaseHelper.onDataChanged = _onLocalDataChanged;

    Future.delayed(const Duration(seconds: 3), () {
      initialSync();
    });

    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(
      _autoSyncThreshold,
      (_) => silentSync(),
    );

    debugPrint('✅ [Sync] Initialized');
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

  // ========== عند تغيير البيانات محلياً ==========
  static void _onLocalDataChanged() {
    _saveLastLocalChange(DateTime.now());
    _saveHasPendingChanges(true);

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 5), () {
      silentSync();
    });
  }

  // ========== المزامنة عند العودة من الخلفية ==========
  static Future<void> checkAndSyncIfNeeded() async {
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

  // ========== مزامنة صامتة ==========
  static Future<void> silentSync() async {
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

  // ========== مزامنة أولية ==========
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

    return _runSync(silent: false);
  }

  // ========== مزامنة يدوية ==========
  static Future<SyncResult> manualSync() async {
    if (!GDriveService.isSignedIn) {
      final err = await GDriveService.signInWithError();
      if (err != null) {
        return SyncResult(success: false, message: err);
      }
    }

    return _runSync(silent: false);
  }

  // ========== دالة موحدة ==========
  static Future<SyncResult> _runSync({required bool silent}) async {
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
      final future = _performSync(silent: silent);
      _currentSyncFuture = future;
      final result = await future;
      return result;
    } finally {
      _isSyncing = false;
      _currentSyncFuture = null;
    }
  }

  // ========== المزامنة الفعلية ==========
  static Future<SyncResult> _performSync({required bool silent}) async {
    if (!silent) _setStatus(SyncStatus.syncing);

    try {
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

      final conflict = hasLocalChanges && hasCloudChanges;

      int addedCustomers = 0;
      int addedTransactions = 0;
      int updatedCustomers = 0;

      // نزّل ودمج
      if (hasCloudChanges && cloudData != null) {
        if (!silent) _setStatus(SyncStatus.downloading);
        final result = await _mergeCloudData(cloudData);
        addedCustomers = result['customers'] ?? 0;
        addedTransactions = result['transactions'] ?? 0;
        updatedCustomers = result['updated'] ?? 0;
      }

      // ارفع الحالة الحالية
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

      // تحديث وقت المزامنة
      final now = DateTime.now();
      await prefs.setString(_keyLastSyncTime, now.toIso8601String());
      await prefs.setString(_keyLastUpload, now.toIso8601String());
      if (hasCloudChanges) {
        await prefs.setString(_keyLastDownload, now.toIso8601String());
      }
      await _saveHasPendingChanges(false);

      if (conflict) {
        _lastConflict = SyncConflict(
          localTime: lastLocal ?? DateTime.now(),
          cloudTime: cloudModified ?? DateTime.now(),
        );
      }

      if (!silent) _setStatus(SyncStatus.idle);

      if (!silent) {
        await LoggerService.logSyncSuccess(
          transactionsAdded: addedTransactions,
          customersAdded: addedCustomers,
          customersUpdated: updatedCustomers,
          hasConflict: conflict,
        );
      }

      final finalResult = SyncResult(
        success: true,
        message: conflict
            ? 'تمت المزامنة (مع دمج تعارض)'
            : 'تمت المزامنة بنجاح',
        customersAdded: addedCustomers,
        transactionsAdded: addedTransactions,
        customersUpdated: updatedCustomers,
        hasConflict: conflict,
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

      final errResult = SyncResult(
        success: false,
        message: 'فشل المزامنة: $e',
      );

      if (!_resultController.isClosed) {
        _resultController.add(errResult);
      }

      return errResult;
    }
  }

  // ========== دمج البيانات السحابية (مُحسّن) ==========
  static Future<Map<String, int>> _mergeCloudData(
      Map<String, dynamic> cloudData) async {
    final db = DatabaseHelper.instance;
    int addedCustomers = 0;
    int addedTransactions = 0;
    int updatedCustomers = 0;

    try {
      final customers = (cloudData['customers'] as List?) ?? [];
      final transactions = (cloudData['transactions'] as List?) ?? [];
      final usedCodes = (cloudData['used_codes'] as List?) ?? [];

      // 1. الرموز
      for (final uc in usedCodes) {
        final code = uc['code'] as String?;
        final type = uc['type'] as String?;
        if (code == null || type == null) continue;

        final exists = await db.codeExists(code);
        if (!exists) {
          await db.addUsedCode(code: code, type: type);
        }
      }

      // 2. العملاء (مع تحديث البيانات الموجودة)
      final Map<int, int> idMap = {};

      for (final c in customers) {
        final cloudId = c['id'] as int?;
        if (cloudId == null) continue;

        final name = c['name'] as String? ?? '';
        final createdAt = c['created_at'] as String? ?? '';

        // البحث عن عميل بنفس الاسم + التاريخ
        final existingId =
            await db.findCustomerIdByNameAndDate(name, createdAt);

        if (existingId != null) {
          idMap[cloudId] = existingId;

          // 🆕 تحديث بيانات العميل (بما فيها max_balance و is_active)
          final cloudMaxBalance = c['max_balance'];
          final cloudIsActive = c['is_active'];
          final cloudPhone = c['phone'];
          final cloudCategory = c['category'];
          final cloudAccountType = c['account_type'];
          final cloudNote = c['note'];

          final updateData = <String, dynamic>{};
          if (cloudMaxBalance != null) {
            updateData['max_balance'] = cloudMaxBalance;
          }
          if (cloudIsActive != null) {
            updateData['is_active'] = cloudIsActive;
          }
          if (cloudPhone != null) {
            updateData['phone'] = cloudPhone;
          }
          if (cloudCategory != null) {
            updateData['category'] = cloudCategory;
          }
          if (cloudAccountType != null) {
            updateData['account_type'] = cloudAccountType;
          }
          if (cloudNote != null) {
            updateData['note'] = cloudNote;
          }

          if (updateData.isNotEmpty) {
            final updated = await db.updateCustomerFields(
              existingId,
              updateData,
            );
            if (updated > 0) updatedCustomers++;
          }
        } else {
          // عميل جديد
          final newMap = Map<String, dynamic>.from(c);
          newMap.remove('id');
          final newId = await db.insertCustomerRaw(newMap);
          idMap[cloudId] = newId;
          addedCustomers++;
        }
      }

      // 3. المعاملات
      for (final t in transactions) {
        final cloudCustomerId = t['customer_id'] as int?;
        if (cloudCustomerId == null) continue;

        final localCustomerId = idMap[cloudCustomerId];
        if (localCustomerId == null) continue;

        final amount = (t['amount'] as num?)?.toDouble() ?? 0;
        final type = t['type'] as String? ?? 'debt';
        final createdAt = t['created_at'] as String? ?? '';

        final exists = await db.transactionExists(
          customerId: localCustomerId,
          amount: amount,
          type: type,
          createdAt: createdAt,
        );

        if (!exists) {
          final newMap = Map<String, dynamic>.from(t);
          newMap.remove('id');
          newMap['customer_id'] = localCustomerId;
          await db.insertTransactionRaw(newMap);
          addedTransactions++;
        }
      }

      debugPrint(
          '✅ [Sync] Merged: +$addedCustomers customers, ~$updatedCustomers updated, +$addedTransactions transactions');
    } catch (e) {
      debugPrint('❌ [Sync] Merge error: $e');
    }

    return {
      'customers': addedCustomers,
      'transactions': addedTransactions,
      'updated': updatedCustomers,
    };
  }

  // ========== رفع الحالة الحالية ==========
  static Future<bool> _uploadCurrentState() async {
    try {
      final db = DatabaseHelper.instance;
      final customers = await db.allCustomersRaw();
      final transactions = await db.allTransactionsRaw();
      final usedCodes = await db.allUsedCodesRaw();

      final data = {
        'app': 'debt_voice_app',
        'version': 2,
        'created_at': DateTime.now().toIso8601String(),
        'customers': customers,
        'transactions': transactions,
        'used_codes': usedCodes,
      };

      return await GDriveService.uploadSyncFile(data);
    } catch (e) {
      debugPrint('❌ [Sync] Upload state error: $e');
      return false;
    }
  }

  // ========== أدوات ==========
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
