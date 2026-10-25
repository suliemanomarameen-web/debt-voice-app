import 'package:flutter/material.dart';
import '../config/app_settings.dart';
import '../services/settings_service.dart';
import '../services/auth_service.dart';
import '../services/logger_service.dart';
import '../models/log_event.dart';

class AdvancedSettingsScreen extends StatefulWidget {
  const AdvancedSettingsScreen({super.key});

  @override
  State<AdvancedSettingsScreen> createState() =>
      _AdvancedSettingsScreenState();
}

class _AdvancedSettingsScreenState extends State<AdvancedSettingsScreen> {
  @override
  void initState() {
    super.initState();
    SettingsService.init().then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _changeBool(String key, bool value) async {
    if (AppSettings.isDangerous(key) &&
        SettingsService.getBool(
            AppSettings.requirePasswordForDangerousSettings,
            defaultValue: true)) {
      final ok = await _askForPassword();
      if (!ok) return;
    }

    final oldValue = SettingsService.getBool(key);
    await SettingsService.setBool(key, value);

    await LoggerService.logSettingChanged(
      settingName: _labelFor(key),
      oldValue: oldValue ? 'مفعّل' : 'معطّل',
      newValue: value ? 'مفعّل' : 'معطّل',
    );

    if (!mounted) return;
    setState(() {});
  }

  Future<void> _changeInt(String key, int value) async {
    if (AppSettings.isDangerous(key) &&
        SettingsService.getBool(
            AppSettings.requirePasswordForDangerousSettings,
            defaultValue: true)) {
      final ok = await _askForPassword();
      if (!ok) return;
    }

    final oldValue = SettingsService.getInt(key);
    await SettingsService.setInt(key, value);

    await LoggerService.logSettingChanged(
      settingName: _labelFor(key),
      oldValue: oldValue.toString(),
      newValue: value.toString(),
    );

    if (!mounted) return;
    setState(() {});
  }

  Future<void> _resetSetting(String key) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('استعادة الافتراضي؟'),
          content: Text('سيتم إرجاع "${_labelFor(key)}" للقيمة الافتراضية.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('استعادة'),
            ),
          ],
        ),
      ),
    );
    if (confirm != true) return;

    await SettingsService.reset(key);
    if (!mounted) return;
    setState(() {});
    _snack('✅ تمت الاستعادة', Colors.green);
  }

  Future<void> _resetGroup(String groupName, List<String> keys) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('استعادة المجموعة؟'),
          content: Text(
              'سيتم إرجاع كل إعدادات "$groupName" للقيم الافتراضية.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('استعادة'),
            ),
          ],
        ),
      ),
    );
    if (confirm != true) return;

    await SettingsService.resetGroup(keys);
    if (!mounted) return;
    setState(() {});
    _snack('✅ تمت استعادة "$groupName"', Colors.green);
  }

  Future<void> _resetAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber, color: Colors.red),
              SizedBox(width: 8),
              Text('استعادة كل الإعدادات'),
            ],
          ),
          content: const Text(
            '⚠️ سيتم إرجاع **كل** الإعدادات للقيم الافتراضية.\n\n'
            'لا يمكن التراجع.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('استعادة الكل'),
            ),
          ],
        ),
      ),
    );
    if (confirm != true) return;

    await SettingsService.resetAll();
    if (!mounted) return;
    setState(() {});
    _snack('✅ تمت استعادة كل الإعدادات', Colors.green);
  }

  Future<bool> _askForPassword() async {
    final enabled = await AuthService.isEnabled();
    if (!enabled) return true;

    final ctrl = TextEditingController();
    String? error;

    final result = await showDialog<bool>(
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
                  'هذا الإعداد خطير ويحتاج كلمة المرور.',
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
                      Navigator.pop(ctx, true);
                    } else {
                      setSt(() => error = 'غير صحيحة');
                    }
                  },
                ),
              ],
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
                  if (ok) {
                    if (ctx.mounted) Navigator.pop(ctx, true);
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

    return result == true;
  }

  void _snack(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // الأسماء العربية للإعدادات
  // ═══════════════════════════════════════════════════════════
  String _labelFor(String key) {
    const map = {
      // 🗑️ الحذف
      AppSettings.blockDeleteNonzeroBalance: 'منع حذف حساب رصيده ≠ 0',
      AppSettings.blockDeleteWithTransactions:
          'منع حذف حساب عليه عمليات',
      AppSettings.softDeleteEnabled: 'الحذف الناعم (سلة المحذوفات)',
      AppSettings.retentionDays: 'مدة الاحتفاظ في السلة',
      AppSettings.autoCleanupDeleted: 'حذف نهائي تلقائي',
      AppSettings.blockCustomerDeletion: 'منع حذف الحسابات نهائياً',
      AppSettings.blockTransactionDeletion: 'منع حذف العمليات نهائياً',

      // ✏️ التعديل
      AppSettings.allowEditTransactions:
          'السماح بتعديل العمليات',
      AppSettings.allowEditCustomerBalance:
          'السماح بتعديل الرصيد مباشرة',
      AppSettings.trackEdits: 'تسجيل كل تعديل في السجل',
      AppSettings.requireEditReason: 'طلب سبب عند التعديل',

      // 🔄 المزامنة
      AppSettings.syncEnabled: 'تفعيل المزامنة',
      AppSettings.syncIntervalMinutes: 'تكرار المزامنة',
      AppSettings.syncOnDataChange: 'مزامنة عند التعديل',
      AppSettings.syncOnAppOpen: 'مزامنة عند فتح التطبيق',
      AppSettings.autoResolveConflicts: 'حل التعارضات تلقائيًا',
      AppSettings.conflictNotification: 'إشعار عند التعارض',
      AppSettings.deletionConflictRestore:
          'استعادة الحساب دائمًا عند تعارض الحذف',
      AppSettings.syncLogs: 'مزامنة سجل الأحداث',
      AppSettings.syncDeletedBin: 'مزامنة سلة المحذوفات',

      // 📜 السجل
      AppSettings.logEnabled: 'تفعيل السجل',
      AppSettings.logRetentionDays: 'مدة الاحتفاظ بالأحداث',
      AppSettings.logMaxCount: 'الحد الأقصى للأحداث',
      AppSettings.logAutoCleanup: 'تنظيف تلقائي للسجل',
      AppSettings.logRemoteActivity: 'تسجيل نشاط الأجهزة الأخرى',
      AppSettings.logTransactionEdits: 'تسجيل تعديلات العمليات',
      AppSettings.logRequiresAckForWarnings: 'التحذيرات تحتاج تأكيدًا',

      // 🎤 الصوت
      AppSettings.voiceEnabled: 'تفعيل الصوت',
      AppSettings.voiceAutoSaveHighConfidence:
          'حفظ تلقائي عند ثقة عالية',
      AppSettings.voiceConfirmBeforeSave: 'طلب تأكيد قبل الحفظ',
      AppSettings.voicePendingAutoExpireDays:
          'انتهاء صلاحية المعلقات الصوتية',
      AppSettings.voiceFilterEmpty: 'فلترة التسجيلات الفارغة',
      AppSettings.voiceFilterUnclear: 'فلترة غير المفهومة',

      // 💰 الرصيد
      AppSettings.enforceMaxBalance: 'تطبيق الحد الأقصى',
      AppSettings.warnOnExceed: 'تنبيه عند التجاوز',
      AppSettings.blockOnExceed: 'منع تسجيل عملية تتجاوز الحد',
      AppSettings.allowDebtOnInactive: 'السماح بدين على حساب موقوف',
      AppSettings.notifyDebtOnInactive: 'إشعار عند دين على حساب موقوف',

      // 🔒 الأمان
      AppSettings.lockEnabled: 'تفعيل القفل',
      AppSettings.lockTimeoutMinutes: 'مدة القفل التلقائي',
      AppSettings.requirePasswordForDelete: 'طلب كلمة مرور للحذف',
      AppSettings.requirePasswordForRestore: 'طلب كلمة مرور للاستعادة',
      AppSettings.requirePasswordForDangerousSettings:
          'طلب كلمة مرور للإعدادات الخطيرة',

      // 📱 الواجهة
      AppSettings.showDeletedBin: 'إظهار سلة المحذوفات',
      AppSettings.showTrackingInfo: 'إظهار "من عدّل"',
      AppSettings.showCloudId: 'إظهار Cloud ID',
      AppSettings.compactMode: 'وضع مضغوط',
    };
    return map[key] ?? key;
  }

  String _descriptionFor(String key) {
    const map = {
      // 🗑️ الحذف
      AppSettings.blockDeleteNonzeroBalance:
          'لا يمكن حذف حساب رصيده ≠ 0',
      AppSettings.blockDeleteWithTransactions:
          'لا يمكن حذف حساب عليه معاملات',
      AppSettings.softDeleteEnabled:
          'يُحفظ في السلة قبل الحذف النهائي',
      AppSettings.retentionDays:
          'مدة بقاء العنصر في السلة (بالأيام)',
      AppSettings.autoCleanupDeleted:
          'حذف نهائي تلقائي بعد انتهاء المدة',
      AppSettings.blockCustomerDeletion:
          'منع حذف أي حساب نهائياً حتى من السلة',
      AppSettings.blockTransactionDeletion:
          'منع حذف أي عملية نهائياً حتى من السلة',

      // ✏️ التعديل
      AppSettings.allowEditTransactions:
          'التحكم الكامل: إذا مُعطّل، لا يمكن تعديل أي عملية (المبلغ، الأصناف، النوع)',
      AppSettings.allowEditCustomerBalance:
          'تعديل الرصيد بدون معاملة',
      AppSettings.trackEdits:
          'كل تعديل يُسجَّل في سجل الأحداث',
      AppSettings.requireEditReason:
          'يُطلب من المستخدم كتابة السبب',

      // 🔄 المزامنة
      AppSettings.syncEnabled: 'تفعيل/تعطيل المزامنة كليًا',
      AppSettings.syncIntervalMinutes:
          'كم دقيقة بين كل مزامنة دورية؟',
      AppSettings.syncOnDataChange: 'مزامنة تلقائية بعد أي تعديل',
      AppSettings.syncOnAppOpen: 'مزامنة تلقائية عند فتح التطبيق',
      AppSettings.autoResolveConflicts: 'دمج تلقائي + الأحدث يفوز',
      AppSettings.conflictNotification:
          'تنبيه في السجل عند حدوث تعارض',
      AppSettings.deletionConflictRestore:
          'القاعدة الافتراضية: الحذف يُلغى دائمًا',
      AppSettings.syncLogs: 'مزامنة log_events',
      AppSettings.syncDeletedBin:
          'مزامنة الحذف النهائي بين الأجهزة (يمنع إعادة السجلات المحذوفة)',

      // 📜 السجل
      AppSettings.logEnabled: 'تفعيل/تعطيل تسجيل الأحداث',
      AppSettings.logRetentionDays:
          'مدة بقاء الحدث قبل حذفه تلقائيًا',
      AppSettings.logMaxCount: 'أقصى عدد أحداث محفوظة',
      AppSettings.logAutoCleanup: 'تنظيف تلقائي للأحداث القديمة',
      AppSettings.logRemoteActivity:
          'تسجيل ما يفعله محاسب آخر في سجلك',
      AppSettings.logTransactionEdits: 'كل تعديل على عملية يُسجَّل',
      AppSettings.logRequiresAckForWarnings:
          'التحذيرات تظهر في "المعلقات"',

      // 🎤 الصوت
      AppSettings.voiceEnabled: 'تفعيل الإدخال الصوتي',
      AppSettings.voiceAutoSaveHighConfidence:
          'حفظ بدون سؤال عند الثقة',
      AppSettings.voiceConfirmBeforeSave: 'سؤال المستخدم قبل الحفظ',
      AppSettings.voicePendingAutoExpireDays:
          'انتهاء صلاحية التسجيلات المعلقة',
      AppSettings.voiceFilterEmpty:
          'إخفاء التسجيلات الصامتة من القائمة',
      AppSettings.voiceFilterUnclear:
          'إخفاء التسجيلات غير المفهومة',

      // 💰 الرصيد
      AppSettings.enforceMaxBalance: 'تطبيق حد الرصيد الأقصى',
      AppSettings.warnOnExceed: 'إظهار تحذير عند التجاوز',
      AppSettings.blockOnExceed: 'منع الحفظ إذا تجاوز الحد',
      AppSettings.allowDebtOnInactive:
          'إذا مُعطّل، يُمنع الدين على موقوف',
      AppSettings.notifyDebtOnInactive:
          'إشعار تحذير عند الدين على موقوف',

      // 🔒 الأمان
      AppSettings.lockEnabled: 'تفعيل قفل التطبيق',
      AppSettings.lockTimeoutMinutes:
          'القفل التلقائي بعد هذه المدة',
      AppSettings.requirePasswordForDelete:
          'طلب كلمة المرور قبل الحذف',
      AppSettings.requirePasswordForRestore:
          'طلب كلمة المرور قبل الاستعادة',
      AppSettings.requirePasswordForDangerousSettings:
          'حماية الإعدادات الخطيرة',

      // 📱 الواجهة
      AppSettings.showDeletedBin:
          'إظهار سلة المحذوفات في القوائم',
      AppSettings.showTrackingInfo:
          'عرض "من عدّل" في بطاقات السجل',
      AppSettings.showCloudId: 'للمطورين فقط — يظهر UUID',
      AppSettings.compactMode: 'واجهة أصغر وأكثف',
    };
    return map[key] ?? '';
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('الإعدادات المتقدمة'),
          actions: [
            IconButton(
              icon: const Icon(Icons.restore),
              tooltip: 'استعادة الكل',
              onPressed: _resetAll,
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.withOpacity(0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.tune, color: Colors.blue, size: 24),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'التحكم الكامل في سلوك التطبيق. '
                      'الإعدادات تُحفظ فورًا. '
                      'الإعدادات الخطيرة تحتاج كلمة المرور.',
                      style: TextStyle(fontSize: 12, height: 1.5),
                    ),
                  ),
                ],
              ),
            ),

            // ═══════════════════════════════════════════════════
            // 🗑️ الحذف
            // ═══════════════════════════════════════════════════
            _buildGroup(
              title: '🗑️ الحذف',
              groupName: 'الحذف',
              keys: const [
                AppSettings.blockDeleteNonzeroBalance,
                AppSettings.blockDeleteWithTransactions,
                AppSettings.softDeleteEnabled,
                AppSettings.retentionDays,
                AppSettings.autoCleanupDeleted,
                AppSettings.blockCustomerDeletion,
                AppSettings.blockTransactionDeletion,
              ],
              children: [
                _buildBoolTile(AppSettings.blockDeleteNonzeroBalance),
                _buildBoolTile(AppSettings.blockDeleteWithTransactions),
                _buildBoolTile(AppSettings.softDeleteEnabled),
                _buildIntTile(
                  AppSettings.retentionDays,
                  min: 1,
                  max: 365,
                  suffix: 'يوم',
                ),
                _buildBoolTile(AppSettings.autoCleanupDeleted),
                const Divider(height: 1),
                _buildBoolTile(AppSettings.blockCustomerDeletion),
                _buildBoolTile(AppSettings.blockTransactionDeletion),
              ],
            ),

            // ═══════════════════════════════════════════════════
            // ✏️ التعديل
            // ═══════════════════════════════════════════════════
            _buildGroup(
              title: '✏️ التعديل',
              groupName: 'التعديل',
              keys: const [
                AppSettings.allowEditTransactions,
                AppSettings.allowEditCustomerBalance,
                AppSettings.trackEdits,
                AppSettings.requireEditReason,
              ],
              children: [
                _buildBoolTile(AppSettings.allowEditTransactions),
                _buildBoolTile(AppSettings.allowEditCustomerBalance),
                _buildBoolTile(AppSettings.trackEdits),
                _buildBoolTile(AppSettings.requireEditReason),
              ],
            ),

            // ═══════════════════════════════════════════════════
            // 🔄 المزامنة
            // ═══════════════════════════════════════════════════
            _buildGroup(
              title: '🔄 المزامنة',
              groupName: 'المزامنة',
              keys: const [
                AppSettings.syncEnabled,
                AppSettings.syncIntervalMinutes,
                AppSettings.syncOnDataChange,
                AppSettings.syncOnAppOpen,
                AppSettings.autoResolveConflicts,
                AppSettings.conflictNotification,
                AppSettings.deletionConflictRestore,
                AppSettings.syncLogs,
                AppSettings.syncDeletedBin,
              ],
              children: [
                _buildBoolTile(AppSettings.syncEnabled),
                _buildIntTile(
                  AppSettings.syncIntervalMinutes,
                  min: 1,
                  max: 60,
                  suffix: 'دقيقة',
                ),
                _buildBoolTile(AppSettings.syncOnDataChange),
                _buildBoolTile(AppSettings.syncOnAppOpen),
                _buildBoolTile(AppSettings.autoResolveConflicts),
                _buildBoolTile(AppSettings.conflictNotification),
                _buildBoolTile(AppSettings.deletionConflictRestore),
                _buildBoolTile(AppSettings.syncLogs),
                const Divider(height: 1),
                _buildBoolTile(AppSettings.syncDeletedBin),
              ],
            ),

            // ═══════════════════════════════════════════════════
            // 📜 السجل
            // ═══════════════════════════════════════════════════
            _buildGroup(
              title: '📜 السجل',
              groupName: 'السجل',
              keys: const [
                AppSettings.logEnabled,
                AppSettings.logRetentionDays,
                AppSettings.logMaxCount,
                AppSettings.logAutoCleanup,
                AppSettings.logRemoteActivity,
                AppSettings.logTransactionEdits,
                AppSettings.logRequiresAckForWarnings,
              ],
              children: [
                _buildBoolTile(AppSettings.logEnabled),
                _buildIntTile(
                  AppSettings.logRetentionDays,
                  min: 1,
                  max: 365,
                  suffix: 'يوم',
                ),
                _buildIntTile(
                  AppSettings.logMaxCount,
                  min: 100,
                  max: 100000,
                  suffix: 'حدث',
                ),
                _buildBoolTile(AppSettings.logAutoCleanup),
                _buildBoolTile(AppSettings.logRemoteActivity),
                _buildBoolTile(AppSettings.logTransactionEdits),
                _buildBoolTile(AppSettings.logRequiresAckForWarnings),
              ],
            ),

            // ═══════════════════════════════════════════════════
            // 🎤 الصوت
            // ═══════════════════════════════════════════════════
            _buildGroup(
              title: '🎤 الصوت',
              groupName: 'الصوت',
              keys: const [
                AppSettings.voiceEnabled,
                AppSettings.voiceAutoSaveHighConfidence,
                AppSettings.voiceConfirmBeforeSave,
                AppSettings.voicePendingAutoExpireDays,
                AppSettings.voiceFilterEmpty,
                AppSettings.voiceFilterUnclear,
              ],
              children: [
                _buildBoolTile(AppSettings.voiceEnabled),
                _buildBoolTile(AppSettings.voiceAutoSaveHighConfidence),
                _buildBoolTile(AppSettings.voiceConfirmBeforeSave),
                _buildIntTile(
                  AppSettings.voicePendingAutoExpireDays,
                  min: 1,
                  max: 365,
                  suffix: 'يوم',
                ),
                _buildBoolTile(AppSettings.voiceFilterEmpty),
                _buildBoolTile(AppSettings.voiceFilterUnclear),
              ],
            ),

            // ═══════════════════════════════════════════════════
            // 💰 الرصيد
            // ═══════════════════════════════════════════════════
            _buildGroup(
              title: '💰 الرصيد والحدود',
              groupName: 'الرصيد',
              keys: const [
                AppSettings.enforceMaxBalance,
                AppSettings.warnOnExceed,
                AppSettings.blockOnExceed,
                AppSettings.allowDebtOnInactive,
                AppSettings.notifyDebtOnInactive,
              ],
              children: [
                _buildBoolTile(AppSettings.enforceMaxBalance),
                _buildBoolTile(AppSettings.warnOnExceed),
                _buildBoolTile(AppSettings.blockOnExceed),
                _buildBoolTile(AppSettings.allowDebtOnInactive),
                _buildBoolTile(AppSettings.notifyDebtOnInactive),
              ],
            ),

            // ═══════════════════════════════════════════════════
            // 🔒 الأمان
            // ═══════════════════════════════════════════════════
            _buildGroup(
              title: '🔒 الأمان',
              groupName: 'الأمان',
              keys: const [
                AppSettings.lockEnabled,
                AppSettings.lockTimeoutMinutes,
                AppSettings.requirePasswordForDelete,
                AppSettings.requirePasswordForRestore,
                AppSettings.requirePasswordForDangerousSettings,
              ],
              children: [
                _buildBoolTile(AppSettings.lockEnabled),
                _buildIntTile(
                  AppSettings.lockTimeoutMinutes,
                  min: 1,
                  max: 120,
                  suffix: 'دقيقة',
                ),
                _buildBoolTile(AppSettings.requirePasswordForDelete),
                _buildBoolTile(AppSettings.requirePasswordForRestore),
                _buildBoolTile(
                    AppSettings.requirePasswordForDangerousSettings),
              ],
            ),

            // ═══════════════════════════════════════════════════
            // 📱 الواجهة
            // ═══════════════════════════════════════════════════
            _buildGroup(
              title: '📱 الواجهة',
              groupName: 'الواجهة',
              keys: const [
                AppSettings.showDeletedBin,
                AppSettings.showTrackingInfo,
                AppSettings.showCloudId,
                AppSettings.compactMode,
              ],
              children: [
                _buildBoolTile(AppSettings.showDeletedBin),
                _buildBoolTile(AppSettings.showTrackingInfo),
                _buildBoolTile(AppSettings.showCloudId),
                _buildBoolTile(AppSettings.compactMode),
              ],
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildGroup({
    required String title,
    required String groupName,
    required List<String> keys,
    required List<Widget> children,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ExpansionTile(
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.restore, size: 20),
          tooltip: 'استعادة الافتراضي',
          onPressed: () => _resetGroup(groupName, keys),
        ),
        children: children,
      ),
    );
  }

  Widget _buildBoolTile(String key) {
    final value = SettingsService.getBool(key);
    final isDangerous = AppSettings.isDangerous(key);
    final isModified = SettingsService.isModified(key);

    return SwitchListTile(
      dense: true,
      value: value,
      onChanged: (v) => _changeBool(key, v),
      title: Row(
        children: [
          Expanded(
            child: Text(
              _labelFor(key),
              style: TextStyle(
                fontSize: 13,
                fontWeight:
                    isModified ? FontWeight.bold : FontWeight.normal,
                color: isDangerous ? Colors.red.shade700 : null,
              ),
            ),
          ),
          if (isDangerous)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'خطير',
                style: TextStyle(
                  fontSize: 8,
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          if (isModified)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: Icon(Icons.edit, size: 12, color: Colors.orange),
            ),
        ],
      ),
      subtitle: Text(
        _descriptionFor(key),
        style: const TextStyle(fontSize: 11, color: Colors.grey),
      ),
      secondary: IconButton(
        icon: const Icon(Icons.restore, size: 16),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        tooltip: 'استعادة الافتراضي',
        onPressed: () => _resetSetting(key),
      ),
    );
  }

  Widget _buildIntTile(
    String key, {
    required int min,
    required int max,
    required String suffix,
  }) {
    final value = SettingsService.getInt(key);
    final isModified = SettingsService.isModified(key);

    return ListTile(
      dense: true,
      title: Row(
        children: [
          Expanded(
            child: Text(
              _labelFor(key),
              style: TextStyle(
                fontSize: 13,
                fontWeight:
                    isModified ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          if (isModified)
            const Icon(Icons.edit, size: 12, color: Colors.orange),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _descriptionFor(key),
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.remove_circle_outline, size: 20),
                onPressed: value > min
                    ? () => _changeInt(key, value - 1)
                    : null,
              ),
              Expanded(
                child: Center(
                  child: Text(
                    '$value $suffix',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline, size: 20),
                onPressed: value < max
                    ? () => _changeInt(key, value + 1)
                    : null,
              ),
            ],
          ),
        ],
      ),
      trailing: IconButton(
        icon: const Icon(Icons.restore, size: 16),
        tooltip: 'استعادة',
        onPressed: () => _resetSetting(key),
      ),
    );
  }
}
