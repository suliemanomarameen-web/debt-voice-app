import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../db/database_helper.dart';
import '../services/auth_service.dart';
import '../services/export_service.dart';
import '../services/overlay_service.dart';
import '../services/permission_service.dart';
import '../services/reminder_service.dart';
import '../services/speech_service.dart';
import '../services/theme_service.dart';
import '../screens/stats_screen.dart';

class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key});
  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  final _speech = SpeechService();
  bool _micReady = false;
  bool _speechReady = false;
  String _version = '...';

  @override
  void initState() {
    super.initState();
    _checkStatus();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _version = '${info.version} (${info.buildNumber})';
      });
    } catch (_) {
      if (mounted) setState(() => _version = '1.0.0');
    }
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
          content: Text('كل شيء جاهز'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      String msg = '';
      if (!_micReady) msg += 'الميكروفون غير مسموح. ';
      if (!_speechReady) msg += 'محرك الصوت غير جاهز.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.orange),
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
          content: Text('تم تشغيل الزر العائم'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('فشل التشغيل'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Future<void> _exportAllCsv() async {
    final f = await ExportService.exportAllToCsv();
    await ExportService.shareFile(f, text: 'كل الحسابات CSV');
  }

  Future<void> _exportAllExcel() async {
    final f = await ExportService.exportAllToExcel();
    await ExportService.shareFile(f, text: 'كل الحسابات Excel');
  }

  Future<void> _scheduleDaily() async {
    final db = DatabaseHelper.instance;
    final total = await db.totalDebts();
    await ReminderService.scheduleDaily(
      summary: 'إجمالي المتبقي: ${total.toStringAsFixed(0)} ريال',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم تفعيل التذكير اليومي'),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeService>();

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
            subtitle: Text(_micReady ? 'ممنوح' : 'غير ممنوح'),
          ),
          ListTile(
            leading: Icon(
              _speechReady ? Icons.check_circle : Icons.error_outline,
              color: _speechReady ? Colors.green : Colors.red,
            ),
            title: const Text('محرك الصوت'),
            subtitle: Text(_speechReady ? 'جاهز' : 'غير جاهز'),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              onPressed: _enableAll,
              icon: const Icon(Icons.security),
              label: const Text('تفعيل كل الأذونات'),
            ),
          ),

          // 🆕 قسم الحماية
          const _SectionHeader('الحماية'),
          FutureBuilder<bool>(
            future: AuthService.canUseBiometrics(),
            builder: (_, snap) {
              final supported = snap.data ?? false;
              return FutureBuilder<bool>(
                future: AuthService.isEnabled(),
                builder: (_, snap2) {
                  final enabled = snap2.data ?? false;
                  return SwitchListTile(
                    secondary: const Icon(Icons.fingerprint),
                    title: const Text('القفل ببصمة الإصبع'),
                    subtitle: Text(supported
                        ? 'يُقفل التطبيق عند مغادرته'
                        : 'الجهاز لا يدعم البصمة'),
                    value: enabled,
                    onChanged: !supported
                        ? null
                        : (v) async {
                            if (v) {
                              final ok = await AuthService.authenticate(
                                  reason: 'لتأكيد التفعيل');
                              if (!ok) return;
                            }
                            await AuthService.setEnabled(v);
                            if (context.mounted) {
                              setState(() {});
                            }
                          },
                  );
                },
              );
            },
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

          const _SectionHeader('المظهر'),
          ListTile(
            leading: const Icon(Icons.brightness_6),
            title: const Text('وضع الألوان'),
            subtitle: Text({
              ThemeMode.system: 'تلقائي',
              ThemeMode.light: 'نهاري',
              ThemeMode.dark: 'ليلي',
            }[theme.mode]!),
            onTap: () => showDialog(
              context: context,
              builder: (_) => SimpleDialog(
                title: const Text('اختر الوضع'),
                children: ThemeMode.values
                    .map((m) => SimpleDialogOption(
                          onPressed: () {
                            theme.setMode(m);
                            Navigator.pop(context);
                          },
                          child: Text({
                            ThemeMode.system: 'تلقائي',
                            ThemeMode.light: 'نهاري',
                            ThemeMode.dark: 'ليلي',
                          }[m]!),
                        ))
                    .toList(),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.palette),
            title: const Text('اللون الأساسي'),
            trailing: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: theme.seed,
                shape: BoxShape.circle,
              ),
            ),
            onTap: () => showDialog(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('اختر اللون'),
                content: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: ThemeService.presetColors
                      .map((c) => GestureDetector(
                            onTap: () {
                              theme.setSeed(c);
                              Navigator.pop(context);
                            },
                            child: Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: c,
                                shape: BoxShape.circle,
                                border: theme.seed == c
                                    ? Border.all(
                                        color: Colors.black, width: 3)
                                    : null,
                              ),
                            ),
                          ))
                      .toList(),
                ),
              ),
            ),
          ),

          const _SectionHeader('الإحصائيات'),
          ListTile(
            leading: const Icon(Icons.bar_chart),
            title: const Text('عرض الإحصائيات'),
            subtitle: const Text('أعلى المدينين + الرسم الشهري'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const StatsScreen()),
            ),
          ),

          const _SectionHeader('التصدير'),
          ListTile(
            leading: const Icon(Icons.table_chart),
            title: const Text('تصدير Excel'),
            subtitle: const Text('كل الحسابات'),
            onTap: _exportAllExcel,
          ),
          ListTile(
            leading: const Icon(Icons.file_download),
            title: const Text('تصدير CSV'),
            subtitle: const Text('كل الحسابات'),
            onTap: _exportAllCsv,
          ),

          const _SectionHeader('التذكيرات'),
          ListTile(
            leading: const Icon(Icons.notifications_active),
            title: const Text('تذكير يومي'),
            subtitle: const Text('إشعار كل يوم 9 صباحاً'),
            trailing: FilledButton(
              onPressed: _scheduleDaily,
              child: const Text('تفعيل'),
            ),
          ),

          const _SectionHeader('معلومات'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('دفتر الديون'),
            subtitle: Text('الإصدار: $_version'),
          ),
          const SizedBox(height: 24),
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
