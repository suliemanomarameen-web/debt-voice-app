import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import '../services/speech_service.dart';

class OverlayWidget extends StatefulWidget {
  const OverlayWidget({super.key});
  @override
  State<OverlayWidget> createState() => _OverlayWidgetState();
}

class _OverlayWidgetState extends State<OverlayWidget> {
  final _speech = SpeechService();
  bool _recording = false;
  String _partialText = '';

  @override
  void initState() {
    super.initState();
    _speech.init();
  }

  Future<void> _startRecording() async {
    setState(() {
      _recording = true;
      _partialText = '';
    });

    await _speech.listen(onResult: (text, isFinal) {
      _partialText = text;
      if (isFinal) {
        _finishRecording();
      }
    }, timeout: const Duration(seconds: 30));
  }

  Future<void> _finishRecording() async {
    await _speech.stop();
    setState(() => _recording = false);

    if (_partialText.isEmpty) return;

    // أرسل النص إلى التطبيق الرئيسي
    await FlutterOverlayWindow.shareData({
      'action': 'voice_text',
      'text': _partialText,
    });
  }

  Future<void> _cancelRecording() async {
    await _speech.cancel();
    setState(() {
      _recording = false;
      _partialText = '';
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
        child: Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _recording ? Colors.red : Colors.deepOrange,
            boxShadow: const [
              BoxShadow(color: Colors.black45, blurRadius: 12, spreadRadius: 2),
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
