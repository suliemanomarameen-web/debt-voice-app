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
    if (!_speechReady) _speechReady = await _speech.init();
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

  // ========== نافذة كلمة المرور القديمة ==========
  Future<bool> _askOldPassword() async {
    final ctrl = TextEditingController();
    String? error;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (ctx, setSt) => AlertDialog(
            title: const Text('كلمة المرور الحالية'),
            content: TextField(
              controller: ctrl,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 20,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'كلمة المرور الحالية',
                border: const OutlineInputBorder(),
                counterText: '',
                errorText: error,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () async {
                  final pwd = ctrl.text.trim();
                  if (pwd.isEmpty) {
                    setSt(() => error = 'أدخل كلمة المرور');
                    return;
                  }
                  final ok = await AuthService.verifyPassword(pwd);
                  if (!ok) {
                    setSt(() => error = 'كلمة المرور غير صحيحة');
                    return;
                  }
                  Navigator.pop(ctx, true);
                },
                child: const Text('تأكيد'),
              ),
            ],
          ),
        ),
      ),
    );
    return result ?? false;
  }

  // ========== نافذة إنشاء كلمة مرور + سؤال أمان ==========
  Future<Map<String, String>?> _askNewPasswordWithSecurity() async {
    final pwd1 = TextEditingController();
    final pwd2 = TextEditingController();
    final answer = TextEditingController();
    String selectedQuestion = 'ما اسم مدينتك الأولى؟';
    String? error;

    const questions = [
      'ما اسم مدينتك الأولى؟',
      'ما اسم أول مدرسة درست فيها؟',
      'ما اسم والدتك؟',
      'ما اسم أول صديق لك؟',
      'ما اسم حيوانك المفضل؟',
    ];

    return await showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (ctx, setSt) => AlertDialog(
            title: const Text('إنشاء كلمة مرور'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('احفظ كلمة المرور جيداً. ستحتاجها لفتح التطبيق.',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: pwd1,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: 20,
                    decoration: const InputDecoration(
                      labelText: 'كلمة المرور (أرقام)',
                      border: OutlineInputBorder(),
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: pwd2,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: 20,
                    decoration: const InputDecoration(
                      labelText: 'تأكيد كلمة المرور',
                      border: OutlineInputBorder(),
                      counterText: '',
                    ),
                  ),
                  const Divider(height: 32),
                  const Text('سؤال الأمان (لاستعادة كلمة المرور):',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: selectedQuestion,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: questions
                        .map((q) => DropdownMenuItem(value: q, child: Text(q)))
                        .toList(),
                    onChanged: (v) => setSt(() => selectedQuestion = v!),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: answer,
                    decoration: InputDecoration(
                      labelText: 'إجابة سؤال الأمان',
                      border: const OutlineInputBorder(),
                      errorText: error,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () {
                  final p1 = pwd1.text.trim();
                  final p2 = pwd2.text.trim();
                  final ans = answer.text.trim();
                  if (p1.length < 4) {
                    setSt(() => error = 'كلمة المرور: 4 أرقام على الأقل');
                    return;
                  }
                  if (p1 != p2) {
                    setSt(() => error = 'كلمتا المرور غير متطابقتين');
                    return;
                  }
                  if (ans.isEmpty) {
                    setSt(() => error = 'أدخل إجابة سؤال الأمان');
                    return;
                  }
                  Navigator.pop(ctx, {
                    'password': p1,
                    'question': selectedQuestion,
                    'answer': ans,
                  });
                },
                child: const Text('حفظ'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ========== تفعيل القفل ==========
  Future<void> _enableLock() async {
    final data = await _askNewPasswordWithSecurity();
    if (data == null) return;
    await AuthService.setPassword(data['password']!);
    await AuthService.setSecurity(
      question: data['question']!,
      answer: data['answer']!,
    );
    await AuthService.setEnabled(true);
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تفعيل القفل'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  // ========== تغيير كلمة المرور ==========
  Future<void> _changePassword() async {
    // 1) كلمة المرور القديمة
    final ok = await _askOldPassword();
    if (!ok) return;

    // 2) كلمة المرور الجديدة
    final data = await _askNewPasswordWithSecurity();
    if (data == null) return;

    // 3) حفظ الجديدة
    await AuthService.setPassword(data['password']!);
    await AuthService.setSecurity(
      question: data['question']!,
      answer: data['answer']!,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تغيير كلمة المرور'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  // ========== تعطيل القفل ==========
  Future<void> _disableLock() async {
    final ok = await _askOldPassword();
    if (!ok) return;
    await AuthService.setEnabled(false);
    await AuthService.removePassword();
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تعطيل القفل'),
          backgroundColor: Colors.grey,
        ),
      );
    }
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

          // ========== الحماية ==========
          const _SectionHeader('الحماية'),
          FutureBuilder<bool>(
            future: AuthService.isEnabled(),
            builder: (_, snap) {
              final enabled = snap.data ?? false;
              return Column(
                children: [
                  if (!enabled)
                    ListTile(
                      leading: const Icon(Icons.lock_outline),
                      title: const Text('تفعيل القفل'),
                      subtitle: const Text('حماية التطبيق بكلمة مرور'),
                      trailing: FilledButton(
                        onPressed: _enableLock,
                        child: const Text('تفعيل'),
                      ),
                    ),
                  if (enabled) ...[
                    const ListTile(
                      leading: Icon(Icons.lock, color: Colors.green),
                      title: Text('القفل مفعّل'),
                      subtitle:
                          Text('يُقفل عند مغادرة التطبيق لأكثر من 30 ثانية'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.password),
                      title: const Text('تغيير كلمة المرور'),
                      trailing:
                          const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: _changePassword,
                    ),
                    ListTile(
                      leading: const Icon(Icons.help_outline),
                      title: const Text('سؤال الأمان الحالي'),
                      subtitle: FutureBuilder<String?>(
                        future: AuthService.getSecurityQuestion(),
                        builder: (_, s) =>
                            Text(s.data ?? 'غير محدد'),
                      ),
                    ),
                    ListTile(
                      leading:
                          const Icon(Icons.lock_open, color: Colors.red),
                      title: const Text('تعطيل القفل',
                          style: TextStyle(color: Colors.red)),
                      onTap: _disableLock,
                    ),
                  ],
                ],
              );
            },
          ),

          // ========== الزر العائم ==========
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

          // ========== المظهر ==========
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

          // ========== الإحصائيات ==========
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

          // ========== التصدير ==========
          const _SectionHeader('التصدير'),
          ListTile(
            leading: const Icon(Icons.table_chart),
            title: const Text('تصدير Excel'),
            onTap: _exportAllExcel,
          ),
          ListTile(
            leading: const Icon(Icons.file_download),
            title: const Text('تصدير CSV'),
            onTap: _exportAllCsv,
          ),

          // ========== التذكيرات ==========
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

          // ========== معلومات ==========
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
