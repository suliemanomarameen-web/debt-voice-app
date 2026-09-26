import 'package:flutter/material.dart';
import '../services/overlay_service.dart';
import '../services/permission_service.dart';
import '../services/speech_service.dart';

class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key});
  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  final _speech = SpeechService();
  bool _micReady = false;
  bool _speechReady = false;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    final mic = await PermissionService.allGranted();
    if (!_speechReady) {
      _speechReady = await _speech.init();
    }
    if (!mounted) return;
    setState(() {
      _micReady = mic;
      _speechReady = _speechReady;
    });
  }

  Future<void> _enableAll() async {
    await PermissionService.requestAll();
    _speechReady = await _speech.init();
    await _checkStatus();

    if (!mounted) return;
    if (_micReady && _speechReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ كل شيء جاهز'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      String msg = '';
      if (!_micReady) msg += 'الميكروفون غير مسموح. ';
      if (!_speechReady) msg += 'محرك الصوت غير جاهز.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('⚠️ $msg'), backgroundColor: Colors.orange),
      );
    }
  }

  Future<void> _startOverlay() async {
    if (!_micReady || !_speechReady) {
      await _enableAll();
      if (!_micReady || !_speechReady) return;
    }

    final ok = await OverlayService.show();
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ تم تشغيل الزر العائم'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ فشل التشغيل'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(
        children: [
          const _SectionHeader('التهيئة'),
          ListTile(
            leading: Icon(
              _micReady ? Icons.check_circle : Icons.error_outline,
              color: _micReady ? Colors.green : Colors.red,
            ),
            title: const Text('إذن الميكروفون'),
            subtitle: Text(_micReady ? 'ممنوح ✅' : 'غير ممنوح'),
          ),
          ListTile(
            leading: Icon(
              _speechReady ? Icons.check_circle : Icons.error_outline,
              color: _speechReady ? Colors.green : Colors.red,
            ),
            title: const Text('محرك الصوت'),
            subtitle: Text(_speechReady ? 'جاهز ✅' : 'غير جاهز'),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              onPressed: _enableAll,
              icon: const Icon(Icons.security),
              label: const Text('تفعيل كل الأذونات'),
            ),
          ),
          const _SectionHeader('الزر العائم'),
          ListTile(
            leading: const Icon(Icons.picture_in_picture_alt),
            title: const Text('تشغيل الزر العائم'),
            trailing: FilledButton(
              onPressed: _startOverlay,
              child: const Text('تشغيل'),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.close),
            title: const Text('إيقاف الزر العائم'),
            onTap: () async {
              await OverlayService.hide();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تم الإيقاف')),
                );
              }
            },
          ),
          const _SectionHeader('معلومات'),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('دفتر الديون'),
            subtitle: Text('الإصدار 1.0.0'),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Text(title,
            style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
                fontSize: 14)),
      );
}
