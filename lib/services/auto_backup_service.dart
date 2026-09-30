import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'backup_service.dart';

/// مهام النسخ الاحتياطي التلقائي
const String taskAutoBackup = 'debt_auto_backup';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      if (task == taskAutoBackup) {
        // نسخة احتياطية
        final result = await BackupService.createBackup();
        if (result.success) {
          debugPrint('✅ Auto backup created: ${result.filePath}');
          // احذف النسخ القديمة
          await AutoBackupService.trimOldBackups();
        } else {
          debugPrint('❌ Auto backup failed: ${result.message}');
        }
      }
      return true;
    } catch (e) {
      debugPrint('Auto backup error: $e');
      return false;
    }
  });
}

class AutoBackupService {
  static const _keyEnabled = 'auto_backup_enabled';
  static const _keyFrequency = 'auto_backup_frequency'; // daily/weekly/monthly
  static const _maxBackups = 10;

  // ========== إعدادات ==========
  static Future<bool> isEnabled() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getBool(_keyEnabled) ?? false;
  }

  static Future<void> setEnabled(bool value) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_keyEnabled, value);
    if (value) {
      await _schedule();
    } else {
      await cancel();
    }
  }

  static Future<String> getFrequency() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getString(_keyFrequency) ?? 'daily';
  }

  static Future<void> setFrequency(String freq) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_keyFrequency, freq);
    if (await isEnabled()) {
      await _schedule();
    }
  }

  // ========== التهيئة ==========
  static Future<void> init() async {
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: false,
    );

    if (await isEnabled()) {
      await _schedule();
    }
  }

  // ========== الجدولة ==========
  static Future<void> _schedule() async {
    await cancel();

    final freq = await getFrequency();
    Duration interval;
    switch (freq) {
      case 'weekly':
        interval = const Duration(days: 7);
        break;
      case 'monthly':
        interval = const Duration(days: 30);
        break;
      case 'daily':
      default:
        interval = const Duration(hours: 24);
        break;
    }

    await Workmanager().registerPeriodicTask(
      taskAutoBackup,
      taskAutoBackup,
      frequency: interval,
      initialDelay: const Duration(minutes: 15),
      constraints: Constraints(
        networkType: NetworkType.notRequired,
        requiresBatteryNotLow: false,
        requiresCharging: false,
        requiresDeviceIdle: false,
        requiresStorageNotLow: false,
      ),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
    );

    debugPrint('Auto backup scheduled: $freq');
  }

  static Future<void> cancel() async {
    try {
      await Workmanager().cancelByUniqueName(taskAutoBackup);
      debugPrint('Auto backup cancelled');
    } catch (e) {
      debugPrint('Cancel error: $e');
    }
  }

  /// تشغيل يدوي الآن (اختبار)
  static Future<void> runNow() async {
    final result = await BackupService.createBackup();
    if (result.success) {
      await trimOldBackups();
    }
  }

  // ========== الاحتفاظ بآخر 10 نسخ ==========
  static Future<void> trimOldBackups() async {
    try {
      final backups = await BackupService.listBackups();
      if (backups.length <= _maxBackups) return;

      // رتّبت بالفعل من الأحدث للأقدم في listBackups
      final toDelete = backups.skip(_maxBackups);
      for (final file in toDelete) {
        try {
          final f = File(file.path);
          if (await f.exists()) await f.delete();
        } catch (e) {
          debugPrint('Delete old backup error: $e');
        }
      }
      debugPrint('Trimmed ${toDelete.length} old backups');
    } catch (e) {
      debugPrint('Trim error: $e');
    }
  }
}
