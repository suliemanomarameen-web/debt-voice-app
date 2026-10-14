import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../services/keywords_service.dart';
import '../services/logger_service.dart';
import '../services/overlay_service.dart';
import '../services/permission_service.dart';
import '../services/recovery_service.dart';
import '../services/reminder_service.dart';
import '../services/speech_service.dart';
import '../services/theme_service.dart';
import '../screens/gdrive_screen.dart';
import '../screens/keywords_screen.dart';
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

  bool _filterEmptyVoice = true;
  bool _filterUnclearText = true;
  bool _filterOtherErrors = true;
  bool _filterOtherWarnings = true;

  // 🆕 الاستعادة (بدون واتساب)
  bool _hasRecoveryCode = false;
  bool _hasSecurityQuestion = false;

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
    _loadPendingFilters();
    _loadRecoveryInfo();
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

  Future<void> _loadPendingFilters() async {
    final sp = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _filterEmptyVoice = sp.getBool('pending_filter_empty') ?? true;
      _filterUnclearText = sp.getBool('pending_filter_unclear') ?? true;
      _filterOtherErrors = sp.getBool('pending_filter_errors') ?? true;
      _filterOtherWarnings = sp.getBool('pending_filter_warnings') ?? true;
    });
  }

  Future<void> _loadRecoveryInfo() async {
    final hasCode = await RecoveryService.hasRecoveryCode();
    final hasQ = await RecoveryService.hasSecurityQuestion();
    if (!mounted) return;
    setState(() {
      _hasRecoveryCode = hasCode;
      _hasSecurityQuestion = hasQ;
    });
  }

  Future<void> _togglePendingFilter(String key, bool v) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(key, v);

    await LoggerService.logSettingChanged(
      settingName: key
          .replaceFirst('pending_filter_', 'فلتر ')
          .replaceAll('_', ' '),
      oldValue: v ? 'معطّل' : 'مفعّل',
      newValue: v ? 'مفعّل' : 'معطّل',
    );

    if (!mounted) return;
    setState(() {
      if (key == 'pending_filter_empty') _filterEmptyVoice = v;
      if (key == 'pending_filter_unclear') _filterUnclearText = v;
      if (key == 'pending_filter_errors') _filterOtherErrors = v;
      if (key == 'pending_filter_warnings') _filterOtherWarnings = v;
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

// ═══════════════════════════════════════════════════════════
// 🆕 طلب كلمة المرور (للإجراءات الحساسة)
// ═══════════════════════════════════════════════════════════
Future<String?> _askForPassword() async {
  final ctrl = TextEditingController();
  String? error;

  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => Directionality(
      textDirection: TextDirection.rtl,
      child: StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.lock_outline, color: Colors.orange),
              SizedBox(width: 8),
              Text('تأكيد الهوية'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'أدخل كلمة المرور الحالية للمتابعة',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                obscureText: true,
                keyboardType: TextInputType.number,
                autofocus: true,
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  labelText: 'كلمة المرور',
                  border: const OutlineInputBorder(),
                  errorText: error,
                  prefixIcon: const Icon(Icons.lock),
                ),
                onSubmitted: (v) async {
                  final ok = await AuthService.verifyPassword(v.trim());
                  if (ok) {
                    Navigator.pop(ctx, v.trim());
                  } else {
                    setSt(() => error = 'كلمة المرور غير صحيحة');
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
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
                if (ok) {
                  if (ctx.mounted) Navigator.pop(ctx, pwd);
                } else {
                  setSt(() => error = 'كلمة المرور غير صحيحة');
                  ctrl.clear();
                }
              },
              child: const Text('تأكيد'),
            ),
          ],
        ),
      ),
    ),
  );

  return result;
}

