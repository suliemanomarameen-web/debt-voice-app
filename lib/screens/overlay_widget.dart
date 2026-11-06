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
/// - يستمع لـ start_recording من الإشعار (عبر SharedPreferences polling)
/// - يعالج الأزرار الأخرى (عملية، عميل جديد، إحصائيات، إشعارات، إيقاف)
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
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _loadMode();
    _setupListener();
    _initSpeech();
    _startPolling();
  }

  // ═══════════════════════════════════════════════════════════
  // قراءة الوضع من SharedPreferences
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
  // Polling للأوامر من الإشعار الدائم (خلفية)
  // ═══════════════════════════════════════════════════════════
  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      try {
        final prefs = await SharedPreferences.getInstance();

        // 🎤 ابدأ التسجيل
        if (prefs.getBool('pending_overlay_record') == true) {
          await prefs.setBool('pending_overlay_record', false);
          debugPrint('🖼️ [Overlay] Poll: pending_overlay_record → start');
          if (!_recording && _ready) _startRecording();
          return;
        }

        // ➕ عملية سريعة → اطلب من main isolate فتح الحوار
        if (prefs.getBool('pending_quick_tx') == true) {
          await prefs.setBool('pending_quick_tx', false);
          debugPrint('🖼️ [Overlay] Poll: pending_quick_tx → open_quick_tx');
          await FlutterOverlayWindow.shareData({'action': 'open_quick_tx'});
          return;
        }

        // 👤 عميل جديد
        if (prefs.getBool('pending_new_customer') == true) {
          await prefs.setBool('pending_new_customer', false);
          debugPrint('🖼️ [Overlay] Poll: pending_new_customer → open_new_customer');
          await FlutterOverlayWindow.shareData({'action': 'open_new_customer'});
          return;
        }

        // 📊 الإحصائيات
        if (prefs.getBool('pending_open_stats') == true) {
          await prefs.setBool('pending_open_stats', false);
          debugPrint('🖼️ [Overlay] Poll: pending_open_stats → open_stats');
          await FlutterOverlayWindow.shareData({'action': 'open_stats'});
          return;
        }

        // 📋 الإشعارات
        if (prefs.getBool('pending_open_notifications') == true) {
          await prefs.setBool('pending_open_notifications', false);
          debugPrint('🖼️ [Overlay] Poll: pending_open_notifications → open_notifications');
          await FlutterOverlayWindow.shareData({'action': 'open_notifications'});
          return;
        }

        // ⏹️ إيقاف الزر العائم
        if (prefs.getBool('pending_stop_overlay') == true) {
          await prefs.setBool('pending_stop_overlay', false);
          debugPrint('🖼️ [Overlay] Poll: pending_stop_overlay → stop');
          // إغلاق الـ overlay من الداخل (سيؤدي إلى إغلاق الخدمة)
          await FlutterOverlayWindow.closeOverlay();
          return;
        }
      } catch (e) {
        debugPrint('❌ [Overlay] Poll error: $e');
      }
    });
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
  // إلغاء التسجيل
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
    _pollTimer?.cancel();
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
// Overlay Widget v4: إضافة Polling
// - كل 500ms يقرأ SharedPreferences
// - ينفذ الإجراءات: record, quick_tx, new_customer, stats, notifications, stop
// - يرسل shareData للـ main isolate لفتح الشاشات المطلوبة
// - يغلق الـ overlay مباشرة عند stop_overlay
