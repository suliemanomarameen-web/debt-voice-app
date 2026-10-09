import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// خدمة تسجيل الصوت وإعادة تشغيله
/// - تُسجّل الصوت إلى ملف .m4a
/// - تُشغّل التسجيلات المحفوظة
/// - تدير التنظيف التلقائي
class AudioRecorderService {
  static final AudioRecorderService _instance =
      AudioRecorderService._internal();
  factory AudioRecorderService() => _instance;
  AudioRecorderService._internal();

  // ========== المسجّل ==========
  final AudioRecorder _recorder = AudioRecorder();

  // ========== المشغّل ==========
  final AudioPlayer _player = AudioPlayer();

  // ========== الحالة ==========
  bool _isRecording = false;
  String? _currentRecordingPath;
  DateTime? _recordingStartTime;

  // ========== مفاتيح الإعدادات ==========
  static const String _keyRetentionDays = 'voice_retention_days';
  static const int _defaultRetentionDays = 30; // أيام
  static const String _folderName = 'voice_recordings';

  // ========== getters ==========
  bool get isRecording => _isRecording;
  String? get currentRecordingPath => _currentRecordingPath;
  Duration get recordingDuration {
    if (_recordingStartTime == null) return Duration.zero;
    return DateTime.now().difference(_recordingStartTime!);
  }

  // ============================================================
  // ============ 🆕 التهيئة ============================
  // ============================================================
  static Future<void> init() async {
    try {
      // إنشاء المجلد
      final dir = await _getRecordingsDir();
      debugPrint('✅ [Audio] Recordings dir: ${dir.path}');
    } catch (e) {
      debugPrint('❌ [Audio] init error: $e');
    }
  }

  /// 🆕 جلب مجلد التسجيلات (وإنشاؤه إذا لم يوجد)
  static Future<Directory> _getRecordingsDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/$_folderName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  // ============================================================
  // ============ 🆕 بدء التسجيل ====================
  // ============================================================

