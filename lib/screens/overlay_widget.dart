import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import '../services/speech_service.dart';

/// الزر العائم — القلب النابض لتجربة الصوت
///
/// ي يدعم وضعين:
/// 1. **long_press** (افتراضي): ضغط مطول → سجّل، ارفع إصبعك → أرسل
/// 2. **tap**: نقرة → سجّل، نقرة ثانية → أرسل، ضغط مطول → إلغاء
///
/// يستمع لثلاث رسائل من الـ main isolate:
/// - speech_ready: STT جاهز في main → جرّب التهيئة
/// - overlay_mode: الوضع الحالي (long_press / tap)
/// - start_recording: من زر الإشعار الدائم
///
/// يرسل رسائل إلى main isolate:
/// - voice_text: النص المكتشف
/// - need_setup: يحتاج إعداد (إذن مفقود)
class OverlayWidget extends StatefulWidget {
  const OverlayWidget({super.key});

  @override
  State<OverlayWidget> createState() => _OverlayWidgetState();
}

class _OverlayWidgetState extends State<OverlayWidget> {
  final _speech = SpeechService();

  bool _recording = false;
  bool _ready = false;
  bool _initializing = false;
  bool _finishing = false;
  String _partialText = '';

  /// الوضع الحالي — long_press | tap
  String _mode = 'long_press';

  StreamSubscription<dynamic>? _subscription;
  Timer? _readyFallbackTimer;
  Timer? _recordingTimer;

  @override
  void initState() {
    super.initState();
    _setupListener();
    _scheduleReadyFallback();
    _tryInitSpeech();
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
            // الـ main isolate جاهز — جرّب تهيئة STT في overlay
            _readyFallbackTimer?.cancel();
            _tryInitSpeech();
            break;

          case 'overlay_mode':
            final m = data['mode'] as String?;
            if (m != null && mounted) {
              setState(() => _mode = m);
              debugPrint('🖼️ [Overlay] Mode updated: $m');
            }
            break;

          case 'start_recording':
            // من زر الإشعار الدائم
            debugPrint('🎤 [Overlay] Start from notification');
            _startRecording();
            break;
        }
      });
    } catch (e) {
      debugPrint('❌ [Overlay] listener setup error: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // تهيئة STT
  // ═══════════════════════════════════════════════════════════
  Future<void> _tryInitSpeech() async {
    if (_initializing) return;
    _initializing = true;
    try {
      final ok = await _speech.init();
      if (!mounted) return;
      setState(() => _ready = ok);
      debugPrint('🖼️ [Overlay] STT init → ready=$ok');
    } catch (e) {
      debugPrint('❌ [Overlay] STT init error: $e');
      if (mounted) setState(() => _ready = false);
    } finally {
      _initializing = false;
    }
  }

  void _scheduleReadyFallback() {
    // إذا لم تصل speech_ready خلال 3 ثوانٍ، جرّب التهيئة مباشرة
    _readyFallbackTimer = Timer(const Duration(seconds: 3), () {
      if (!_ready && mounted) {
        debugPrint('🖼️ [Overlay] Fallback STT init attempt');
        _tryInitSpeech();
      }
    });
  }

  // ═══════════════════════════════════════════════════════════
  // بدء التسجيل
  // ═══════════════════════════════════════════════════════════
  Future<void> _startRecording() async {
    if (_recording || _finishing) return;

    // تهيئة STT إذا لم تكن جاهزة
    if (!_ready) {
      await _tryInitSpeech();
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

    // مؤقت احتياطي — إذا لم ينتهِ التسجيل تلقائيًا بعد 35 ثانية
    _recordingTimer?.cancel();
    _recordingTimer = Timer(const Duration(seconds: 35), () {
      if (_recording && mounted) {
        debugPrint('🖼️ [Overlay] Recording timeout — forcing finish');
        _finishRecording();
      }
    });

    try {
      await _speech.listen(
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 5),
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
      _recordingTimer?.cancel();
      if (mounted) setState(() => _recording = false);
    }
  }

  // ═══════════════════════════════════════════════════════════
  // إنهاء التسجيل (بعد isFinal أو بعد رفع الإصبع)
  // ═══════════════════════════════════════════════════════════
  Future<void> _finishRecording() async {
    if (_finishing || !_recording) return;
    _finishing = true;

    _recordingTimer?.cancel();

    try {
      await _speech.stop();

      if (!mounted) return;
      HapticFeedback.mediumImpact();

      setState(() => _recording = false);

      final text = _partialText.trim();
      final finalText = text.isEmpty ? '__EMPTY__' : text;

      debugPrint('🖼️ [Overlay] Sending voice_text: "$finalText"');

      await FlutterOverlayWindow.shareData({
        'action': 'voice_text',
        'text': finalText,
      });

      _partialText = '';
    } catch (e) {
      debugPrint('❌ [Overlay] finish error: $e');
    } finally {
      _finishing = false;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // إلغاء التسجيل (بدون إرسال)
  // ═══════════════════════════════════════════════════════════
  Future<void> _cancelRecording() async {
    if (!_recording) return;

    _recordingTimer?.cancel();

    try {
      await _speech.cancel();
    } catch (_) {}

    if (!mounted) return;
    HapticFeedback.lightImpact();
    setState(() {
      _recording = false;
      _partialText = '';
    });
    debugPrint('🖼️ [Overlay] Recording cancelled');
  }

  // ═══════════════════════════════════════════════════════════
  // معالجة النقرة (في وضع tap فقط)
  // ═══════════════════════════════════════════════════════════
  Future<void> _handleTap() async {
    if (_recording) {
      await _finishRecording();
    } else {
      await _startRecording();
    }
  }

  // ═══════════════════════════════════════════════════════════
  // Dispose
  // ═══════════════════════════════════════════════════════════
  @override
  void dispose() {
    _subscription?.cancel();
    _readyFallbackTimer?.cancel();
    _recordingTimer?.cancel();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════
  // البناء
  // ═══════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final isTapMode = _mode == 'tap';
    
    // لون الحالة
    final Color bgColor = _recording
        ? Colors.red
        : (_ready ? Colors.deepOrange : Colors.grey.shade600);

    // أيقونة الحالة
    final IconData icon = _recording
        ? Icons.stop
        : (_ready ? Icons.mic : Icons.mic_off);

    // ظل متوهج
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
        // في tap mode: نقرة تبدّل بين بدء/إيقاف
        onTap: isTapMode ? _handleTap : null,
        // في long_press mode: ضغط مطول = بدء/إيقاف
        // في tap mode: ضغط مطول = إلغاء (اختصار)
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
              // الأيقونة
              Icon(
                icon,
                color: Colors.white,
                size: _recording ? 42 : 40,
              ),

              // مؤشر نبض خفيف أثناء التسجيل
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

              // مؤشر "غير جاهز" — نقطة صغيرة سفلية
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

              // في tap mode، أثناء التسجيل — مربع صغير (إشارة للإيقاف)
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

// Overlay Widget v1: النسخة الأساسية (ضغط مطول فقط)
// Overlay Widget v2: إعادة كتابة كاملة
// - وضعان: long_press (افتراضي) و tap
// - استماع لثلاث رسائل: speech_ready، overlay_mode، start_recording
// - تهيئة STT تلقائيًا عند speech_ready + fallback بعد 3 ثوانٍ
// - إيقاف تلقائي بعد isFinal + مؤقت احتياطي 35 ثانية
// - haptic feedback (اهتزاز) عند البدء والإيقاف
// - إلغاء بـ long press في tap mode
// - مؤشرات بصرية: نقطة صفراء عند غير الجاهز، مربع أبيض عند tap-recording
