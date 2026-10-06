import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'gdrive_service.dart';

/// تكرار النسخ الاحتياطي
enum BackupFrequency {
  daily,
  weekly,
  monthly,
  yearly,
}

/// خدمة النسخ الاحتياطي التلقائي على Google Drive
class CloudBackupService {
  // ========== المفاتيح ==========
  static const String _keyEnabled = 'cloud_backup_enabled';
  static const String _keyFrequency = 'cloud_backup_frequency';
  static const String _keyMaxBackups = 'cloud_backup_max'; // -1 = غير نهائي
  static const String _keyLastBackup = 'cloud_backup_last_time';

  // ========== الحالة ==========
  static Timer? _checkTimer;
  static bool _isRunning = false;

  /// يُستدعى عند نجاح أو فشل النسخ (لإشعار الواجهة)
  static void Function(bool success, String message)? onBackupResult;

  // ========== التهيئة ==========
  static Future<void> init() async {
    // ابدأ فحصاً دورياً كل 30 دقيقة
    _startPeriodicCheck();

    // فحص أولي بعد 10 ثوانٍ من فتح التطبيق
    Future.delayed(const Duration(seconds: 10), () {
      checkAndRun();
    });

    debugPrint('✅ [CloudBackup] Initialized');
  }

  static void dispose() {
    _checkTimer?.cancel();
  }

  // ========== الفحص الدوري ==========
  static void _startPeriodicCheck() {
    _checkTimer?.cancel();
    _checkTimer = Timer.periodic(
      const Duration(minutes: 30),
      (_) => checkAndRun(),
    );
  }

  /// فحص ما إذا كان الوقت قد حان للنسخ
  static Future<void> checkAndRun() async {
    if (_isRunning) return;

    final enabled = await isEnabled();
    if (!enabled) return;

    if (!GDriveService.isSignedIn) {
      // محاولة silent sign in
      final ok = await GDriveService.trySilentSignIn();
      if (!ok) return;
    }

    final lastBackup = await getLastBackupTime();
    final freq = await getFrequency();

    if (lastBackup == null) {
      // لم يُنسخ بعد → نفذ الآن
      await _runBackup();
      return;
    }

    final now = DateTime.now();
    final elapsed = now.difference(lastBackup);

    Duration interval;
    switch (freq) {
      case BackupFrequency.daily:
        interval = const Duration(days: 1);
        break;
      case BackupFrequency.weekly:
        interval = const Duration(days: 7);
        break;
      case BackupFrequency.monthly:
        interval = const Duration(days: 30);
        break;
      case BackupFrequency.yearly:
        interval = const Duration(days: 365);
        break;
    }

    if (elapsed >= interval) {
      await _runBackup();
    }
  }

  /// تنفيذ النسخ الآن
  static Future<void> runNow() async {
    if (_isRunning) return;
    await _runBackup();
  }

  static Future<void> _runBackup() async {
    _isRunning = true;
    try {
      debugPrint('🔄 [CloudBackup] Starting backup...');

      final result = await GDriveService.uploadBackup();

      if (result['success'] == true) {
        final now = DateTime.now();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_keyLastBackup, now.toIso8601String());

        // حذف النسخ القديمة إذا لزم
        await _trimOldBackups();

        debugPrint('✅ [CloudBackup] Backup successful');
        onBackupResult?.call(true, 'تم النسخ التلقائي بنجاح');
      } else {
        debugPrint('❌ [CloudBackup] Failed: ${result['message']}');
        onBackupResult?.call(false, result['message'] ?? 'فشل النسخ');
      }
    } catch (e) {
      debugPrint('❌ [CloudBackup] Error: $e');
      onBackupResult?.call(false, 'خطأ: $e');
    } finally {
      _isRunning = false;
    }
  }

  // ========== حذف النسخ القديمة ==========
  static Future<void> _trimOldBackups() async {
    final maxBackups = await getMaxBackups();
    if (maxBackups < 0) return; // غير نهائي
    if (maxBackups == 0) return; // 0 = احتفظ بالكل (تفسير آخر)

    final backups = await GDriveService.listBackups();
    if (backups.length <= maxBackups) return;

    // النسخ مرتبة من الأحدث للأقدم
    final toDelete = backups.skip(maxBackups);
    for (final b in toDelete) {
      try {
        await GDriveService.deleteBackup(b['id']);
        debugPrint('🗑️ Deleted old backup: ${b['name']}');
      } catch (e) {
        debugPrint('Delete error: $e');
      }
    }
  }

  // ========== الإعدادات ==========
  static Future<bool> isEnabled() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getBool(_keyEnabled) ?? false;
  }

  static Future<void> setEnabled(bool v) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_keyEnabled, v);
    if (v) {
      // عند التفعيل، افحص فوراً
      Future.delayed(const Duration(seconds: 2), () => checkAndRun());
    }
  }

  static Future<BackupFrequency> getFrequency() async {
    final sp = await SharedPreferences.getInstance();
    final s = sp.getString(_keyFrequency) ?? 'daily';
    switch (s) {
      case 'weekly':
        return BackupFrequency.weekly;
      case 'monthly':
        return BackupFrequency.monthly;
      case 'yearly':
        return BackupFrequency.yearly;
      case 'daily':
      default:
        return BackupFrequency.daily;
    }
  }

  static Future<void> setFrequency(BackupFrequency f) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_keyFrequency, f.name);
  }

  /// -1 = غير نهائي، وإلا عدد النسخ
  static Future<int> getMaxBackups() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getInt(_keyMaxBackups) ?? 10;
  }

  static Future<void> setMaxBackups(int v) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setInt(_keyMaxBackups, v);
  }

  static Future<DateTime?> getLastBackupTime() async {
    final sp = await SharedPreferences.getInstance();
    final s = sp.getString(_keyLastBackup);
    return s != null ? DateTime.parse(s) : null;
  }

  // ========== أدوات مساعدة ==========
  static String frequencyLabel(BackupFrequency f) {
    switch (f) {
      case BackupFrequency.daily:
        return 'يومي';
      case BackupFrequency.weekly:
        return 'أسبوعي';
      case BackupFrequency.monthly:
        return 'شهري';
      case BackupFrequency.yearly:
        return 'سنوي';
    }
  }

  static String describeMaxBackups(int max) {
    if (max < 0) return 'غير نهائي';
    return 'آخر $max نسخة';
  }
}