  /// يبدأ التسجيل. يعيد `true` إذا نجح.
  Future<bool> startRecording() async {
    try {
      // إذا كان هناك تسجيل جارٍ → أوقفه أولاً
      if (_isRecording) {
        await stopRecording();
      }

      // التحقق من الإذن
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        debugPrint('❌ [Audio] No microphone permission');
        return false;
      }

      // تجهيز مسار الملف
      final dir = await _getRecordingsDir();
      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final path = '${dir.path}/rec_$timestamp.m4a';

      // بدء التسجيل
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 44100,
        ),
        path: path,
      );

      _isRecording = true;
      _currentRecordingPath = path;
      _recordingStartTime = DateTime.now();

      debugPrint('🎙️ [Audio] Recording started: $path');
      return true;
    } catch (e) {
      debugPrint('❌ [Audio] startRecording error: $e');
      _isRecording = false;
      _currentRecordingPath = null;
      _recordingStartTime = null;
      return false;
    }
  }

  // ============================================================
  // ============ 🆕 إيقاف التسجيل ====================
  // ============================================================

  /// يوقف التسجيل ويعيد مسار الملف (أو `null` عند الفشل)
  Future<String?> stopRecording() async {
    try {
      if (!_isRecording) return null;

      final path = await _recorder.stop();
      _isRecording = false;
      _recordingStartTime = null;

      final resultPath = path ?? _currentRecordingPath;
      _currentRecordingPath = null;

      if (resultPath != null) {
        final file = File(resultPath);
        if (await file.exists()) {
          final size = await file.length();
          debugPrint(
              '✅ [Audio] Recording stopped: $resultPath (${_formatBytes(size)})');

          // إذا كان الملف صغيراً جداً (< 2KB) → احذفه
          if (size < 2048) {
            debugPrint('⚠️ [Audio] File too small, deleting');
            await file.delete();
            return null;
          }

          return resultPath;
        }
      }

      return null;
    } catch (e) {
      debugPrint('❌ [Audio] stopRecording error: $e');
      _isRecording = false;
      _recordingStartTime = null;
      _currentRecordingPath = null;
      return null;
    }
  }

  /// إلغاء التسجيل (بدون حفظ)
  Future<void> cancelRecording() async {
    try {
      if (_isRecording) {
        final path = await _recorder.stop();
        _isRecording = false;
        _recordingStartTime = null;
        _currentRecordingPath = null;

        if (path != null) {
          final file = File(path);
          if (await file.exists()) {
            await file.delete();
            debugPrint('🗑️ [Audio] Recording cancelled & deleted');
          }
        }
      }
    } catch (e) {
      debugPrint('❌ [Audio] cancelRecording error: $e');
    }
  }

  // ============================================================
  // ============ 🆕 تشغيل تسجيل ====================
  // ============================================================

  /// يبدأ تشغيل ملف صوتي. يعيد `true` إذا نجح.
  Future<bool> play(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint('❌ [Audio] File not found: $filePath');
        return false;
      }

      // إيقاف أي تشغيل جارٍ
      await _player.stop();

      await _player.play(DeviceFileSource(filePath));
      debugPrint('▶️ [Audio] Playing: $filePath');
      return true;
    } catch (e) {
      debugPrint('❌ [Audio] play error: $e');
      return false;
    }
  }

  /// إيقاف التشغيل
  Future<void> stopPlayback() async {
    try {
      await _player.stop();
    } catch (_) {}
  }

  /// إيقاف كل شيء (تسجيل + تشغيل)
  Future<void> stopAll() async {
    await stopPlayback();
    if (_isRecording) {
      await stopRecording();
    }
  }

  // ============================================================
  // ============ Stream للتشغيل ====================
  // ============================================================

  /// حالة المشغّل (لتحديث الواجهة)
  Stream<PlayerState> get playerStateStream => _player.onPlayerStateChanged;

  /// موضع التشغيل الحالي
  Stream<Duration> get playerPositionStream => _player.onPositionChanged;

  /// مدة الملف الكامل
  Stream<Duration> get playerDurationStream => _player.onDurationChanged;

  // ============================================================
  // ============ معلومات ملف ====================
  // ============================================================

  /// التحقق من وجود ملف
  static Future<bool> fileExists(String path) async {
    try {
      return await File(path).exists();
    } catch (_) {
      return false;
    }
  }

  /// حجم الملف (بايت)
  static Future<int> getFileSize(String path) async {
    try {
      final f = File(path);
      if (!await f.exists()) return 0;
      return await f.length();
    } catch (_) {
      return 0;
    }
  }

  /// حذف ملف
  static Future<bool> deleteFile(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) {
        await f.delete();
        return true;
      }
    } catch (_) {}
    return false;
  }

  // ============================================================
  // ============ 🆕 التنظيف ====================
  // ============================================================

  /// جلب عدد الأيام المحددة للاحتفاظ (0 = لا تحذف)
  static Future<int> getRetentionDays() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getInt(_keyRetentionDays) ?? _defaultRetentionDays;
  }

  /// تعيين عدد الأيام (0 = لا تحذف)
  static Future<void> setRetentionDays(int days) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setInt(_keyRetentionDays, days);
  }

  /// حذف التسجيلات الأقدم من X يوم
  static Future<int> cleanupOldRecordings() async {
    try {
      final days = await getRetentionDays();
      if (days <= 0) return 0;

      final dir = await _getRecordingsDir();
      final files = await dir.list().toList();

      final cutoff = DateTime.now().subtract(Duration(days: days));
      int deleted = 0;

      for (final f in files) {
        if (f is! File) continue;
        try {
          final stat = await f.stat();
          if (stat.modified.isBefore(cutoff)) {
            await f.delete();
            deleted++;
          }
        } catch (_) {}
      }

      debugPrint('🗑️ [Audio] Cleanup: deleted $deleted files');
      return deleted;
    } catch (e) {
      debugPrint('❌ [Audio] cleanupOldRecordings error: $e');
      return 0;
    }
  }

  /// حذف كل التسجيلات
  static Future<int> deleteAllRecordings() async {
    try {
      final dir = await _getRecordingsDir();
      final files = await dir.list().toList();
      int deleted = 0;
      for (final f in files) {
        if (f is! File) continue;
        try {
          await f.delete();
          deleted++;
        } catch (_) {}
      }
      return deleted;
    } catch (_) {
      return 0;
    }
  }

  /// حجم كل التسجيلات (بايت)
  static Future<int> getTotalSize() async {
    try {
      final dir = await _getRecordingsDir();
      final files = await dir.list().toList();
      int total = 0;
      for (final f in files) {
        if (f is! File) continue;
        try {
          total += await f.length();
        } catch (_) {}
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  /// عدد التسجيلات
  static Future<int> getCount() async {
    try {
      final dir = await _getRecordingsDir();
      final files = await dir.list().toList();
      return files.whereType<File>().length;
    } catch (_) {
      return 0;
    }
  }

  // ============================================================
  // ============ أدوات ====================
  // ============================================================

  /// تنظيف موارد
  Future<void> dispose() async {
    try {
      await _player.dispose();
      await _recorder.dispose();
    } catch (_) {}
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// تحويل بايت إلى نص (للعرض في الواجهة)
  static String formatSize(int bytes) => _formatBytes(bytes);
}