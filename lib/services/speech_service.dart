import 'package:speech_to_text/speech_to_text.dart' as stt;

class SpeechService {
  static final stt.SpeechToText _speech = stt.SpeechToText();
  static bool _initialized = false;

  /// تهيئة خدمة الصوت
  static Future<bool> init() async {
    if (_initialized) return true;
    try {
      _initialized = await _speech.initialize(
        onError: (e) => print('STT Error: $e'),
        onStatus: (s) => print('STT Status: $s'),
      );
      return _initialized;
    } catch (e) {
      print('STT Init Error: $e');
      return false;
    }
  }

  /// بدء الاستماع
  static Future<void> listen({
    required void Function(String text, bool isFinal) onResult,
    String localeId = 'ar_YE',
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (!_initialized) await init();
    await _speech.listen(
      localeId: localeId,
      listenFor: timeout,
      pauseFor: const Duration(seconds: 3),
      partialResults: true,
      onResult: (r) {
        onResult(r.recognizedWords, r.finalResult);
      },
    );
  }

  /// إيقاف الاستماع
  static Future<void> stop() => _speech.stop();
  static Future<void> cancel() => _speech.cancel();

  static bool get isListening => _speech.isListening;
}
