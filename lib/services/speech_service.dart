import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'tts_service.dart';

/// Shared speech engine used by VoiceScreen and the floating overlay.
///
/// A single native speech_to_text engine must not deliver callbacks from an
/// older listening session into a newer conversation. Manual stop and cancel
/// are also distinguished from a genuine end-of-speech event.
class SpeechService {
  static final SpeechService _instance = SpeechService._internal();
  factory SpeechService() => _instance;
  SpeechService._internal();

  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _available = false;
  bool _initializing = false;
  String _locale = 'ar_YE';

  String _lastText = '';
  void Function()? _onSilence;
  void Function(String text, bool isFinal)? _onResult;
  bool _finalResultDelivered = false;
  bool _silenceDelivered = false;
  bool _suppressCallbacks = false;
  bool _sessionActive = false;
  bool _engineStarted = false;
  int _generation = 0;
  int _listenRequestGeneration = 0;
  int _lastStartedGeneration = -1;

  bool get isListening => _speech.isListening;
  bool get hasActiveRecognition => _engineStarted && _sessionActive;
  bool get isAvailable => _available;
  bool get isReady => _available;
  String get lastText => _lastText;

  void setLocale(String loc) => _locale = loc;

  void _deliverSilence(int generation) {
    if (generation != _generation ||
        !_sessionActive ||
        _suppressCallbacks ||
        _silenceDelivered ||
        _finalResultDelivered) {
      return;
    }
    _silenceDelivered = true;
    _sessionActive = false;
    final callback = _onSilence;
    _onSilence = null;
    _onResult = null;
    callback?.call();
  }

  void _deliverFinalText(String text, int generation) {
    if (generation != _generation ||
        !_sessionActive ||
        _suppressCallbacks ||
        _finalResultDelivered) {
      return;
    }
    final value = text.trim();
    if (value.isEmpty) {
      _deliverSilence(generation);
      return;
    }
    _lastText = value;
    _finalResultDelivered = true;
    _sessionActive = false;
    final callback = _onResult;
    _onSilence = null;
    _onResult = null;
    callback?.call(value, true);
  }

  Future<bool> init() async {
    if (_available) return true;

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
        onError: (e) {
          debugPrint('STT Error: ${e.errorMsg}');
          // A no-match/timeout is a real empty attempt only after the
          // recognizer entered listening state. Startup errors must not burn
          // one of the user's three dialog attempts.
          if (e.errorMsg == 'error_no_match' ||
              e.errorMsg == 'error_speech_timeout') {
            // The status callback owns end-of-speech delivery. Error callbacks
            // have no session token and can arrive late from a previous owner.
          } else if (e.errorMsg != 'error_client') {
            _available = false;
          }
        },
        onStatus: (status) {
          debugPrint('STT Status: $status');
          // Status notifications are global to the native recognizer and
          // may arrive late after cancel/restart. Confirm the plugin's actual
          // state before attributing a status to the current session.
          if (status == 'listening' &&
              _sessionActive &&
              !_suppressCallbacks &&
              _speech.isListening) {
            _engineStarted = true;
            _lastStartedGeneration = _generation;
          }
          if (status == 'done' || status == 'notListening') {
            if (_suppressCallbacks ||
                !_sessionActive ||
                !_engineStarted ||
                _speech.isListening) {
              return;
            }
            if (_lastText.isEmpty) {
              _deliverSilence(_generation);
            } else {
              _deliverFinalText(_lastText, _generation);
            }
          }
        },
      );

