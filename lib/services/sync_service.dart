import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../db/database_helper.dart';
import 'gdrive_service.dart';

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
  final bool hasConflict;
  final DateTime? timestamp;

  SyncResult({
    required this.success,
    required this.message,
    this.customersAdded = 0,
    this.transactionsAdded = 0,
    this.hasConflict = false,
    this.timestamp,
  });
}

/// تعارض في المزامنة
class SyncConflict {
  final DateTime localTime;
  final DateTime cloudTime;
  final int localCustomers;
  final int localTransactions;
  final int cloudCustomers;
  final int cloudTransactions;

  SyncConflict({
    required this.localTime,
    required this.cloudTime,
    required this.localCustomers,
    required this.localTransactions,
    required this.cloudCustomers,
    required this.cloudTransactions,
  });
}

class SyncService {
  // ========== المفاتيح في SharedPreferences ==========
  static const String _keyLastSyncTime = 'sync_last_time';
  static const String _keyLastUpload = 'sync_last_upload';
  static const String _keyLastDownload = 'sync_last_download';
  static const String _keyLastLocalChange = 'sync_last_local_change';
  static const String _keyHasPendingChanges = 'sync_has_pending';

  // ========== الحالة ==========
  static SyncStatus _status = SyncStatus.idle;
  static SyncStatus get status => _status;

  static Timer? _debounceTimer;
  static Timer? _periodicTimer;
  static bool _isSyncing = false;

  /// Stream لإشعار الواجهة بالتغييرات
  static final _statusController = StreamController<SyncStatus>.broadcast();
  static Stream<SyncStatus> get statusStream => _statusController.stream;

  /// آخر تعارض
  static SyncConflict? _lastConflict;
  static SyncConflict? get lastConflict => _lastConflict;

  // ========== التهيئة ==========
  /// يُستدعى من main.dart عند بدء التطبيق
  static Future<void> init() async {
    // ربط callback التغييرات في قاعدة البيانات
    DatabaseHelper.onDataChanged = _onLocalDataChanged;

    // مزامنة أولية (بعد تأخير بسيط)
    Future.delayed(const Duration(seconds: 3), () {
      initialSync();
    });

    // مزامنة دورية كل 5 دقائق
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => silentSync(),
    );

