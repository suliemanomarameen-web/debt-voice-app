import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/speech_service.dart';

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
  String _status = 'جاري التهيئة...';

  @override
  void initState() {
    super.initState();
    _setup();
  }

  Future<void> _setup() async {
    // 1) اطلب إذن الميكروفون
    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      setState(() {
        _status = 'لم يُمنح إذن الميكروفون';
      });
      return;
    }

    // 2) هيّئ محرك الصوت
    final ok = await _speech.init();
    if (!mounted) return;

    if (!ok) {
      setState(() {
        _status = 'فشل تهيئة محرك الصوت';
      });
      return;
    }

    setState(() {
      _ready = true;
      _status = 'اضغط مطولاً للتسجيل';
    });
  }

  Future<void> _startRecording() async {
    if (!_ready) {
      // حاول التهيئة مرة أخرى
      await _setup();
      if (!_ready) return;
    }

    setState(() {
      _recording = true;
      _partialText = '';
      _status = 'أستمع...';
    });

    try {
      await _speech.listen(
        onResult: (text, isFinal) {
          if (!mounted) return;
          setState(() {
            _partialText = text;
          });
          if (isFinal) {
            _finishRecording();
          }
        },
        timeout: const Duration(seconds: 30),
      );
    } catch (e) {
      setState(() {
        _status = 'خطأ: $e';
        _recording = false;
      });
    }
  }

  Future<void> _finishRecording() async {
    await _speech.stop();
    if (!mounted) return;

    setState(() {
      _recording = false;
      _status = _partialText.isEmpty ? 'لم أسمع شيئاً' : 'تم';
    });

    if (_partialText.isEmpty) return;

    // أرسل النص للتطبيق الرئيسي
    await FlutterOverlayWindow.shareData({
      'action': 'voice_text',
      'text': _partialText,
    });

    // أعِد الزر لحالته
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) {
      setState(() {
        _status = 'اضغط مطولاً للتسجيل';
        _partialText = '';
      });
    }
  }

  Future<void> _cancelRecording() async {
    await _speech.cancel();
    if (!mounted) return;
    setState(() {
      _recording = false;
      _partialText = '';
      _status = 'اضغط مطولاً للتسجيل';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        onLongPressStart: (_) => _startRecording(),
        onLongPressEnd: (_) {
          if (_recording) _finishRecording();
        },
        onTap: _recording ? _cancelRecording : null,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _recording
                    ? Colors.red
                    : (_ready ? Colors.deepOrange : Colors.grey),
                boxShadow: const [
                  BoxShadow(
                      color: Colors.black45, blurRadius: 12, spreadRadius: 2),
                ],
              ),
              child: Icon(
                _recording ? Icons.mic : Icons.mic_none,
                color: Colors.white,
                size: 40,
              ),
            ),
            if (_recording)
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.red, width: 3),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