      if (_available) {
        await Future.delayed(const Duration(milliseconds: 250));
      }
      debugPrint('✅ [SpeechService] initialized=$_available locale=$_locale');
    } catch (e) {
      debugPrint('❌ STT Init error: $e');
      _available = false;
    } finally {
      _initializing = false;
    }
    return _available;
  }

  Future<void> reset() async {
    _listenRequestGeneration++;
    _generation++;
    _sessionActive = false;
    _engineStarted = false;
    _suppressCallbacks = true;
    _onSilence = null;
    _onResult = null;
    try {
      await _speech.cancel();
    } catch (_) {}
    _available = false;
    _initializing = false;
    _lastText = '';
  }

  Future<bool> listen({
    required void Function(String text, bool isFinal) onResult,
    void Function()? onSilence,
    Duration listenFor = const Duration(seconds: 30),
    Duration pauseFor = const Duration(seconds: 5),
    @Deprecated('استخدم listenFor بدلًا منه')
    Duration? timeout,
  }) async {
    final requestGeneration = ++_listenRequestGeneration;
    final effectiveListenFor = timeout ?? listenFor;

    // Wait until any prompt/confirmation spoken by the app has fully ended.
    var ttsWaits = 0;
    while (TtsService.isSpeaking && ttsWaits < 100) {
      await Future.delayed(const Duration(milliseconds: 100));
      ttsWaits++;
    }
    if (requestGeneration != _listenRequestGeneration) return false;
    if (TtsService.isSpeaking) {
      debugPrint('⚠️ [SpeechService] skipped listen while TTS is speaking');
      return false;
    }

    if (!_available) {
      final ok = await init();
      if (!ok) {
        debugPrint('⚠️ [SpeechService] not available — cannot listen');
        return false;
      }
    }
    if (requestGeneration != _listenRequestGeneration) return false;

    // The speech_to_text plugin exposes one native recognizer. A new
    // source takes ownership explicitly and cancels any previous session,
    // preventing VoiceScreen and the overlay from listening concurrently.
    if (_sessionActive || _speech.isListening) {
      _generation++;
      _suppressCallbacks = true;
      _sessionActive = false;
      _engineStarted = false;
      _onSilence = null;
      _onResult = null;
      try {
        await _speech.cancel();
      } catch (_) {}
    }

    final generation = ++_generation;
    _lastText = '';
    _onSilence = onSilence;
    _onResult = onResult;
    _finalResultDelivered = false;
    _silenceDelivered = false;
    _suppressCallbacks = false;
    _sessionActive = true;
    _engineStarted = false;

    await Future.delayed(const Duration(milliseconds: 120));
    if (generation != _generation || !_sessionActive) return false;

    try {
      await _speech.listen(
        localeId: _locale,
        listenFor: effectiveListenFor,
        pauseFor: pauseFor,
        partialResults: true,
        onResult: (r) {
          if (generation != _generation ||
              !_sessionActive ||
              _suppressCallbacks) {
            return;
          }
          final text = r.recognizedWords.trim();
          if (text.isNotEmpty) _lastText = text;
          if (r.finalResult) {
            _deliverFinalText(text.isNotEmpty ? text : _lastText, generation);
          } else if (text.isNotEmpty) {
            onResult(text, false);
          }
        },
        onSoundLevelChange: (level) {},
      );
      // Some Android devices return from listen() without opening the native
      // recognizer. Do not convert that startup failure into a silence retry.
      // Wait briefly for the platform's explicit "listening" status.
      // A failed startup is not user silence and must not consume a retry.
      var startupWaits = 0;
      while (generation == _generation &&
          _sessionActive &&
          !_engineStarted &&
          startupWaits < 20) {
        if (_speech.isListening) {
          _engineStarted = true;
          _lastStartedGeneration = generation;
          break;
        }
        await Future.delayed(const Duration(milliseconds: 100));
        startupWaits++;
      }
      if (generation == _generation &&
          _sessionActive &&
          !_engineStarted &&
          _speech.isListening) {
        _engineStarted = true;
        _lastStartedGeneration = generation;
      }
      if (generation == _generation && _sessionActive && !_engineStarted) {
        _sessionActive = false;
        _onSilence = null;
        _onResult = null;
        debugPrint('⚠️ [SpeechService] native recognizer did not start');
      }
      return generation == _generation &&
          _sessionActive &&
          _engineStarted &&
          _lastStartedGeneration == generation;
    } catch (e) {
      debugPrint('❌ [SpeechService] listen error: $e');
      if (generation == _generation) {
        _sessionActive = false;
        _engineStarted = false;
        _onSilence = null;
        _onResult = null;
        _available = false;
      }
      return false;
    }
  }

  /// Stops listening. By default this is a user-requested stop and callbacks
  /// are suppressed. The overlay's push-to-talk release passes false so the
  /// final recognized words can still be delivered.
  Future<void> stop({bool suppressCallbacks = true}) async {
    if (suppressCallbacks) {
      // Invalidate a listen request that is still waiting for TTS/init/startup.
      // Otherwise the microphone could open after the user has pressed Stop.
      _listenRequestGeneration++;
      _generation++;
      _suppressCallbacks = true;
      _sessionActive = false;
      _engineStarted = false;
    }
    try {
      await _speech.stop();
    } catch (e) {
      debugPrint('⚠️ [SpeechService] stop error: $e');
    }
  }

  Future<void> cancel() async {
    _listenRequestGeneration++;
    _generation++;
    _suppressCallbacks = true;
    _sessionActive = false;
    _engineStarted = false;
    _onSilence = null;
    _onResult = null;
    try {
      await _speech.cancel();
    } catch (e) {
      debugPrint('⚠️ [SpeechService] cancel error: $e');
    }
    _lastText = '';
  }
}

// Speech Service v3:
// - تمييز الإيقاف اليدوي عن الصمت الحقيقي.
// - منع callbacks المتأخرة من جلسة صوتية سابقة.
// - تسليم النتيجة النهائية أو الصمت مرة واحدة فقط.
// - الحفاظ على محرك STT مشترك بين VoiceScreen والزر العائم.