// ═══════════════════════════════════════════════════════════
// 🆕 عرض رمز الاسترداد (يتطلب كلمة المرور)
// ═══════════════════════════════════════════════════════════
Future<void> _showRecoveryCode() async {
  // 1. اطلب كلمة المرور أولاً
  final pwd = await _askForPassword();
  if (pwd == null) return;

  // 2. جلب الرمز
  final code = await RecoveryService.getRecoveryCodePlain();
  if (!mounted || code == null) return;

  await showDialog(
    context: context,
    builder: (ctx) => Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.vpn_key, color: Colors.deepPurple),
            SizedBox(width: 8),
            Text('رمز الاسترداد'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.deepPurple.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.deepPurple.withOpacity(0.4)),
              ),
              child: SelectableText(
                code,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                  color: Colors.deepPurple,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '📌 احفظ هذا الرمز في مكان آمن\n'
              'سيُستخدم لاستعادة كلمة المرور إذا نسيتها.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: code));
              if (!ctx.mounted) return;
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(
                  content: Text('✅ تم نسخ الرمز'),
                  backgroundColor: Colors.green,
                ),
              );
            },
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('نسخ'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx),
            icon: const Icon(Icons.check, size: 16),
            label: const Text('تم'),
          ),
        ],
      ),
    ),
  );
}

// ═══════════════════════════════════════════════════════════
// 🆕 توليد رمز جديد (يتطلب كلمة المرور)
// ═══════════════════════════════════════════════════════════
Future<void> _generateNewRecoveryCode() async {
  // 1. اطلب كلمة المرور أولاً
  final pwd = await _askForPassword();
  if (pwd == null) return;

  // 2. اطلب تأكيد
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.refresh, color: Colors.orange),
            SizedBox(width: 8),
            Text('توليد رمز جديد'),
          ],
        ),
        content: const Text(
          'سيتم إنشاء رمز استرداد جديد.\n\n'
          '⚠️ الرمز القديم سيتوقف عن العمل.',
          style: TextStyle(fontSize: 12),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('توليد'),
          ),
        ],
      ),
    ),
  );

  if (ok != true) return;

  final newCode = RecoveryService.generateRecoveryCode();
  await RecoveryService.setRecoveryCode(newCode);
  await LoggerService.logSecurityEvent(
    action: 'توليد رمز استرداد جديد',
    description: 'تم إنشاء رمز استرداد جديد',
  );
  await _loadRecoveryInfo();

  if (!mounted) return;
  await _showRecoveryCode();
}

