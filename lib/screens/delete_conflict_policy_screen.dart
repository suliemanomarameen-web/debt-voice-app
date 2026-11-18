import 'package:flutter/material.dart';
import '../config/app_settings.dart';
import '../services/settings_service.dart';
import '../services/permission_gate.dart';
import '../services/logger_service.dart';

class DeleteConflictPolicyScreen extends StatefulWidget {
  const DeleteConflictPolicyScreen({super.key});

  @override
  State<DeleteConflictPolicyScreen> createState() =>
      _DeleteConflictPolicyScreenState();
}

class _DeleteConflictPolicyScreenState
    extends State<DeleteConflictPolicyScreen> {
  bool _busy = false;

  String get _softMode {
    if (SettingsService.getBool(AppSettings.softDeleteAlwaysWins)) {
      return 'delete';
    }
    if (SettingsService.getBool(AppSettings.softModificationAlwaysWins)) {
      return 'modification';
    }
    return 'latest';
  }

  String get _permanentMode {
    if (SettingsService.getBool(AppSettings.permanentDeleteAlwaysWins,
        defaultValue: true)) {
      return 'delete';
    }
    if (SettingsService.getBool(AppSettings.modificationAlwaysWins)) {
      return 'modification';
    }
    return 'latest';
  }

  Future<void> _change({required bool softDelete, required String mode}) async {
    if (_busy) return;
    if (!await PermissionGate.requirePassword(
      context,
      title: 'تأكيد تغيير سياسة الحذف',
      message: 'أدخل كلمة المرور لتغيير سياسة التعارض بين الحذف والتعديل.',
    )) return;

    if (!mounted) return;
    setState(() => _busy = true);
    final oldMode = softDelete ? _softMode : _permanentMode;
    final ok = await SettingsService.setDeleteConflictPolicy(
      softDelete: softDelete,
      mode: mode,
    );

    if (!mounted) return;
    setState(() => _busy = false);

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لم يتم تغيير السياسة. تحقق من صلاحيتك ثم أعد المحاولة.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    await LoggerService.logSettingChanged(
      settingName: softDelete ? 'سياسة الحذف المؤقت' : 'سياسة الحذف النهائي',
      oldValue: _modeLabel(oldMode),
      newValue: _modeLabel(mode),
    );

    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          softDelete
              ? 'تم حفظ طلب تغيير سياسة الحذف المؤقت'
              : 'تم حفظ طلب تغيير سياسة الحذف النهائي',
        ),
      ),
    );
  }

  String _modeLabel(String mode) {
    switch (mode) {
      case 'delete':
        return 'الحذف يفوز دائماً';
      case 'modification':
        return 'التعديل يفوز دائماً';
      default:
        return 'الأحدث يفوز';
    }
  }

  Widget _policySection({
    required String title,
    required String description,
    required String selected,
    required bool softDelete,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(description,
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 14),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                    value: 'delete',
                    label: Text('الحذف يفوز', textAlign: TextAlign.center)),
                ButtonSegment(
                    value: 'modification',
                    label: Text('التعديل يفوز', textAlign: TextAlign.center)),
                ButtonSegment(
                    value: 'latest',
                    label: Text('الأحدث يفوز', textAlign: TextAlign.center)),
              ],
              selected: {selected},
              onSelectionChanged: _busy
                  ? null
                  : (values) => _change(
                      softDelete: softDelete, mode: values.first),
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: LinearProgressIndicator(),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('سياسة الحذف والتعديل')),
        body: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                'اختر كيف يتصرف التطبيق عند تعارض الحذف مع تعديل أحدث أو أقدم. '
                'كل سياسة مستقلة عن الأخرى.',
                style: TextStyle(fontSize: 13, height: 1.5),
              ),
            ),
            _policySection(
              title: 'الحذف المؤقت (سلة المحذوفات)',
              description:
                  'يتحكم في التعارض بين نقل العملية إلى سلة المحذوفات وبين تعديلها.',
              selected: _softMode,
              softDelete: true,
            ),
            _policySection(
              title: 'الحذف النهائي',
              description:
                  'يتحكم في التعارض مع الحذف النهائي وشاهد القبر الذي يمنع عودة العملية.',
              selected: _permanentMode,
              softDelete: false,
            ),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'عند تغيير السياسة من جهاز محاسب، يُرسل الطلب إلى الجهاز الأساسي '
                'للتحقق من الصلاحية واعتماده قبل نشره على بقية الأجهزة.',
                style: TextStyle(fontSize: 11, color: Colors.grey, height: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
