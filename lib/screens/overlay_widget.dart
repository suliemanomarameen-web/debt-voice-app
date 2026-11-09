import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/logger_service.dart';

class OverlayWidget extends StatefulWidget {
  const OverlayWidget({super.key});

  @override
  State<OverlayWidget> createState() => _OverlayWidgetState();
}

class _OverlayWidgetState extends State<OverlayWidget> {
  bool _recording = false;
  bool _ready = true; // محرك الصوت الآن يعمل في main، لذا هو دائماً جاهز هنا
  String _mode = 'long_press';

  StreamSubscription<dynamic>? _subscription;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _loadMode();
    _setupListener();
    _startPolling();
  }

  Future<void> _loadMode() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final m = sp.getString('overlay_record_mode') ?? 'long_press';
      if (mounted) setState(() => _mode = m);
      await LoggerService.devInfo('overlay', 'Mode loaded: $m');
    } catch (e) {
      await LoggerService.devError('overlay', 'loadMode: $e');
    }
  }

  void _setupListener() {
    try {
      _subscription = FlutterOverlayWindow.overlayListener.listen((data) async {
        if (data is! Map) return;
        final action = data['action'] as String?;
        await LoggerService.devInfo('overlay', 'Received message: $action');

        switch (action) {
          case 'stt_started': // 🆕 إضاءة الزر عند استمرار الحوار
            if (mounted) setState(() => _recording = true);
            break;

          case 'stt_result':
            // استقبال نتيجة التعرف على الصوت من main
            final text = data['text'] as String? ?? '';
            // لا نطفيء الزر إلا عند الإلغاء أو الخطأ، لكي يبدو مستمراً
            if (text == 'cancelled' || text == '__ERROR__' || text == 'stopped') {
              if (mounted) {
                setState(() {
                  _recording = false;
                });
              }
            }
            await LoggerService.devInfo('overlay', 'STT result received: "$text"');
            break;

          case 'overlay_mode':
            final m = data['mode'] as String?;
            if (m != null && mounted) setState(() => _mode = m);
            break;

          case 'start_recording':
            await LoggerService.devInfo('overlay', 'start_recording requested');
            _startRecording();
            break;
        }
      });
    } catch (e) {
      LoggerService.devError('overlay', 'listener error: $e');
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      try {
        final prefs = await SharedPreferences.getInstance();

        if (prefs.getBool('pending_overlay_record') == true) {
          await prefs.setBool('pending_overlay_record', false);
          await LoggerService.devInfo(
              'overlay', 'Poll: pending_overlay_record → start');
          if (!_recording) _startRecording();
          return;
        }

        if (prefs.getBool('pending_quick_tx') == true) {
          await prefs.setBool('pending_quick_tx', false);
          await LoggerService.devInfo(
              'overlay', 'Poll: pending_quick_tx → open_quick_tx');
          await FlutterOverlayWindow.shareData({'action': 'open_quick_tx'});
          return;
        }

        if (prefs.getBool('pending_new_customer') == true) {
          await prefs.setBool('pending_new_customer', false);
          await LoggerService.devInfo(
              'overlay', 'Poll: pending_new_customer → open_new_customer');
          await FlutterOverlayWindow.shareData({'action': 'open_new_customer'});
          return;
        }

        if (prefs.getBool('pending_open_stats') == true) {
          await prefs.setBool('pending_open_stats', false);
          await LoggerService.devInfo(
              'overlay', 'Poll: pending_open_stats → open_stats');
          await FlutterOverlayWindow.shareData({'action': 'open_stats'});
          return;
        }

        if (prefs.getBool('pending_open_notifications') == true) {
          await prefs.setBool('pending_open_notifications', false);
          await LoggerService.devInfo(
              'overlay', 'Poll: pending_open_notifications → open_notifications');
          await FlutterOverlayWindow.shareData({'action': 'open_notifications'});
          return;
        }

        if (prefs.getBool('pending_stop_overlay') == true) {
          await prefs.setBool('pending_stop_overlay', false);
          await LoggerService.devInfo(
              'overlay', 'Poll: pending_stop_overlay → stop');
          await FlutterOverlayWindow.closeOverlay();
          return;
        }
      } catch (e) {
        debugPrint('❌ [Overlay] Poll error: $e');
      }
    });
  }

  Future<void> _startRecording() async {
    if (_recording) {
      await LoggerService.devWarn('overlay', '_startRecording: already recording');
      return;
    }

    if (!mounted) return;

    HapticFeedback.lightImpact();
    setState(() {
      _recording = true;
    });

    await LoggerService.devInfo('overlay', 'Requesting STT from main isolate');

    try {
      // نطلب من التطبيق الرئيسي (main) تشغيل محرك الصوت
      await FlutterOverlayWindow.shareData({'action': 'start_stt_in_main'});
    } catch (e) {
      await LoggerService.devError('overlay', 'Failed to request STT: $e');
      if (mounted) setState(() => _recording = false);
    }
  }

  Future<void> _finishRecording() async {
    if (!_recording) return;

    try {
      if (mounted) setState(() => _recording = false);
      HapticFeedback.mediumImpact();
      await LoggerService.devInfo('overlay', 'Requesting STT stop');
      // نطلب من التطبيق الرئيسي إيقاف التسجيل
      await FlutterOverlayWindow.shareData({'action': 'stop_stt_in_main'});
    } catch (e) {
      await LoggerService.devError('overlay', 'finish error: $e');
    }
  }

  Future<void> _cancelRecording() async {
    if (!_recording) return;
    if (!mounted) return;
    HapticFeedback.lightImpact();
    setState(() {
      _recording = false;
    });
    await LoggerService.devInfo('overlay', 'Recording cancelled by user');
    try {
      // 🆕 إرسال أمر إلغاء كامل وليس إيقافاً مؤقتاً
      await FlutterOverlayWindow.shareData({'action': 'cancel_stt_in_main'});
    } catch (_) {}
  }

  Future<void> _handleTap() async {
    if (_recording) {
      await _cancelRecording();
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
        onTap: _handleTap, // 🆕 يعمل في كلا الوضعين: بدء أو إلغاء
        onLongPressStart: (_) {
          if (_recording) {
            _cancelRecording();
          } else {
            _startRecording();
          }
        },
        onLongPressEnd: (_) {
          if (!isTapMode && _recording) {
            _finishRecording(); // يرسل stop فقط، الحوار يستمر
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
// Overlay Widget v4: Polling كل 500ms
// Overlay Widget v5: سجلات المطور (devInfo/devWarn/devError)
// Overlay Widget v6: نقل محرك الصوت (STT) إلى main isolate وإزالة SpeechService
// Overlay Widget v7: إضافة حالة stt_started لدعم استمرار الحوار
// Overlay Widget v8: النقر = إلغاء، رفع الإصبع = استمرار الحوار