// ═══════════════════════════════════════════════════════════
// 🆕 تغيير سؤال الأمان (يتطلب كلمة المرور)
// ═══════════════════════════════════════════════════════════
Future<void> _editSecurityQuestion() async {
  final currentQuestion = await RecoveryService.getSecurityQuestion();
  final isCustom = await RecoveryService.isQuestionCustom();

  final pwdCtrl = TextEditingController();
  final answerCtrl = TextEditingController();
  final customQuestionCtrl = TextEditingController(
    text: isCustom ? (currentQuestion ?? '') : '',
  );

  String selectedQuestion = isCustom
      ? '__CUSTOM__'
      : (currentQuestion ?? RecoveryService.presetQuestions.first);

  bool showCustomField = isCustom;

  final result = await showDialog<Map<String, dynamic>>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => Directionality(
      textDirection: TextDirection.rtl,
      child: StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.help_outline, color: Colors.blue),
              SizedBox(width: 8),
              Text('تغيير سؤال الأمان'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: pwdCtrl,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'كلمة المرور الحالية',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                const Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'سؤال الأمان الجديد:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: selectedQuestion,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  isExpanded: true,
                  items: [
                    ...RecoveryService.presetQuestions.map((q) =>
                        DropdownMenuItem(value: q, child: Text(q))),
                    const DropdownMenuItem(
                      value: '__CUSTOM__',
                      child: Text('✏️ سؤال مخصص (أكتبه بنفسي)'),
                    ),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setSt(() {
                      selectedQuestion = v;
                      showCustomField = (v == '__CUSTOM__');
                    });
                  },
                ),
                if (showCustomField) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: customQuestionCtrl,
                    maxLength: 100,
                    decoration: const InputDecoration(
                      labelText: 'اكتب سؤالك المخصص',
                      hintText: 'مثال: ما اسم قطتك الأولى؟',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.edit),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                TextField(
                  controller: answerCtrl,
                  decoration: const InputDecoration(
                    labelText: 'الإجابة',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.check),
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
              onPressed: () async {
                final pwd = pwdCtrl.text.trim();
                if (pwd.isEmpty) return;
                final valid = await AuthService.verifyPassword(pwd);
                if (!valid) {
                  if (!ctx.mounted) return;
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                      content: Text('كلمة المرور غير صحيحة'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                final finalQuestion = showCustomField
                    ? customQuestionCtrl.text.trim()
                    : selectedQuestion;

                if (finalQuestion.isEmpty) {
                  if (!ctx.mounted) return;
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                      content: Text('أدخل السؤال'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }

                final answer = answerCtrl.text.trim();
                if (answer.isEmpty) {
                  if (!ctx.mounted) return;
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                      content: Text('أدخل الإجابة'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }

                Navigator.pop(ctx, {
                  'question': finalQuestion,
                  'answer': answer,
                  'isCustom': showCustomField,
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

  await RecoveryService.setSecurityQuestion(
    question: result['question'] as String,
    answer: result['answer'] as String,
    isCustom: result['isCustom'] as bool,
  );

  await LoggerService.logSecurityEvent(
    action: 'تغيير سؤال الأمان',
    description: result['isCustom'] == true
        ? 'سؤال مخصص'
        : 'سؤال جاهز',
  );

  await _loadRecoveryInfo();
  if (!mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('✅ تم حفظ سؤال الأمان'),
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
              'يُسجَّل هذا الاسم مع كل عملية تضيفها من هذا الجهاز.',
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

  if (result == '__CLEAR__' || result.isEmpty) {
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
  await LoggerService.info(
    oldName == null || oldName.isEmpty ? 'إضافة اسم محاسب' : 'تغيير اسم المحاسب',
    'الاسم: "$result"',
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
      await LoggerService.logBackupCreated(
        customersCount: result.customersCount,
        transactionsCount: result.transactionsCount,
        cloud: false,
      );

      if (!mounted) return;
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

    await LoggerService.logBackupRestored(
      customersAdded: result.customersAdded,
      transactionsAdded: result.transactionsAdded,
      mode: mode,
    );

    if (!mounted) return;
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
    await LoggerService.logSettingChanged(
      settingName: 'النسخ التلقائي المحلي',
      oldValue: _autoEnabled ? 'مُفعّل' : 'مُعطّل',
      newValue: v ? 'مُفعّل' : 'مُعطّل',
    );
    if (!mounted) return;
    setState(() => _autoEnabled = v);
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
    await LoggerService.logSettingChanged(
      settingName: 'النسخ السحابي التلقائي',
      oldValue: _cloudBackupEnabled ? 'مُفعّل' : 'مُعطّل',
      newValue: v ? 'مُفعّل' : 'مُعطّل',
    );
    if (!mounted) return;
    setState(() => _cloudBackupEnabled = v);
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
  }

  // ============== إعدادات الرموز ==============
  Future<void> _toggleCodeEnabled(bool v) async {
    await CodeService.setEnabled(v);
    await LoggerService.logSettingChanged(
      settingName: 'تفعيل رموز العمليات',
      oldValue: _codeEnabled ? 'مُفعّل' : 'مُعطّل',
      newValue: v ? 'مُفعّل' : 'مُعطّل',
    );
    if (!mounted) return;
    setState(() => _codeEnabled = v);
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
              'هل تريد تحديث رموز العمليات القديمة أيضاً؟',
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
          // ========== المحاسب ==========
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
          const SizedBox(height: 8),

          // ========== الفهم الصوتي ==========
          const _SectionHeader('الفهم الصوتي'),
          ListTile(
            leading: const Icon(Icons.record_voice_over,
                color: Colors.deepPurple),
            title: const Text('كلمات الفهم الصوتي'),
            subtitle: const Text(
                'عدّل الكلمات التي يفهمها التطبيق من صوتك'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const KeywordsScreen()),
              ).then((_) {
                if (mounted) setState(() {});
              });
            },
          ),
          const SizedBox(height: 8),

          // ========== فلترة المعلقات ==========
          const _SectionHeader('فلترة المعلقات الصوتية'),
          SwitchListTile(
            secondary: const Icon(Icons.mic_off,
                color: Colors.orange, size: 22),
            title: const Text('تسجيلات صوتية فارغة',
                style: TextStyle(fontSize: 13)),
            value: _filterEmptyVoice,
            onChanged: (v) => _togglePendingFilter('pending_filter_empty', v),
            dense: true,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.help_outline,
                color: Colors.orange, size: 22),
            title: const Text('نصوص غير مفهومة',
                style: TextStyle(fontSize: 13)),
            value: _filterUnclearText,
            onChanged: (v) => _togglePendingFilter('pending_filter_unclear', v),
            dense: true,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.error_outline,
                color: Colors.red, size: 22),
            title: const Text('أخطاء أخرى',
                style: TextStyle(fontSize: 13)),
            value: _filterOtherErrors,
            onChanged: (v) => _togglePendingFilter('pending_filter_errors', v),
            dense: true,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.warning_amber,
                color: Colors.amber, size: 22),
            title: const Text('تحذيرات أخرى',
                style: TextStyle(fontSize: 13)),
            value: _filterOtherWarnings,
            onChanged: (v) => _togglePendingFilter('pending_filter_warnings', v),
            dense: true,
          ),
          const SizedBox(height: 8),

          // ========== السجل ==========
          const _SectionHeader('سجل الأحداث'),
          ListTile(
            leading: const Icon(Icons.history, color: Colors.deepPurple),
            title: const Text('عرض سجل الأحداث'),
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
            },
          ),

          // ========== رموز العمليات ==========
          const _SectionHeader('رموز العمليات'),
          SwitchListTile(
            secondary: const Icon(Icons.qr_code, color: Colors.blue),
            title: const Text('تفعيل رموز العمليات'),
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
                child: Text(_debtPrefix,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.red)),
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
                child: Text(_paymentPrefix,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.green)),
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
                child: Text(_returnPrefix,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.orange)),
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
                  Text('$_codeDigits',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
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
          ],

          // ========== إعدادات PDF ==========
          const _SectionHeader('إعدادات كشف الحساب (PDF)'),
          SwitchListTile(
            secondary: const Icon(Icons.qr_code, color: Colors.blue),
            title: const Text('إظهار رموز العمليات'),
            value: _pdfShowCodes,
            onChanged: (v) => _togglePdfSetting('pdf_show_codes', v),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.star, color: Colors.amber),
            title: const Text('إخفاء التصنيف'),
            value: _pdfHideCategory,
            onChanged: (v) => _togglePdfSetting('pdf_hide_category', v),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.person, color: Colors.teal),
            title: const Text('إخفاء نوع الحساب'),
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

          // ========== الاستعادة ==========
          const _SectionHeader('الاستعادة'),
          ListTile(
            leading: Icon(
              Icons.vpn_key,
              color: _hasRecoveryCode ? Colors.deepPurple : Colors.grey,
            ),
            title: const Text('رمز الاسترداد'),
            subtitle: Text(
              _hasRecoveryCode
                  ? '✅ محفوظ — اضغط للعرض (يتطلب كلمة المرور)'
                  : 'لم يُنشأ بعد — اضغط للتوليد',
              style: TextStyle(
                color: _hasRecoveryCode ? Colors.deepPurple : Colors.grey,
                fontWeight:
                    _hasRecoveryCode ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () async {
              if (_hasRecoveryCode) {
                await _showRecoveryCode();
              } else {
                await _generateNewRecoveryCode();
              }
            },
          ),
          if (_hasRecoveryCode)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _generateNewRecoveryCode,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('توليد رمز جديد',
                      style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 38),
                    foregroundColor: Colors.orange,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 4),
          ListTile(
            leading: Icon(
              Icons.help_outline,
              color: _hasSecurityQuestion ? Colors.blue : Colors.grey,
            ),
            title: const Text('سؤال الأمان'),
            subtitle: Text(
              _hasSecurityQuestion
                  ? '✅ محفوظ — اضغط للتغيير (يتطلب كلمة المرور)'
                  : 'لم يُضف بعد — اضغط للإضافة',
              style: TextStyle(
                color: _hasSecurityQuestion ? Colors.blue : Colors.grey,
                fontWeight:
                    _hasSecurityQuestion ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            trailing: Icon(
              _hasSecurityQuestion ? Icons.edit : Icons.add,
              size: 18,
            ),
            onTap: _editSecurityQuestion,
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
              subtitle: Text(_cloudMaxBackups < 0
                  ? 'غير نهائي'
                  : 'آخر $_cloudMaxBackups نسخة'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: _changeCloudMaxBackups,
            ),
            ListTile(
              leading:
                  const Icon(Icons.play_circle, color: Colors.deepPurple),
              title: const Text('رفع نسخة الآن'),
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

  // ========== حوارات القفل ==========
  Future<void> _enableLockDialog() async {
    final pwd1 = TextEditingController();
    final pwd2 = TextEditingController();
    final answer = TextEditingController();
    final customQuestionCtrl = TextEditingController();

    String selectedQuestion = RecoveryService.presetQuestions.first;
    bool useCustomQuestion = false;
    String? error;

    final result = await showDialog<Map<String, dynamic>>(
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
                  const Align(
                    alignment: Alignment.centerRight,
                    child: Text('سؤال الأمان:',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: selectedQuestion,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      ...RecoveryService.presetQuestions.map((q) =>
                          DropdownMenuItem(value: q, child: Text(q))),
                      const DropdownMenuItem(
                        value: '__CUSTOM__',
                        child: Text('✏️ سؤال مخصص (أكتبه بنفسي)'),
                      ),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setSt(() {
                        selectedQuestion = v;
                        useCustomQuestion = (v == '__CUSTOM__');
                      });
                    },
                  ),
                  if (useCustomQuestion) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: customQuestionCtrl,
                      maxLength: 100,
                      decoration: const InputDecoration(
                        labelText: 'اكتب سؤالك',
                        hintText: 'مثال: ما اسم قطتك الأولى؟',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.edit),
                      ),
                    ),
                  ],
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
                  final q = useCustomQuestion
                      ? customQuestionCtrl.text.trim()
                      : selectedQuestion;

                  if (p1.length < 4) {
                    setSt(() => error = 'كلمة المرور: 4 أرقام على الأقل');
                    return;
                  }
                  if (p1 != p2) {
                    setSt(() => error = 'غير متطابقتين');
                    return;
                  }
                  if (q.isEmpty) {
                    setSt(() => error = 'أدخل السؤال');
                    return;
                  }
                  if (a.isEmpty) {
                    setSt(() => error = 'أدخل الإجابة');
                    return;
                  }
                  Navigator.pop(ctx, {
                    'pwd': p1,
                    'q': q,
                    'a': a,
                    'isCustom': useCustomQuestion,
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

    await AuthService.setPassword(result['pwd'] as String);
    await RecoveryService.setSecurityQuestion(
      question: result['q'] as String,
      answer: result['a'] as String,
      isCustom: result['isCustom'] as bool,
    );

    final recoveryCode = RecoveryService.generateRecoveryCode();
    await RecoveryService.setRecoveryCode(recoveryCode);
    await AuthService.setEnabled(true);

    await LoggerService.logSecurityEvent(
      action: 'تفعيل القفل',
      description: 'تم تفعيل القفل مع سؤال أمان ورمز استرداد',
    );

    await _loadRecoveryInfo();
    if (mounted) setState(() {});

    if (mounted) {
      await _showRecoveryCode();
    }
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
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: ctrl,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'كلمة المرور الحالية',
                    border: const OutlineInputBorder(),
                    errorText: error,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.warning_amber,
                          size: 16, color: Colors.orange),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'سيتم حذف كلمة المرور وسؤال الأمان ورمز الاسترداد.',
                          style: TextStyle(fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () async {
                  final ok =
                      await AuthService.verifyPassword(ctrl.text.trim());
                  if (!ok) {
                    setSt(() => error = 'غير صحيحة');
                    return;
                  }
                  Navigator.pop(ctx, true);
                },
                child: const Text('تعطيل'),
              ),
            ],
          ),
        ),
      ),
    );

    if (ok != true) return;

    await AuthService.setEnabled(false);
    await AuthService.removePassword();
    await RecoveryService.clearAll();

    await LoggerService.logSecurityEvent(
      action: 'تعطيل القفل',
      description: 'تم تعطيل القفل وحذف بيانات الاستعادة',
    );

    await _loadRecoveryInfo();
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
