import 'package:speech_to_text/speech_to_text.dart' as stt;

class SpeechService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _available = false;
  String _locale = 'ar_YE';

  bool get isListening => _speech.isListening;
  bool get isAvailable => _available;

  void setLocale(String loc) => _locale = loc;

  Future<bool> init() async {
    if (_available) return true;
    _available = await _speech.initialize(
      onError: (e) => print('STT Error: $e'),
      onStatus: (s) => print('STT Status: $s'),
    );
    return _available;
  }

  Future<void> listen({
    required void Function(String text, bool isFinal) onResult,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (!_available) await init();
    await _speech.listen(
      localeId: _locale,
      listenFor: timeout,
      pauseFor: const Duration(seconds: 3),
      partialResults: true,
      onResult: (r) => onResult(r.recognizedWords, r.finalResult),
    );
  }

  Future<void> stop() async => _speech.stop();
  Future<void> cancel() async => _speech.cancel();
}
