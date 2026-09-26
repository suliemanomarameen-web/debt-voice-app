import 'package:speech_to_text/speech_to_text.dart' as stt;

class SpeechService {
  static final stt.SpeechToText _speech = stt.SpeechToText();
  static bool _initialized = false;
  static bool _listening = false;

  /// حالة التهيئة العامة (يقرأها الزر العائم)
  static bool get isReady => _initialized;
  static bool get isListening => _listening;

  /// تهيئة محرك الصوت (تُستدعى من التطبيق الرئيسي)
  static Future<bool> init() async {
    if (_initialized) return true;
    try {
      _initialized = await _speech.initialize(
        onError: (e) {
          print('STT Error: $e');
          _listening = false;
        },
        onStatus: (s) {
          print('STT Status: $s');
          _listening = s == 'listening';
        },
      );
      return _initialized;
    } catch (e) {
      print('STT Init error: $e');
      return false;
    }
  }

  /// بدء الاستماع
  static Future<void> listen({
    required void Function(String text, bool isFinal) onResult,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (!_initialized) await init();
    _listening = true;
    await _speech.listen(
      localeId: 'ar_YE',
      listenFor: timeout,
      pauseFor: const Duration(seconds: 3),
      partialResults: true,
      onResult: (r) => onResult(r.recognizedWords, r.finalResult),
    );
  }

  static Future<void> stop() async {
    _listening = false;
    await _speech.stop();
  }

  static Future<void> cancel() async {
    _listening = false;
    await _speech.cancel();
  }
}
