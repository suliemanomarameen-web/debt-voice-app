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

  @override
  void initState() {
    super.initState();
    // اقرأ الحالة من الـ singleton — لا تُهيّئ مرة أخرى
    _checkReady();
  }

  Future<void> _checkReady() async {
    // اطلب إذن الميكروفون أولاً
    final mic = await Permission.microphone.request();

    // استخدم الحالة الحالية من الـ singleton (مُهيّأة من التطبيق الرئيسي)
    if (!_speech.isReady && mic.isGranted) {
      await _speech.init();
    }

    if (!mounted) return;
    setState(() => _ready = _speech.isReady);
  }

  Future<void> _startRecording() async {
    if (!_ready) {
      await _checkReady();
      if (!_ready) {
        await FlutterOverlayWindow.shareData({'action': 'need_setup'});
        return;
      }
    }

    setState(() {
      _recording = true;
      _partialText = '';
    });

    try {
      await _speech.listen(
        onResult: (text, isFinal) {
          if (!mounted) return;
          _partialText = text;
          if (isFinal) _finishRecording();
        },
        timeout: const Duration(seconds: 30),
      );
    } catch (e) {
      if (mounted) setState(() => _recording = false);
    }
  }

  Future<void> _finishRecording() async {
    await _speech.stop();
    if (!mounted) return;
    setState(() => _recording = false);

    if (_partialText.isEmpty) return;
    await FlutterOverlayWindow.shareData({
      'action': 'voice_text',
      'text': _partialText,
    });
    _partialText = '';
  }

  Future<void> _cancelRecording() async {
    await _speech.cancel();
    if (!mounted) return;
    setState(() {
      _recording = false;
      _partialText = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final color = _recording
        ? Colors.red
        : (_ready ? Colors.deepOrange : Colors.grey);

    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        onLongPressStart: (_) => _startRecording(),
        onLongPressEnd: (_) {
          if (_recording) _finishRecording();
        },
        onTap: _recording ? _cancelRecording : null,
        child: Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
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
      ),
    );
  }
}
