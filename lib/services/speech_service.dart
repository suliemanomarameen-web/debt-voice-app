import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class SpeechService {
  // instance واحد يُشارَك بين التطبيق الرئيسي والنافذة العائمة
  static final SpeechService _instance = SpeechService._internal();
  factory SpeechService() => _instance;
  SpeechService._internal();

  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _available = false;
  bool _initializing = false;
  String _locale = 'ar_YE';

  /// 🆕 آخر نص تم التعرف عليه (لاستخدامه في الإيقاف التلقائي)
  String _lastText = '';

  bool get isListening => _speech.isListening;
  bool get isAvailable => _available;
  bool get isReady => _available;

  /// 🆕 آخر نص مكتشف
  String get lastText => _lastText;

  void setLocale(String loc) => _locale = loc;

  Future<bool> init() async {
    if (_available) return true;

    // إذا كانت هناك تهيئة جارية، انتظر حتى تنتهي
    if (_initializing) {
      for (int i = 0; i < 50; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        if (_available) return true;
        if (!_initializing) break;
      }
      return _available;
    }

    _initializing = true;
    try {
      _available = await _speech.initialize(
        onError: (e) => debugPrint('STT Error: $e'),
        onStatus: (s) => debugPrint('STT Status: $s'),
      );
      debugPrint('✅ [SpeechService] initialized=$_available locale=$_locale');
    } catch (e) {
      debugPrint('❌ STT Init error: $e');
      _available = false;
    } finally {
      // ✅ إعادة تصفير دائمًا — حتى لو حدث استثناء
      _initializing = false;
    }
    return _available;
  }

  /// إعادة تعيين الحالة (للاستخدام عند تغيير المحرك أو إعادة المحاولة)
  Future<void> reset() async {
    try {
      await _speech.cancel();
    } catch (_) {}
    _available = false;
    _initializing = false;
    _lastText = '';
  }

  Future<void> listen({
    required void Function(String text, bool isFinal) onResult,
    Duration listenFor = const Duration(seconds: 30),
    Duration pauseFor = const Duration(seconds: 5),
  }) async {
    if (!_available) {
      final ok = await init();
      if (!ok) {
        debugPrint('⚠️ [SpeechService] not available — cannot listen');
        return;
      }
    }

    _lastText = '';

    // ننتظر قليلًا للتأكد من أن المحرك جاهز
    await Future.delayed(const Duration(milliseconds: 150));

    try {
      await _speech.listen(
        localeId: _locale,
        listenFor: listenFor,
        pauseFor: pauseFor,
        partialResults: true,
        onResult: (r) {
          final text = r.recognizedWords.trim();
          _lastText = text;
          onResult(text, r.finalResult);
        },
        onSoundLevelChange: (level) {
          // لا نستخدمه حاليًا — لكنه متاح لمستقبل
        },
      );
    } catch (e) {
      debugPrint('❌ [SpeechService] listen error: $e');
      _available = false;
      _initializing = false;
    }
  }

  Future<void> stop() async {
    try {
      await _speech.stop();
    } catch (e) {
      debugPrint('⚠️ [SpeechService] stop error: $e');
    }
  }

  Future<void> cancel() async {
    try {
      await _speech.cancel();
    } catch (e) {
      debugPrint('⚠️ [SpeechService] cancel error: $e');
    }
    _lastText = '';
  }
}

// Speech Service v1: النسخة الأساسية (STT بسيط)
// Speech Service v2: تحسين التعرف الصوتي
// - إصلاح تعليق _initializing عند فشل التهيئة (try/finally)
// - زيادة pauseFor من 3 إلى 5 ثوانٍ (صبر أطول على الصمت)
// - زيادة listenFor من 15 إلى 30 ثانية (كلام أطول)
// - إضافة _lastText لتتبع آخر نص
// - إضافة reset() للحالات العالقة
