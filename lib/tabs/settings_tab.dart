import 'package:flutter/material.dart';
import '../services/overlay_service.dart';

class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(
        children: [
          const _SectionHeader('الزر العائم فوق التطبيقات'),
          ListTile(
            leading: const Icon(Icons.picture_in_picture_alt),
            title: const Text('تشغيل الزر العائم'),
            subtitle: const Text('يظهر على حافة الشاشة من أي تطبيق'),
            trailing: FilledButton(
              onPressed: () async {
                final ok = await OverlayService.show();
                if (context.mounted) {
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
                        content: Text('⚠️ فشل التشغيل — امنح الأذونات'),
                        backgroundColor: Colors.orange,
                      ),
                    );
                  }
                }
              },
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
                  const SnackBar(
                    content: Text('تم إيقاف الزر العائم'),
                    backgroundColor: Colors.grey,
                  ),
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
          const ListTile(
            leading: Icon(Icons.mic),
            title: Text('محرك الصوت'),
            subtitle: Text('Google STT (متصل)'),
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
