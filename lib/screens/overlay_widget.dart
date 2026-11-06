import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/speech_service.dart';

/// الزر العائم — نسخة نظيفة
///
/// - STT مباشر في overlay isolate (يعمل عندما تكون Activity موجودة)
/// - إيقاف تلقائي عند isFinal = true
/// - وضعان: long_press (افتراضي) و tap
/// - يستمع لـ start_recording من الإشعار
/// - لا مؤقتات احتياطية، لا flags معقدة
class OverlayWidget extends StatefulWidget {
  const OverlayWidget({super.key});

  @override
  State<OverlayWidget> createState() => _OverlayWidgetState();
}

class _OverlayWidgetState extends State<OverlayWidget> {
  final _speech = SpeechService();

  bool _recording = false;
  bool _ready = false;
  String _partialText = '';
  String _mode = 'long_press';

  StreamSubscription<dynamic>? _subscription;

  @override
  void initState() {
    super.initState();
    _loadMode();
    _setupListener();
    _initSpeech();
  }

  // ═══════════════════════════════════════════════════════════
  // قراءة الوضع من SharedPreferences (لا SettingsService)
  // ═══════════════════════════════════════════════════════════
  Future<void> _loadMode() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final m = sp.getString('overlay_record_mode') ?? 'long_press';
      if (mounted) setState(() => _mode = m);
    } catch (_) {}
  }

  // ═══════════════════════════════════════════════════════════
  // تهيئة STT
  // ═══════════════════════════════════════════════════════════
  Future<void> _initSpeech() async {
    try {
      final ok = await _speech.init();
      if (mounted) setState(() => _ready = ok);
      debugPrint('🖼️ [Overlay] STT ready=$ok');
    } catch (e) {
      debugPrint('❌ [Overlay] STT init error: $e');
      if (mounted) setState(() => _ready = false);
    }
  }

  // ═══════════════════════════════════════════════════════════
  // الاستماع لرسائل main isolate
  // ═══════════════════════════════════════════════════════════
  void _setupListener() {
    try {
      _subscription = FlutterOverlayWindow.overlayListener.listen((data) {
        if (data is! Map) return;
        final action = data['action'] as String?;

        switch (action) {
          case 'speech_ready':
            // main isolate جاهز — جرب التهيئة مرة أخرى
            if (!_ready) _initSpeech();
            break;

          case 'overlay_mode':
            final m = data['mode'] as String?;
            if (m != null && mounted) setState(() => _mode = m);
            break;

          case 'start_recording':
            debugPrint('🎤 [Overlay] start_recording from notification');
            _startRecording();
            break;
        }
      });
    } catch (e) {
      debugPrint('❌ [Overlay] listener error: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // بدء التسجيل
  // ═══════════════════════════════════════════════════════════
  Future<void> _startRecording() async {
    if (_recording) return;

    if (!_ready) {
      await _initSpeech();
      if (!_ready) {
        FlutterOverlayWindow.shareData({'action': 'need_setup'});
        return;
      }
    }

    if (!mounted) return;

    HapticFeedback.lightImpact();
    setState(() {
      _recording = true;
      _partialText = '';
    });

    try {
      await _speech.listen(
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 3),
        onResult: (text, isFinal) {
          if (!mounted) return;
          _partialText = text;
          if (isFinal) {
            _finishRecording();
          }
        },
      );
    } catch (e) {
      debugPrint('❌ [Overlay] listen error: $e');
      if (mounted) setState(() => _recording = false);
    }
  }

  // ═══════════════════════════════════════════════════════════
  // إنهاء التسجيل
  // ═══════════════════════════════════════════════════════════
  Future<void> _finishRecording() async {
    if (!_recording) return;

    try {
      await _speech.stop();
      if (!mounted) return;

      HapticFeedback.mediumImpact();
      setState(() => _recording = false);

      final text = _partialText.trim();
      final finalText = text.isEmpty ? '__EMPTY__' : text;

      debugPrint('🖼️ [Overlay] Sending: "$finalText"');

      await FlutterOverlayWindow.shareData({
        'action': 'voice_text',
        'text': finalText,
      });

      _partialText = '';
    } catch (e) {
      debugPrint('❌ [Overlay] finish error: $e');
      if (mounted) setState(() => _recording = false);
    }
  }

  // ═══════════════════════════════════════════════════════════
  // إلغاء التسجيل (بدون إرسال)
  // ═══════════════════════════════════════════════════════════
  Future<void> _cancelRecording() async {
    if (!_recording) return;
    try {
      await _speech.cancel();
    } catch (_) {}
    if (!mounted) return;
    HapticFeedback.lightImpact();
    setState(() {
      _recording = false;
      _partialText = '';
    });
  }

  // ═══════════════════════════════════════════════════════════
  // معالجة النقرة (في وضع tap)
  // ═══════════════════════════════════════════════════════════
  Future<void> _handleTap() async {
    if (_recording) {
      await _finishRecording();
    } else {
      await _startRecording();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════
  // البناء
  // ═══════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final isTapMode = _mode == 'tap';

    final Color bgColor = _recording
        ? Colors.red
        : (_ready ? Colors.deepOrange : Colors.grey.shade600);

    final IconData icon = _recording
        ? Icons.stop
        : (_ready ? Icons.mic : Icons.mic_off);

    final List<BoxShadow> shadows = _recording
        ? [
            BoxShadow(
              color: Colors.red.withOpacity(0.6),
              blurRadius: 20,
              spreadRadius: 4,
            ),
          ]
        : [
            const BoxShadow(
              color: Colors.black26,
              blurRadius: 12,
              spreadRadius: 2,
            ),
          ];

    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: isTapMode ? _handleTap : null,
        onLongPressStart: (_) {
          if (_recording) {
            _cancelRecording();
          } else {
            _startRecording();
          }
        },
        onLongPressEnd: (_) {
          if (!isTapMode && _recording) {
            _finishRecording();
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: bgColor,
            boxShadow: shadows,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                icon,
                color: Colors.white,
                size: _recording ? 42 : 40,
              ),

              // نبض أثناء التسجيل
              if (_recording)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withOpacity(0.6),
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

              // نقطة صفراء عند غير الجاهز
              if (!_ready)
                Positioned(
                  bottom: 10,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.amber,
                    ),
                  ),
                ),

              // مربع صغير في وضع tap أثناء التسجيل
              if (isTapMode && _recording)
                Positioned(
                  bottom: 12,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// Overlay Widget v1: النسخة الأساسية
// Overlay Widget v2: إعادة كتابة
// Overlay Widget v3: نسخة نظيفة
// - STT مباشر في overlay isolate (يعمل عندما Activity موجودة)
// - إيقاف تلقائي عند isFinal = true
// - وضعان: long_press (افتراضي) و tap
// - استماع لـ start_recording من الإشعار
// - بدون مؤقتات احتياطية، بدون _finishing، بدون _recordingTimer
// - قراءة الوضع من SharedPreferences مباشرة
