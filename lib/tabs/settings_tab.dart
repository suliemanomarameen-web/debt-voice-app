import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../db/database_helper.dart';
import '../models/log_event.dart';
import '../services/accountant_service.dart';
import '../services/auth_service.dart';
import '../services/auto_backup_service.dart';
import '../services/backup_service.dart';
import '../services/cloud_backup_service.dart';
import '../services/code_service.dart';
import '../services/export_service.dart';
import '../services/gdrive_service.dart';
import '../services/logger_service.dart';
import '../services/overlay_service.dart';
import '../services/permission_service.dart';
import '../services/reminder_service.dart';
import '../services/speech_service.dart';
import '../services/theme_service.dart';
import '../screens/gdrive_screen.dart';
import '../screens/logs_screen.dart';
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
  bool _autoWhatsApp = false;

  String? _accountantName;

  bool _codeEnabled = true;
  String _debtPrefix = 'D';
  String _paymentPrefix = 'P';
  String _returnPrefix = 'R';
  int _codeDigits = 4;
  String _codeMode = 'sequential';

  bool _pdfShowCodes = true;
  bool _pdfHideCategory = false;
  bool _pdfHideAccountType = false;

  bool _cloudBackupEnabled = false;
  BackupFrequency _cloudFrequency = BackupFrequency.daily;
  int _cloudMaxBackups = 10;

  @override
  void initState() {
    super.initState();
    _checkStatus();
    _loadVersion();
    _loadAutoBackup();
    _checkGDrive();
    _loadAutoWhatsApp();
    _loadCodeSettings();
    _loadCloudBackupSettings();
    _loadPdfSettings();
    _loadAccountantName();
  }

  Future<void> _loadAccountantName() async {
    final name = await AccountantService.getAccountantName();
    if (!mounted) return;
    setState(() => _accountantName = name);
  }

  Future<void> _loadAutoWhatsApp() async {
    final sp = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _autoWhatsApp = sp.getBool('auto_whatsapp') ?? false;
    });
  }

  Future<void> _loadPdfSettings() async {
    final sp = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _pdfShowCodes = sp.getBool('pdf_show_codes') ?? true;
      _pdfHideCategory = sp.getBool('pdf_hide_category') ?? false;
      _pdfHideAccountType = sp.getBool('pdf_hide_account_type') ?? false;
    });
  }

  Future<void> _loadCodeSettings() async {
    final enabled = await CodeService.isEnabled();
    final d = await CodeService.getDebtPrefix();
    final p = await CodeService.getPaymentPrefix();
    final r = await CodeService.getReturnPrefix();
    final digits = await CodeService.getDigits();
    final mode = await CodeService.getMode();
    if (!mounted) return;
    setState(() {
      _codeEnabled = enabled;
      _debtPrefix = d;
      _paymentPrefix = p;
      _returnPrefix = r;
      _codeDigits = digits;
      _codeMode = mode;
    });
  }

  Future<void> _loadCloudBackupSettings() async {
    final enabled = await CloudBackupService.isEnabled();
    final freq = await CloudBackupService.getFrequency();
    final max = await CloudBackupService.getMaxBackups();
    if (!mounted) return;
    setState(() {
      _cloudBackupEnabled = enabled;
      _cloudFrequency = freq;
      _cloudMaxBackups = max;
    });
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

  // ============== اسم المحاسب ==============
  Future<void> _editAccountantName() async {
    final oldName = _accountantName;
    final ctrl = TextEditingController(text: _accountantName ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.person, color: Colors.teal),
              SizedBox(width: 8),
              Text('اسم المحاسب'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl,
                textCapitalization: TextCapitalization.words,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'الاسم',
                  hintText: 'مثال: سليمان، أحمد...',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'يُسجَّل هذا الاسم مع كل عملية تضيفها من هذا الجهاز، '
                'لتتمكن من معرفة من أضاف كل عملية عند المزامنة.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            if (_accountantName != null && _accountantName!.isNotEmpty)
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx, '__CLEAR__');
                },
                child: const Text(
                  'حذف',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () {
                final v = ctrl.text.trim();
                Navigator.pop(ctx, v);
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;

    if (result == '__CLEAR__') {
      await AccountantService.clearAccountantName();
      // 🆕 تسجيل الحدث
      await LoggerService.info(
        'حذف اسم المحاسب',
        'الاسم السابق: "${oldName ?? ""}"',
        category: LogCategory.settings,
      );
      if (!mounted) return;
      setState(() => _accountantName = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم حذف اسم المحاسب'),
          backgroundColor: Colors.grey,
        ),
      );
      return;
    }

    if (result.isEmpty) {
      await AccountantService.clearAccountantName();
      await LoggerService.info(
        'حذف اسم المحاسب',
        'الاسم السابق: "${oldName ?? ""}"',
        category: LogCategory.settings,
      );
      if (!mounted) return;
      setState(() => _accountantName = null);
      return;
    }

    await AccountantService.setAccountantName(result);
    // 🆕 تسجيل الحدث
    await LoggerService.info(
      oldName == null || oldName.isEmpty ? 'إضافة اسم محاسب' : 'تغيير اسم المحاسب',
      'الاسم: "$result"${oldName != null ? ' (السابق: "$oldName")' : ''}',
      category: LogCategory.settings,
    );
    if (!mounted) return;
    setState(() => _accountantName = result);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✅ تم حفظ اسم المحاسب: $result'),
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
      // 🆕 تسجيل الحدث
      await LoggerService.logBackupCreated(
        customersCount: result.customersCount,
        transactionsCount: result.transactionsCount,
        cloud: false,
      );

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
        type: FileType.any,
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

    // 🆕 تسجيل الحدث
    await LoggerService.logBackupRestored(
      customersAdded: result.customersAdded,
      transactionsAdded: result.transactionsAdded,
      mode: mode,
    );

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

  // ============== النسخ التلقائي المحلي ==============
  Future<void> _toggleAutoBackup(bool v) async {
    await AutoBackupService.setEnabled(v);
    // 🆕 تسجيل الحدث
    await LoggerService.logSettingChanged(
      settingName: 'النسخ التلقائي المحلي',
      oldValue: _autoEnabled ? 'مُفعّل' : 'مُعطّل',
      newValue: v ? 'مُفعّل' : 'مُعطّل',
    );
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
    // 🆕 تسجيل الحدث
    await LoggerService.logSettingChanged(
      settingName: 'تكرار النسخ التلقائي',
      oldValue: _freqLabel(_autoFreq),
      newValue: _freqLabel(result),
    );
    if (!mounted) return;
    setState(() => _autoFreq = result);
  }

  String _freqLabel(String f) {
    return {'daily': 'يومياً', 'weekly': 'أسبوعياً', 'monthly': 'شهرياً'}[f] ??
        f;
  }

  // ============== النسخ السحابي ==============
  Future<void> _toggleCloudBackup(bool v) async {
    if (v && !GDriveService.isSignedIn) {
      final err = await GDriveService.signInWithError();
      if (err != null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('يجب تسجيل الدخول: $err')),
        );
        return;
      }
    }

    await CloudBackupService.setEnabled(v);
    // 🆕 تسجيل الحدث
    await LoggerService.logSettingChanged(
      settingName: 'النسخ السحابي التلقائي',
      oldValue: _cloudBackupEnabled ? 'مُفعّل' : 'مُعطّل',
      newValue: v ? 'مُفعّل' : 'مُعطّل',
    );
    if (!mounted) return;
    setState(() => _cloudBackupEnabled = v);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(v
            ? 'تم تفعيل النسخ السحابي التلقائي'
            : 'تم إيقاف النسخ السحابي'),
        backgroundColor: v ? Colors.green : Colors.grey,
      ),
    );
  }

  Future<void> _changeCloudFrequency() async {
    final result = await showDialog<BackupFrequency>(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: SimpleDialog(
          title: const Text('تكرار النسخ السحابي'),
          children: BackupFrequency.values.map((f) {
            final selected = _cloudFrequency == f;
            return SimpleDialogOption(
              onPressed: () => Navigator.pop(context, f),
              child: Row(
                children: [
                  if (selected)
                    const Icon(Icons.check, color: Colors.green)
                  else
                    const SizedBox(width: 24),
                  const SizedBox(width: 8),
                  Text(CloudBackupService.frequencyLabel(f)),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
    if (result == null) return;
    await CloudBackupService.setFrequency(result);
    // 🆕 تسجيل الحدث
    await LoggerService.logSettingChanged(
      settingName: 'تكرار النسخ السحابي',
      oldValue: CloudBackupService.frequencyLabel(_cloudFrequency),
      newValue: CloudBackupService.frequencyLabel(result),
    );
    if (!mounted) return;
    setState(() => _cloudFrequency = result);
  }

  Future<void> _changeCloudMaxBackups() async {
    final ctrl = TextEditingController(
      text: _cloudMaxBackups < 0 ? '' : _cloudMaxBackups.toString(),
    );
    bool notLimited = _cloudMaxBackups < 0;

    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (ctx, setSt) => AlertDialog(
            title: const Text('عدد النسخ المحفوظة'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('غير نهائي'),
                  subtitle: const Text('احتفظ بكل النسخ بدون حذف'),
                  value: notLimited,
                  onChanged: (v) => setSt(() => notLimited = v),
                ),
                if (!notLimited)
                  TextField(
                    controller: ctrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'عدد النسخ',
                      border: OutlineInputBorder(),
                      hintText: 'مثال: 10',
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () {
                  if (notLimited) {
                    Navigator.pop(ctx, -1);
                  } else {
                    final n = int.tryParse(ctrl.text.trim());
                    if (n == null || n < 1) return;
                    Navigator.pop(ctx, n);
                  }
                },
                child: const Text('حفظ'),
              ),
            ],
          ),
        ),
      ),
    );

    if (result == null) return;
    await CloudBackupService.setMaxBackups(result);
    // 🆕 تسجيل الحدث
    await LoggerService.logSettingChanged(
      settingName: 'عدد النسخ السحابية المحفوظة',
      oldValue: _cloudMaxBackups < 0 ? 'غير نهائي' : '$_cloudMaxBackups',
      newValue: result < 0 ? 'غير نهائي' : '$result',
    );
    if (!mounted) return;
    setState(() => _cloudMaxBackups = result);
  }

  Future<void> _runCloudBackupNow() async {
    if (!GDriveService.isSignedIn) {
      final err = await GDriveService.signInWithError();
      if (err != null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(err)),
        );
        return;
      }
    }

    setState(() => _backupBusy = true);
    await CloudBackupService.runNow();
    if (!mounted) return;
    setState(() => _backupBusy = false);

    // 🆕 تسجيل الحدث (النسخ السحابي التلقائي في CloudBackupService يسجل بنفسه)

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم تشغيل النسخ السحابي'),
        backgroundColor: Colors.green,
      ),
    );
  }

  // ============== إعدادات الرموز ==============
  Future<void> _toggleCodeEnabled(bool v) async {
    await CodeService.setEnabled(v);
    // 🆕 تسجيل الحدث
    await LoggerService.logSettingChanged(
      settingName: 'تفعيل رموز العمليات',
      oldValue: _codeEnabled ? 'مُفعّل' : 'مُعطّل',
      newValue: v ? 'مُفعّل' : 'مُعطّل',
    );
    if (!mounted) return;
    setState(() => _codeEnabled = v);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(v ? 'تم تفعيل رموز العمليات' : 'تم تعطيل رموز العمليات'),
        backgroundColor: v ? Colors.green : Colors.grey,
      ),
    );
  }

  Future<void> _editPrefix(String type) async {
    String current;
    String label;
    if (type == 'debt') {
      current = _debtPrefix;
      label = 'رمز الدين';
    } else if (type == 'payment') {
      current = _paymentPrefix;
      label = 'رمز السداد';
    } else {
      current = _returnPrefix;
      label = 'رمز المرتجع';
    }

    final ctrl = TextEditingController(text: current);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(label),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl,
                maxLength: 3,
                textAlign: TextAlign.center,
                textCapitalization: TextCapitalization.characters,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'مثال: D',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'حرف أو رمز قصير (1-3 أحرف)',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () {
                final v = ctrl.text.trim();
                if (v.isEmpty) return;
                Navigator.pop(ctx, v);
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;
    final newPrefix = result.toUpperCase();
    final oldPrefix = current;

    if (newPrefix != oldPrefix && mounted) {
      final updateOld = await showDialog<bool>(
        context: context,
        builder: (ctx) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.update, color: Colors.orange),
                SizedBox(width: 8),
                Text('تحديث الرموز القديمة؟'),
              ],
            ),
            content: Text(
              'لقد غيّرت الرمز من "$oldPrefix" إلى "$newPrefix".\n\n'
              'هل تريد تحديث رموز العمليات القديمة أيضاً؟\n\n'
              'مثال: $oldPrefix-0001 → $newPrefix-0001\n\n'
              '⚠️ إذا اخترت "لا"، ستحتفظ العمليات القديمة برموزها الحالية.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('لا، اتركها'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('نعم، حدّثها'),
              ),
            ],
          ),
        ),
      );

      // تحديث الرموز القديمة أولاً
      if (updateOld == true && mounted) {
        setState(() => _backupBusy = true);
        final count = await CodeService.updateOldCodes(
          oldPrefix: oldPrefix,
          newPrefix: newPrefix,
        );
        if (!mounted) return;
        setState(() => _backupBusy = false);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم تحديث $count عملية'),
            backgroundColor: Colors.green,
          ),
        );
      }

      // 🆕 تسجيل الحدث
      await LoggerService.logCodeChanged(
        type: label,
        oldPrefix: oldPrefix,
        newPrefix: newPrefix,
        updatedCount: updateOld == true ? 0 : 0,
      );

      // حفظ البادئة الجديدة
      if (type == 'debt') {
        await CodeService.setDebtPrefix(newPrefix);
        if (mounted) setState(() => _debtPrefix = newPrefix);
      } else if (type == 'payment') {
        await CodeService.setPaymentPrefix(newPrefix);
        if (mounted) setState(() => _paymentPrefix = newPrefix);
      } else {
        await CodeService.setReturnPrefix(newPrefix);
        if (mounted) setState(() => _returnPrefix = newPrefix);
      }
    } else {
      if (type == 'debt') {
        await CodeService.setDebtPrefix(newPrefix);
        if (mounted) setState(() => _debtPrefix = newPrefix);
      } else if (type == 'payment') {
        await CodeService.setPaymentPrefix(newPrefix);
        if (mounted) setState(() => _paymentPrefix = newPrefix);
      } else {
        await CodeService.setReturnPrefix(newPrefix);
        if (mounted) setState(() => _returnPrefix = newPrefix);
      }
    }
  }

  Future<void> _changeDigits() async {
    final result = await showDialog<int>(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: SimpleDialog(
          title: const Text('عدد الأرقام في الرمز'),
          children: [4, 6, 8].map((d) {
            final max = CodeService.getMaxPossible(d);
            return SimpleDialogOption(
              onPressed: () => Navigator.pop(context, d),
              child: Row(
                children: [
                  if (_codeDigits == d)
                    const Icon(Icons.check, color: Colors.green)
                  else
                    const SizedBox(width: 24),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$d أرقام',
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        Text(
                          'يسمح بـ ${_formatNumber(max)} عملية',
                          style: const TextStyle(
                              fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );

    if (result == null) return;
    await CodeService.setDigits(result);
    // 🆕 تسجيل الحدث
    await LoggerService.logSettingChanged(
      settingName: 'عدد أرقام الرموز',
      oldValue: '$_codeDigits',
      newValue: '$result',
    );
    if (!mounted) return;
    setState(() => _codeDigits = result);
  }

  Future<void> _changeCodeMode() async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: SimpleDialog(
          title: const Text('طريقة توليد الرمز'),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, 'sequential'),
              child: Row(
                children: [
                  if (_codeMode == 'sequential')
                    const Icon(Icons.check, color: Colors.green)
                  else
                    const SizedBox(width: 24),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('مرتب (تسلسلي)',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        Text('D-0001, D-0002, D-0003...',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, 'random'),
              child: Row(
                children: [
                  if (_codeMode == 'random')
                    const Icon(Icons.check, color: Colors.green)
                  else
                    const SizedBox(width: 24),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('عشوائي',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        Text('D-4821, D-1938, D-7305...',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;
    await CodeService.setMode(result);
    // 🆕 تسجيل الحدث
    await LoggerService.logSettingChanged(
      settingName: 'طريقة توليد الرمز',
      oldValue: CodeService.describeMode(_codeMode),
      newValue: CodeService.describeMode(result),
    );
    if (!mounted) return;
    setState(() => _codeMode = result);
  }

  String _formatNumber(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  // ============== إعدادات PDF ==============
  Future<void> _togglePdfSetting(String key, bool v) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(key, v);

    // 🆕 تسجيل الحدث
    String settingName;
    if (key == 'pdf_show_codes') {
      settingName = 'إظهار رموز العمليات في PDF';
    } else if (key == 'pdf_hide_category') {
      settingName = 'إخفاء التصنيف من PDF';
    } else {
      settingName = 'إخفاء نوع الحساب من PDF';
    }
    await LoggerService.logSettingChanged(
      settingName: settingName,
      oldValue: v ? 'مُعطّل' : 'مُفعّل',
      newValue: v ? 'مُفعّل' : 'مُعطّل',
    );

    if (!mounted) return;
    setState(() {
      if (key == 'pdf_show_codes') _pdfShowCodes = v;
      if (key == 'pdf_hide_category') _pdfHideCategory = v;
      if (key == 'pdf_hide_account_type') _pdfHideAccountType = v;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeService>();
    final isDark = theme.mode == ThemeMode.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(
        children: [
          // ========== قسم المحاسب ==========
          const _SectionHeader('المحاسب'),
          ListTile(
            leading: Icon(
              Icons.person,
              color: _accountantName != null ? Colors.teal : Colors.grey,
            ),
            title: const Text('اسم المحاسب'),
            subtitle: Text(
              _accountantName ?? 'لم يتم ضبطه - اضغط للإضافة',
              style: TextStyle(
                color: _accountantName != null ? Colors.teal : Colors.grey,
                fontWeight: _accountantName != null
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
            ),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: _editAccountantName,
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.teal.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.teal.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 16, color: Colors.teal),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'يُسجَّل هذا الاسم مع كل عملية تضيفها من هذا الجهاز. '
                    'يساعدك على معرفة من أضاف كل عملية عند المزامنة مع أجهزة أخرى.',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.teal.shade200 : Colors.teal.shade900,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // ========== 🆕 قسم السجل ==========
          const _SectionHeader('سجل الأحداث'),
          ListTile(
            leading: const Icon(Icons.history, color: Colors.deepPurple),
            title: const Text('عرض سجل الأحداث'),
            subtitle: const Text('كل ما يحدث داخل التطبيق'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LogsScreen()),
              );
            },
          ),

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

          // ========== الإشعارات والواتساب ==========
          const _SectionHeader('الإشعارات والواتساب'),
          SwitchListTile(
            secondary: const Icon(Icons.message, color: Colors.green),
            title: const Text('إرسال رسالة واتساب تلقائياً'),
            subtitle: const Text(
                'بعد كل عملية جديدة، يفتح واتساب مع رسالة جاهزة للعميل'),
            value: _autoWhatsApp,
            onChanged: (v) async {
              setState(() => _autoWhatsApp = v);
              final sp = await SharedPreferences.getInstance();
              await sp.setBool('auto_whatsapp', v);
              // 🆕 تسجيل الحدث
              await LoggerService.logSettingChanged(
                settingName: 'إرسال واتساب تلقائياً',
                oldValue: v ? 'مُعطّل' : 'مُفعّل',
                newValue: v ? 'مُفعّل' : 'مُعطّل',
              );
            },
          ),

          // ========== رموز العمليات ==========
          const _SectionHeader('رموز العمليات'),
          SwitchListTile(
            secondary: const Icon(Icons.qr_code, color: Colors.blue),
            title: const Text('تفعيل رموز العمليات'),
            subtitle: const Text(
                'إعطاء رمز فريد لكل عملية (مثل D-0001، P-0002)'),
            value: _codeEnabled,
            onChanged: _toggleCodeEnabled,
          ),
          if (_codeEnabled) ...[
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.arrow_upward, color: Colors.red),
              title: const Text('رمز الدين'),
              trailing: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _debtPrefix,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.red,
                  ),
                ),
              ),
              onTap: () => _editPrefix('debt'),
            ),
            ListTile(
              leading: const Icon(Icons.payments, color: Colors.green),
              title: const Text('رمز السداد'),
              trailing: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _paymentPrefix,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.green,
                  ),
                ),
              ),
              onTap: () => _editPrefix('payment'),
            ),
            ListTile(
              leading:
                  const Icon(Icons.keyboard_return, color: Colors.orange),
              title: const Text('رمز المرتجع'),
              trailing: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _returnPrefix,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.orange,
                  ),
                ),
              ),
              onTap: () => _editPrefix('return'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.numbers, color: Colors.purple),
              title: const Text('عدد الأرقام'),
              subtitle: Text(
                  'يسمح بـ ${_formatNumber(CodeService.getMaxPossible(_codeDigits))} عملية'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$_codeDigits',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios, size: 16),
                ],
              ),
              onTap: _changeDigits,
            ),
            ListTile(
              leading: const Icon(Icons.shuffle, color: Colors.indigo),
              title: const Text('طريقة التوليد'),
              subtitle: Text(CodeService.describeMode(_codeMode)),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: _changeCodeMode,
            ),
            Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.blue.shade900.withOpacity(0.3)
                    : Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.withOpacity(0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.preview, size: 18, color: Colors.blue),
                      SizedBox(width: 6),
                      Text(
                        'معاينة',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _previewChip(
                          '$_debtPrefix-${'1'.padLeft(_codeDigits, '0')}',
                          Colors.red),
                      _previewChip(
                          '$_paymentPrefix-${'1'.padLeft(_codeDigits, '0')}',
                          Colors.green),
                      _previewChip(
                          '$_returnPrefix-${'1'.padLeft(_codeDigits, '0')}',
                          Colors.orange),
                    ],
                  ),
                ],
              ),
            ),
          ],

          // ========== إعدادات كشف الحساب (PDF) ==========
          const _SectionHeader('إعدادات كشف الحساب (PDF)'),
          SwitchListTile(
            secondary: const Icon(Icons.qr_code, color: Colors.blue),
            title: const Text('إظهار رموز العمليات'),
            subtitle: const Text('إظهار عمود الرمز في جدول كشف الحساب'),
            value: _pdfShowCodes,
            onChanged: (v) => _togglePdfSetting('pdf_show_codes', v),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.star, color: Colors.amber),
            title: const Text('إخفاء التصنيف'),
            subtitle: const Text('إخفاء "عادي / VIP / جديد..." من كشف الحساب'),
            value: _pdfHideCategory,
            onChanged: (v) => _togglePdfSetting('pdf_hide_category', v),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.person, color: Colors.teal),
            title: const Text('إخفاء نوع الحساب'),
            subtitle:
                const Text('إخفاء "عميل / مورد / أخرى" من كشف الحساب'),
            value: _pdfHideAccountType,
            onChanged: (v) => _togglePdfSetting('pdf_hide_account_type', v),
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
          const _SectionHeader('النسخ الاحتياطي المحلي'),
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

          // ========== النسخ التلقائي المحلي ==========
          SwitchListTile(
            secondary: const Icon(Icons.schedule, color: Colors.purple),
            title: const Text('النسخ التلقائي المحلي'),
            subtitle: Text(_autoEnabled
                ? 'النسخ كل ${_freqLabel(_autoFreq)}'
                : 'نسخ احتياطي في الخلفية (محلي)'),
            value: _autoEnabled,
            onChanged: _toggleAutoBackup,
          ),
          if (_autoEnabled) ...[
            ListTile(
              leading: const Icon(Icons.repeat),
              title: const Text('تكرار النسخ'),
              subtitle: Text(_freqLabel(_autoFreq)),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: _changeFreq,
            ),
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
          ],

          // ========== النسخ السحابي ==========
          const _SectionHeader('النسخ السحابي (Google Drive)'),
          ListTile(
            leading: Icon(
              Icons.cloud,
              color: _gdriveSignedIn ? Colors.green : Colors.blue,
            ),
            title: const Text('حالة الحساب'),
            subtitle: Text(_gdriveSignedIn
                ? 'متصل: ${GDriveService.userEmail ?? ""}'
                : 'لم يتم تسجيل الدخول'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const GDriveScreen()),
              );
              _checkGDrive();
            },
          ),
          SwitchListTile(
            secondary:
                const Icon(Icons.cloud_upload, color: Colors.deepPurple),
            title: const Text('النسخ السحابي التلقائي'),
            subtitle: Text(_cloudBackupEnabled
                ? 'يتم رفع نسخة ${CloudBackupService.frequencyLabel(_cloudFrequency)}'
                : 'رفع نسخة احتياطية تلقائياً إلى Drive'),
            value: _cloudBackupEnabled,
            onChanged: _toggleCloudBackup,
          ),
          if (_cloudBackupEnabled) ...[
            ListTile(
              leading: const Icon(Icons.schedule, color: Colors.deepPurple),
              title: const Text('تكرار الرفع'),
              subtitle:
                  Text(CloudBackupService.frequencyLabel(_cloudFrequency)),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: _changeCloudFrequency,
            ),
            ListTile(
              leading: const Icon(Icons.storage, color: Colors.indigo),
              title: const Text('عدد النسخ المحفوظة'),
              subtitle: Text(
                _cloudMaxBackups < 0
                    ? 'غير نهائي'
                    : 'آخر $_cloudMaxBackups نسخة',
              ),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: _changeCloudMaxBackups,
            ),
            ListTile(
              leading:
                  const Icon(Icons.play_circle, color: Colors.deepPurple),
              title: const Text('رفع نسخة الآن'),
              subtitle: const Text('تشغيل النسخ السحابي يدوياً'),
              onTap: _backupBusy ? null : _runCloudBackupNow,
            ),
          ],

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

  Widget _previewChip(String code, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.5), width: 0.5),
      ),
      child: Text(
        code,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: color,
          fontFamily: 'monospace',
        ),
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

    // 🆕 تسجيل الحدث
    await LoggerService.logSecurityEvent(
      action: 'تفعيل القفل',
      description: 'تم تفعيل قفل التطبيق بكلمة مرور',
    );

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

    // 🆕 تسجيل الحدث
    await LoggerService.logSecurityEvent(
      action: 'تعطيل القفل',
      description: 'تم تعطيل قفل التطبيق',
    );

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
