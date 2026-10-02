import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../db/database_helper.dart';
import '../services/auth_service.dart';
import '../services/auto_backup_service.dart';
import '../services/backup_service.dart';
import '../services/export_service.dart';
import '../services/gdrive_service.dart';
import '../services/overlay_service.dart';
import '../services/permission_service.dart';
import '../services/reminder_service.dart';
import '../services/speech_service.dart';
import '../services/theme_service.dart';
import '../screens/gdrive_screen.dart';
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
  bool _backupBusy = false;
  bool _autoEnabled = false;
  String _autoFreq = 'daily';
  bool _gdriveSignedIn = false;

  @override
  void initState() {
    super.initState();
    _checkStatus();
    _loadVersion();
    _loadAutoBackup();
    _checkGDrive();
  }

  Future<void> _checkGDrive() async {
    final signed = GDriveService.isSignedIn;
    if (!mounted) return;
    setState(() => _gdriveSignedIn = signed);
  }

  Future<void> _loadAutoBackup() async {
    final enabled = await AutoBackupService.isEnabled();
    final freq = await AutoBackupService.getFrequency();
    if (!mounted) return;
    setState(() {
      _autoEnabled = enabled;
      _autoFreq = freq;
    });
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _version = '${info.version} (${info.buildNumber})');
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

  // ============== النسخ اليدوي ==============
  Future<void> _createBackup() async {
    setState(() => _backupBusy = true);
    final result = await BackupService.createBackup();
    if (!mounted) return;
    setState(() => _backupBusy = false);

    if (result.success) {
      await showDialog(
        context: context,
        builder: (ctx) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 8),
                Text('تم إنشاء النسخة'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${result.customersCount} حساب'),
                Text('${result.transactionsCount} عملية'),
                const Divider(),
                Text('المسار:\n${result.filePath}',
                    style: const TextStyle(fontSize: 11)),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إغلاق'),
              ),
              FilledButton.icon(
                onPressed: () async {
                  Navigator.pop(ctx);
                  if (result.filePath != null) {
                    await BackupService.shareBackup(result.filePath!);
                  }
                },
                icon: const Icon(Icons.share),
                label: const Text('مشاركة'),
              ),
            ],
          ),
        ),
      );
    }
  }

  Future<void> _showBackupsList() async {
    final backups = await BackupService.listBackups();
    if (!mounted) return;

    if (backups.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد نسخ احتياطية')),
      );
      return;
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: Container(
          height: MediaQuery.of(context).size.height * 0.7,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text('النسخ المحفوظة (${backups.length})',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  itemCount: backups.length,
                  itemBuilder: (_, i) {
                    final file = backups[i];
                    final name = file.path.split('/').last;
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.description),
                        title: Text(name,
                            style: const TextStyle(fontSize: 13)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.restore,
                                  color: Colors.blue),
                              onPressed: () {
                                Navigator.pop(context);
                                _restoreFromFile(file.path);
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.share),
                              onPressed: () =>
                                  BackupService.shareBackup(file.path),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete,
                                  color: Colors.red),
                              onPressed: () async {
                                await BackupService.deleteBackup(file.path);
                                if (context.mounted) {
                                  Navigator.pop(context);
                                  _showBackupsList();
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickAndRestore() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result == null || result.files.isEmpty) return;
      final path = result.files.first.path;
      if (path == null) return;
      if (!mounted) return;
      await _restoreFromFile(path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل الاختيار: $e')),
      );
    }
  }

  Future<void> _restoreFromFile(String filePath) async {
    final info = await BackupService.peekFile(filePath);
    if (!mounted) return;

    if (info == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('الملف غير صالح'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final mode = await showDialog<String>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('استعادة نسخة'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('التاريخ: ${info['created_at']}'),
              Text('الحسابات: ${info['customers_count']}'),
              Text('العمليات: ${info['transactions_count']}'),
              const Divider(height: 24),
              const Text('طريقة الاستعادة:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, 'replace'),
              child: const Text('استبدال كامل'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'merge'),
              child: const Text('دمج'),
            ),
          ],
        ),
      ),
    );

    if (mode == null) return;

    setState(() => _backupBusy = true);
    final result = await BackupService.restoreFromFile(filePath, mode: mode);
    if (!mounted) return;
    setState(() => _backupBusy = false);

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Row(
            children: [
              Icon(
                result.success ? Icons.check_circle : Icons.error,
                color: result.success ? Colors.green : Colors.red,
              ),
              const SizedBox(width: 8),
              Text(result.success ? 'تمت الاستعادة' : 'فشل'),
            ],
          ),
          content: Text(
            result.success
                ? '${result.message}\n\n'
                    'حسابات مضافة: ${result.customersAdded}\n'
                    'عمليات مضافة: ${result.transactionsAdded}'
                : result.message,
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('تم'),
            ),
          ],
        ),
      ),
    );
  }

  // ============== النسخ التلقائي ==============
  Future<void> _toggleAutoBackup(bool v) async {
    await AutoBackupService.setEnabled(v);
    if (!mounted) return;
    setState(() => _autoEnabled = v);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            Text(v ? 'تم تفعيل النسخ التلقائي' : 'تم إيقاف النسخ التلقائي'),
        backgroundColor: v ? Colors.green : Colors.grey,
      ),
    );
  }

  Future<void> _changeFreq() async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: SimpleDialog(
          title: const Text('تكرار النسخ التلقائي'),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, 'daily'),
              child: Row(
                children: [
                  if (_autoFreq == 'daily')
                    const Icon(Icons.check, color: Colors.green),
                  const SizedBox(width: 8),
                  const Text('يومياً'),
                ],
              ),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, 'weekly'),
              child: Row(
                children: [
                  if (_autoFreq == 'weekly')
                    const Icon(Icons.check, color: Colors.green),
                  const SizedBox(width: 8),
                  const Text('أسبوعياً'),
                ],
              ),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, 'monthly'),
              child: Row(
                children: [
                  if (_autoFreq == 'monthly')
                    const Icon(Icons.check, color: Colors.green),
                  const SizedBox(width: 8),
                  const Text('شهرياً'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    await AutoBackupService.setFrequency(result);
    if (!mounted) return;
    setState(() => _autoFreq = result);
  }

  String _freqLabel(String f) {
    return {'daily': 'يومياً', 'weekly': 'أسبوعياً', 'monthly': 'شهرياً'}[f] ??
        f;
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeService>();

    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(
        children: [
          // ========== التهيئة ==========
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
                      trailing: FilledButton(
                        onPressed: () => _enableLockDialog(),
                        child: const Text('تفعيل'),
                      ),
                    ),
                  if (enabled) ...[
                    const ListTile(
                      leading: Icon(Icons.lock, color: Colors.green),
                      title: Text('القفل مفعّل'),
                    ),
                    ListTile(
                      leading:
                          const Icon(Icons.lock_open, color: Colors.red),
                      title: const Text('تعطيل القفل',
                          style: TextStyle(color: Colors.red)),
                      onTap: () => _disableLockDialog(),
                    ),
                  ],
                ],
              );
            },
          ),

          // ========== النسخ الاحتياطي المحلي ==========
          const _SectionHeader('النسخ الاحتياطي'),
          ListTile(
            leading: _backupBusy
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.backup, color: Colors.blue),
            title: const Text('إنشاء نسخة احتياطية'),
            subtitle: const Text('حفظ يدوي الآن'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: _backupBusy ? null : _createBackup,
          ),
          ListTile(
            leading: const Icon(Icons.history, color: Colors.green),
            title: const Text('عرض النسخ المحفوظة'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: _showBackupsList,
          ),
          ListTile(
            leading: const Icon(Icons.restore, color: Colors.orange),
            title: const Text('استعادة من ملف'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: _backupBusy ? null : _pickAndRestore,
          ),

          const Divider(height: 24),

          // ========== النسخ التلقائي ==========
          SwitchListTile(
            secondary: const Icon(Icons.schedule, color: Colors.purple),
            title: const Text('النسخ التلقائي'),
            subtitle: Text(_autoEnabled
                ? 'النسخ كل ${_freqLabel(_autoFreq)}'
                : 'نسخ احتياطي في الخلفية'),
            value: _autoEnabled,
            onChanged: _toggleAutoBackup,
          ),
          if (_autoEnabled)
            ListTile(
              leading: const Icon(Icons.repeat),
              title: const Text('تكرار النسخ'),
              subtitle: Text(_freqLabel(_autoFreq)),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: _changeFreq,
            ),
          if (_autoEnabled)
            ListTile(
              leading: const Icon(Icons.play_arrow, color: Colors.green),
              title: const Text('تشغيل نسخة الآن'),
              subtitle: const Text('اختبار فوري'),
              onTap: () async {
                setState(() => _backupBusy = true);
                await AutoBackupService.runNow();
                if (!mounted) return;
                setState(() => _backupBusy = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('تم إنشاء نسخة'),
                    backgroundColor: Colors.green,
                  ),
                );
              },
            ),

          // ========== Google Drive ==========
          const _SectionHeader('Google Drive'),
          ListTile(
            leading: Icon(
              Icons.cloud,
              color: _gdriveSignedIn ? Colors.green : Colors.blue,
            ),
            title: const Text('النسخ الاحتياطي على Drive'),
            subtitle: Text(_gdriveSignedIn
                ? 'متصل: ${GDriveService.userEmail ?? ""}'
                : 'ارفع واستعد من Google Drive'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const GDriveScreen()),
              );
              _checkGDrive();
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

  // ========== حوارات القفل ==========
  Future<void> _enableLockDialog() async {
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

    final result = await showDialog<Map<String, String>>(
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
                  TextField(
                    controller: pwd1,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: 20,
                    decoration: const InputDecoration(
                      labelText: 'كلمة المرور',
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
                  const Divider(height: 24),
                  const Text('سؤال الأمان:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: selectedQuestion,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: questions
                        .map((q) =>
                            DropdownMenuItem(value: q, child: Text(q)))
                        .toList(),
                    onChanged: (v) => setSt(() => selectedQuestion = v!),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: answer,
                    decoration: InputDecoration(
                      labelText: 'الإجابة',
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
                  final a = answer.text.trim();
                  if (p1.length < 4) {
                    setSt(() => error = 'كلمة المرور: 4 أرقام على الأقل');
                    return;
                  }
                  if (p1 != p2) {
                    setSt(() => error = 'غير متطابقتين');
                    return;
                  }
                  if (a.isEmpty) {
                    setSt(() => error = 'أدخل الإجابة');
                    return;
                  }
                  Navigator.pop(ctx, {
                    'pwd': p1,
                    'q': selectedQuestion,
                    'a': a,
                  });
                },
                child: const Text('حفظ'),
              ),
            ],
          ),
        ),
      ),
    );

    if (result == null) return;
    await AuthService.setPassword(result['pwd']!);
    await AuthService.setSecurity(
        question: result['q']!, answer: result['a']!);
    await AuthService.setEnabled(true);
    if (mounted) setState(() {});
  }

  Future<void> _disableLockDialog() async {
    final ctrl = TextEditingController();
    String? error;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (ctx, setSt) => AlertDialog(
            title: const Text('تعطيل القفل'),
            content: TextField(
              controller: ctrl,
              obscureText: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'كلمة المرور الحالية',
                border: const OutlineInputBorder(),
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
                  final ok =
                      await AuthService.verifyPassword(ctrl.text.trim());
                  if (!ok) {
                    setSt(() => error = 'غير صحيحة');
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

    if (ok != true) return;
    await AuthService.setEnabled(false);
    await AuthService.removePassword();
    if (mounted) setState(() {});
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