    debugPrint('✅ [Sync] Initialized');
  }

  /// إيقاف المزامنة (عند الخروج)
  static void dispose() {
    _debounceTimer?.cancel();
    _periodicTimer?.cancel();
    _statusController.close();
  }

  // ========== الإشعارات ==========
  static void _setStatus(SyncStatus s) {
    _status = s;
    if (!_statusController.isClosed) {
      _statusController.add(s);
    }
  }

  // ========== عند تغيير البيانات محلياً ==========
  static void _onLocalDataChanged() {
    // حفظ وقت آخر تغيير محلي
    _saveLastLocalChange(DateTime.now());
    _saveHasPendingChanges(true);

    // رفع تلقائي بعد 5 ثوانٍ (debounce)
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 5), () {
      silentSync();
    });
  }

  // ========== مزامنة صامتة (تلقائية) ==========
  /// لا تُظهر رسائل، تُنفَّذ في الخلفية
  static Future<void> silentSync() async {
    if (_isSyncing) return;
    if (!GDriveService.isSignedIn) return;

    try {
      _isSyncing = true;
      await _performSync(silent: true);
    } catch (e) {
      debugPrint('❌ [Sync] Silent error: $e');
    } finally {
      _isSyncing = false;
    }
  }

  // ========== مزامنة أولية (عند بدء التطبيق) ==========
  static Future<SyncResult> initialSync() async {
    if (!GDriveService.isSignedIn) {
      // محاولة silent sign-in
      await GDriveService.trySilentSignIn();
    }

    if (!GDriveService.isSignedIn) {
      return SyncResult(
        success: false,
        message: 'غير متصل بـ Google Drive',
      );
    }

    return _performSync(silent: false);
  }

  // ========== مزامنة يدوية ==========
  static Future<SyncResult> manualSync() async {
    if (!GDriveService.isSignedIn) {
      final err = await GDriveService.signInWithError();
      if (err != null) {
        return SyncResult(success: false, message: err);
      }
    }

    return _performSync(silent: false);
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

      // 1. جلب وقت آخر تعديل لملف Drive
      final cloudModified = await GDriveService.getSyncFileModifiedTime();

      // 2. تحميل البيانات من Drive
      final cloudData = await GDriveService.downloadSyncFile();

      // 3. حساب الحالة
      final hasLocalChanges =
          lastLocal != null && (lastSync == null || lastLocal.isAfter(lastSync));
      final hasCloudChanges = cloudModified != null &&
          (lastSync == null || cloudModified.isAfter(lastSync));

      // 4. إذا لا يوجد أي تغيير
      if (!hasLocalChanges && !hasCloudChanges) {
        if (!silent) _setStatus(SyncStatus.idle);
        return SyncResult(
          success: true,
          message: 'لا توجد تغييرات',
          timestamp: lastSync,
        );
      }

      // 5. إذا كان هناك تعارض (كلاهما تغير)
      final conflict = hasLocalChanges && hasCloudChanges;

      int addedCustomers = 0;
      int addedTransactions = 0;

      if (hasCloudChanges && cloudData != null) {
        // نزّل ودمج
        if (!silent) _setStatus(SyncStatus.downloading);
        final result = await _mergeCloudData(cloudData);
        addedCustomers = result['customers'] ?? 0;
        addedTransactions = result['transactions'] ?? 0;
      }

      // 6. ارفع الحالة الحالية إلى Drive (سواء كان هناك تغيير محلي أو بعد الدمج)
      if (hasLocalChanges || hasCloudChanges) {
        if (!silent) _setStatus(SyncStatus.uploading);
        await _uploadCurrentState();
      }

      // 7. تحديث آخر مزامنة
      final now = DateTime.now();
      await prefs.setString(_keyLastSyncTime, now.toIso8601String());
      await prefs.setString(_keyLastUpload, now.toIso8601String());
      if (hasCloudChanges) {
        await prefs.setString(_keyLastDownload, now.toIso8601String());
      }
      await _saveHasPendingChanges(false);

      // 8. إذا كان هناك تعارض، نخزنه
      if (conflict) {
        _lastConflict = SyncConflict(
          localTime: lastLocal ?? DateTime.now(),
          cloudTime: cloudModified ?? DateTime.now(),
          localCustomers: 0,
          localTransactions: 0,
          cloudCustomers: 0,
          cloudTransactions: 0,
        );
      }

      if (!silent) _setStatus(SyncStatus.idle);

      return SyncResult(
        success: true,
        message: conflict
            ? 'تمت المزامنة (مع دمج تعارض)'
            : 'تمت المزامنة بنجاح',
        customersAdded: addedCustomers,
        transactionsAdded: addedTransactions,
        hasConflict: conflict,
        timestamp: now,
      );
    } catch (e) {
      debugPrint('❌ [Sync] Error: $e');
      if (!silent) _setStatus(SyncStatus.error);
      return SyncResult(
        success: false,
        message: 'فشل المزامنة: $e',
      );
    }
  }

  // ========== دمج البيانات السحابية مع المحلية ==========
  static Future<Map<String, int>> _mergeCloudData(
      Map<String, dynamic> cloudData) async {
    final db = DatabaseHelper.instance;
    int addedCustomers = 0;
    int addedTransactions = 0;

    try {
      final customers = (cloudData['customers'] as List?) ?? [];
      final transactions = (cloudData['transactions'] as List?) ?? [];

      // ===== دمج الزبائن =====
      // خريطة: cloudId → localId
      final Map<int, int> idMap = {};

      for (final c in customers) {
        final cloudId = c['id'] as int?;
        if (cloudId == null) continue;

        final name = c['name'] as String? ?? '';
        final createdAt = c['created_at'] as String? ?? '';

        // ابحث عن زبون بنفس الاسم والتاريخ
        final existingId =
            await db.findCustomerIdByNameAndDate(name, createdAt);

        if (existingId != null) {
          idMap[cloudId] = existingId;
        } else {
          // أضف زبون جديد (بدون id من السحابة لتفادي التعارض)
          final newMap = Map<String, dynamic>.from(c);
          newMap.remove('id');
          final newId = await db.insertCustomerRaw(newMap);
          idMap[cloudId] = newId;
          addedCustomers++;
        }
      }

      // ===== دمج المعاملات =====
      for (final t in transactions) {
        final cloudCustomerId = t['customer_id'] as int?;
        if (cloudCustomerId == null) continue;

        final localCustomerId = idMap[cloudCustomerId];
        if (localCustomerId == null) continue;

        final amount = (t['amount'] as num?)?.toDouble() ?? 0;
        final type = t['type'] as String? ?? 'debt';
        final createdAt = t['created_at'] as String? ?? '';

        // تحقق من وجود المعاملة
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
          '✅ [Sync] Merged: +$addedCustomers customers, +$addedTransactions transactions');
    } catch (e) {
      debugPrint('❌ [Sync] Merge error: $e');
    }

    return {
      'customers': addedCustomers,
      'transactions': addedTransactions,
    };
  }

  // ========== رفع الحالة الحالية إلى Drive ==========
  static Future<bool> _uploadCurrentState() async {
    try {
      final db = DatabaseHelper.instance;
      final customers = await db.allCustomersRaw();
      final transactions = await db.allTransactionsRaw();

      final data = {
        'app': 'debt_voice_app',
        'version': 1,
        'created_at': DateTime.now().toIso8601String(),
        'customers': customers,
        'transactions': transactions,
      };

      return await GDriveService.uploadSyncFile(data);
    } catch (e) {
      debugPrint('❌ [Sync] Upload state error: $e');
      return false;
    }
  }

  // ========== أدوات مساعدة ==========
  static Future<void> _saveLastLocalChange(DateTime dt) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastLocalChange, dt.toIso8601String());
  }

  static Future<void> _saveHasPendingChanges(bool has) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyHasPendingChanges, has);
  }

  /// جلب آخر وقت مزامنة
  static Future<DateTime?> getLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_keyLastSyncTime);
    return s != null ? DateTime.parse(s) : null;
  }

  /// جلب آخر وقت رفع
  static Future<DateTime?> getLastUploadTime() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_keyLastUpload);
    return s != null ? DateTime.parse(s) : null;
  }

  /// جلب آخر وقت تنزيل
  static Future<DateTime?> getLastDownloadTime() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_keyLastDownload);
    return s != null ? DateTime.parse(s) : null;
  }

  /// هل هناك تغييرات معلقة لم تُرفع بعد؟
  static Future<bool> hasPendingChanges() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyHasPendingChanges) ?? false;
  }
}
