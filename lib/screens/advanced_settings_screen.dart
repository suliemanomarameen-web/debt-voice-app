import 'package:flutter/material.dart';
import '../config/app_settings.dart';
import '../db/database_helper.dart';
import '../services/settings_service.dart';
import '../services/auth_service.dart';
import '../services/logger_service.dart';
import '../services/voice_prompts_service.dart';
import '../models/log_event.dart';
import 'logs_screen.dart';
import 'voice_prompts_screen.dart';

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
    if (key == AppSettings.lockEnabled && value == true) {
      final hasPwd = await AuthService.hasPassword();
      if (!hasPwd) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('⚠️ يرجى إعداد كلمة مرور القفل أولاً من الإعدادات العادية'),
            backgroundColor: Colors.orange,
          ),
        );
        if (mounted) setState(() {});
        return;
      }
    }

    if (AppSettings.isDangerous(key) &&
        SettingsService.getBool(
            AppSettings.requirePasswordForDangerousSettings,
            defaultValue: true)) {
      final ok = await _askForPassword();
      if (!ok) return;
    }

    if (value == true) {
      if (key == AppSettings.permanentDeleteAlwaysWins) {
        final wasOn =
            SettingsService.getBool(AppSettings.modificationAlwaysWins);
        await SettingsService.setBool(
            AppSettings.modificationAlwaysWins, false);
        if (wasOn && mounted) {
          _snack(
              '🔒 تم تعطيل "التعديل يفوز دائماً" تلقائياً',
              Colors.orange);
        }
      } else if (key == AppSettings.modificationAlwaysWins) {
        final wasOn =
            SettingsService.getBool(AppSettings.permanentDeleteAlwaysWins);
        await SettingsService.setBool(
            AppSettings.permanentDeleteAlwaysWins, false);
        if (wasOn && mounted) {
          _snack(
              '🔒 تم تعطيل "الحذف النهائي يفوز دائماً" تلقائياً',
              Colors.orange);
        }
      }
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

  Future<void> _changeString(String key, String value) async {
    if (AppSettings.isDangerous(key) &&
        SettingsService.getBool(
            AppSettings.requirePasswordForDangerousSettings,
            defaultValue: true)) {
      final ok = await _askForPassword();
      if (!ok) return;
    }
    final oldValue = SettingsService.getString(key);
    await SettingsService.setString(key, value);
    await LoggerService.logSettingChanged(
      settingName: _labelFor(key),
      oldValue: oldValue,
      newValue: value,
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
                child: const Text('إلغاء')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('استعادة')),
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
          content: Text('سيتم إرجاع كل إعدادات "$groupName" للقيم الافتراضية.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('استعادة')),
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
          title: const Row(children: [
            Icon(Icons.warning_amber, color: Colors.red),
            SizedBox(width: 8),
            Text('استعادة كل الإعدادات')
          ]),
          content: const Text(
              '⚠️ سيتم إرجاع **كل** الإعدادات للقيم الافتراضية.\n\nلا يمكن التراجع.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء')),
            FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('استعادة الكل')),
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
            title: const Row(children: [
              Icon(Icons.lock_outline, color: Colors.orange),
              SizedBox(width: 8),
              Text('تأكيد الهوية')
            ]),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('هذا الإعداد خطير ويحتاج كلمة المرور.',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
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
                    prefixIcon: const Icon(Icons.lock)),
                onSubmitted: (v) async {
                  final ok = await AuthService.verifyPassword(v.trim());
                  if (ok) {
                    Navigator.pop(ctx, true);
                  } else {
                    setSt(() => error = 'غير صحيحة');
                  }
                },
              ),
            ]),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('إلغاء')),
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 3)));
  }

  String _labelFor(String key) {
    const map = {
      AppSettings.blockDeleteNonzeroBalance: 'منع حذف حساب رصيده ≠ 0',
      AppSettings.blockDeleteWithTransactions: 'منع حذف حساب عليه عمليات',
      AppSettings.softDeleteEnabled: 'الحذف الناعم (سلة المحذوفات)',
      AppSettings.retentionDays: 'مدة الاحتفاظ في السلة',
      AppSettings.autoCleanupDeleted: 'حذف نهائي تلقائي',
      AppSettings.blockCustomerDeletion: 'منع حذف الحسابات نهائياً',
      AppSettings.blockTransactionDeletion: 'منع حذف العمليات نهائياً',
      AppSettings.permanentDeleteAlwaysWins: '🪦 الحذف النهائي يفوز دائماً',
      AppSettings.modificationAlwaysWins: '✏️ التعديل يفوز دائماً',
      AppSettings.duplicateDetectionEnabled: 'تفعيل كشف التكرار',
      AppSettings.duplicateDetectionLevel: 'مستوى الكشف',
      AppSettings.compoundNameHandling: 'الأسماء المركبة',
      AppSettings.detectHighSimilarity: 'كشف التشابه العالي',
      AppSettings.normalizeHamza: 'توحيد الهمزات',
      AppSettings.normalizeTaaMarbuta: 'توحيد التاء المربوطة',
      AppSettings.blockSyncOnConfirmed: 'إيقاف المزامنة عند تكرار مؤكد',
      AppSettings.blockSyncOnLikely: 'إيقاف المزامنة عند تشابه محتمل',
      AppSettings.blockSyncOnWeak: 'إيقاف المزامنة عند تشابه ضعيف',
      AppSettings.blockSyncOnSimilar: 'إيقاف المزامنة عند تشابه حرفي',
      AppSettings.transactionDuplicateMode: 'طريقة كشف تكرار العمليات',
      AppSettings.transactionWindowMinutes: 'النافذة الزمنية للعمليات',
      AppSettings.autoRenameFormat: 'صيغة إعادة التسمية التلقائية',
      AppSettings.maxDuplicatesPerSync: 'الحد الأقصى للتكرارات في المزامنة',
      AppSettings.notifyOnMerge: 'إشعار عند الدمج',
      AppSettings.notifyOnRename: 'إشعار عند إعادة التسمية',
      AppSettings.notifyOnSkip: 'إشعار عند التخطي',
      AppSettings.notifyOnDuplicateDetected: 'إشعار عند اكتشاف تكرار',
      AppSettings.allowEditTransactions: 'السماح بتعديل العمليات',
      AppSettings.allowEditCustomerBalance: 'السماح بتعديل الرصيد مباشرة',
      AppSettings.trackEdits: 'تسجيل كل تعديل في السجل',
      AppSettings.requireEditReason: 'طلب سبب عند التعديل',
      AppSettings.syncEnabled: 'تفعيل المزامنة',
      AppSettings.syncIntervalMinutes: 'تكرار المزامنة',
      AppSettings.syncOnDataChange: 'مزامنة عند التعديل',
      AppSettings.syncOnAppOpen: 'مزامنة عند فتح التطبيق',
      AppSettings.autoResolveConflicts: 'حل التعارضات تلقائيًا',
      AppSettings.conflictNotification: 'إشعار عند التعارض',
      AppSettings.deletionConflictRestore: 'استعادة الحساب دائمًا عند تعارض الحذف',
      AppSettings.syncLogs: 'مزامنة سجل الأحداث',
      AppSettings.syncDeletedBin: 'مزامنة سلة المحذوفات',
      AppSettings.logEnabled: 'تفعيل السجل',
      AppSettings.logRetentionDays: 'مدة الاحتفاظ بالأحداث',
      AppSettings.logMaxCount: 'الحد الأقصى للأحداث',
      AppSettings.logAutoCleanup: 'تنظيف تلقائي للسجل',
      AppSettings.logRemoteActivity: 'تسجيل نشاط الأجهزة الأخرى',
      AppSettings.logTransactionEdits: 'تسجيل تعديلات العمليات',
      AppSettings.logRequiresAckForWarnings: 'التحذيرات تحتاج تأكيدًا',
      AppSettings.voiceEnabled: 'تفعيل الصوت',
      AppSettings.voiceAutoSaveHighConfidence: 'حفظ تلقائي عند ثقة عالية',
      AppSettings.voiceConfirmBeforeSave: 'طلب تأكيد قبل الحفظ',
      AppSettings.voicePendingAutoExpireDays: 'انتهاء صلاحية المعلقات الصوتية',
      AppSettings.voiceFilterEmpty: 'فلترة التسجيلات الفارغة',
      AppSettings.voiceFilterUnclear: 'فلترة غير المفهومة',
      AppSettings.voiceConversationEnabled: 'تفعيل الحوار الصوتي التفاعلي',
      AppSettings.voiceAlwaysAskForItems: 'السؤال عن البيان دائمًا',
      AppSettings.voiceMaxConversationRounds: 'عدد محاولات الحوار',
      AppSettings.overlayRecordMode: 'طريقة التسجيل من الزر العائم',
      AppSettings.overlayAutoStart: 'تشغيل الزر العائم تلقائياً',
      AppSettings.overlayNotifBtnRecord: 'زر: 🎤 ابدأ التسجيل',
      AppSettings.overlayNotifBtnQuickTx: 'زر: ➕ عملية سريعة',
      AppSettings.overlayNotifBtnNotifications: 'زر: 📋 الإشعارات',
      AppSettings.overlayNotifBtnNewCustomer: 'زر: 👤 عميل جديد',
      AppSettings.overlayNotifBtnStats: 'زر: 📊 الإحصائيات',
      AppSettings.overlayNotifBtnStopOverlay: 'زر: ⏹️ إيقاف الزر العائم',
      AppSettings.enforceMaxBalance: 'تطبيق الحد الأقصى',
      AppSettings.warnOnExceed: 'تنبيه عند التجاوز',
      AppSettings.blockOnExceed: 'منع تسجيل عملية تتجاوز الحد',
      AppSettings.allowDebtOnInactive: 'السماح بدين على حساب موقوف',
      AppSettings.notifyDebtOnInactive: 'إشعار عند دين على حساب موقوف',
      AppSettings.lockEnabled: 'تفعيل القفل',
      AppSettings.lockTimeoutMinutes: 'مدة القفل التلقائي',
      AppSettings.requirePasswordForDelete: 'طلب كلمة مرور للحذف',
      AppSettings.requirePasswordForRestore: 'طلب كلمة مرور للاستعادة',
      AppSettings.requirePasswordForDangerousSettings:
          'طلب كلمة مرور للإعدادات الخطيرة',
      AppSettings.showDeletedBin: 'إظهار سلة المحذوفات',
      AppSettings.showTrackingInfo: 'إظهار "من عدّل"',
      AppSettings.showCloudId: 'إظهار Cloud ID',
      AppSettings.compactMode: 'وضع مضغوط',
      AppSettings.developerModeEnabled: 'تفعيل وضع المطور',
      AppSettings.developerModeVerbose: 'سجل مفصّل (Verbose)',
    };
    return map[key] ?? key;
  }

  String _descriptionFor(String key) {
    const map = {
      AppSettings.blockDeleteNonzeroBalance: 'لا يمكن حذف حساب رصيده ≠ 0',
      AppSettings.blockDeleteWithTransactions: 'لا يمكن حذف حساب عليه معاملات',
      AppSettings.softDeleteEnabled: 'يُحفظ في السلة قبل الحذف النهائي',
      AppSettings.retentionDays: 'مدة بقاء العنصر في السلة (بالأيام)',
      AppSettings.autoCleanupDeleted: 'حذف نهائي تلقائي بعد انتهاء المدة',
      AppSettings.blockCustomerDeletion: 'منع حذف أي حساب نهائياً حتى من السلة',
      AppSettings.blockTransactionDeletion:
          'منع حذف أي عملية نهائياً حتى من السلة',
      AppSettings.permanentDeleteAlwaysWins:
          'مفعّل: لا استعادة أبداً. يتعارض مع "التعديل يفوز"',
      AppSettings.modificationAlwaysWins:
          'مفعّل: أي تعديل يستعيد السجل المحذوف',
      AppSettings.duplicateDetectionEnabled: 'إيقاف = لا كشف للتكرارات',
      AppSettings.duplicateDetectionLevel:
          'صارم / متوازن / مرن / مخصص',
      AppSettings.compoundNameHandling:
          'تلقائي: عبدالله = عبد الله',
      AppSettings.detectHighSimilarity:
          'كشف "محمد" و "محمود"',
      AppSettings.normalizeHamza: 'أ/إ/آ → ا',
      AppSettings.normalizeTaaMarbuta: 'ة → ه',
      AppSettings.blockSyncOnConfirmed: 'منع المزامنة عند تكرار مؤكد',
      AppSettings.blockSyncOnLikely: 'منع المزامنة عند تشابه محتمل',
      AppSettings.blockSyncOnWeak: 'منع المزامنة عند تشابه ضعيف',
      AppSettings.blockSyncOnSimilar: 'منع المزامنة عند تشابه حرفي',
      AppSettings.transactionDuplicateMode: 'code / basic / window',
      AppSettings.transactionWindowMinutes: 'بالدقائق',
      AppSettings.autoRenameFormat: 'صيغة الاسم الجديد',
      AppSettings.maxDuplicatesPerSync: 'أقصى عدد تكرارات',
      AppSettings.notifyOnMerge: 'إشعار عند دمج',
      AppSettings.notifyOnRename: 'إشعار عند إعادة تسمية',
      AppSettings.notifyOnSkip: 'إشعار عند تخطي',
      AppSettings.notifyOnDuplicateDetected: 'إشعار عند اكتشاف',
      AppSettings.allowEditTransactions: 'إذا مُعطّل، لا يمكن تعديل أي عملية',
      AppSettings.allowEditCustomerBalance: 'تعديل الرصيد بدون معاملة',
      AppSettings.trackEdits: 'كل تعديل يُسجَّل',
      AppSettings.requireEditReason: 'يُطلب من المستخدم كتابة السبب',
      AppSettings.syncEnabled: 'تفعيل/تعطيل المزامنة كليًا',
      AppSettings.syncIntervalMinutes: 'دقائق بين المزامنات',
      AppSettings.syncOnDataChange: 'بعد أي تعديل',
      AppSettings.syncOnAppOpen: 'عند فتح التطبيق',
      AppSettings.autoResolveConflicts: 'دمج تلقائي + الأحدث يفوز',
      AppSettings.conflictNotification: 'تنبيه في السجل',
      AppSettings.deletionConflictRestore: 'الحذف يُلغى دائمًا',
      AppSettings.syncLogs: 'مزامنة log_events',
      AppSettings.syncDeletedBin: 'مزامنة الحذف النهائي',
      AppSettings.logEnabled: 'تفعيل/تعطيل التسجيل',
      AppSettings.logRetentionDays: 'مدة بقاء الحدث',
      AppSettings.logMaxCount: 'أقصى عدد أحداث محفوظة',
      AppSettings.logAutoCleanup: 'تنظيف تلقائي للأحداث',
      AppSettings.logRemoteActivity: 'تسجيل نشاط الأجهزة الأخرى',
      AppSettings.logTransactionEdits: 'كل تعديل يُسجَّل',
      AppSettings.logRequiresAckForWarnings: 'التحذيرات في "المعلقات"',
      AppSettings.voiceEnabled: 'تفعيل الإدخال الصوتي',
      AppSettings.voiceAutoSaveHighConfidence: 'حفظ بدون سؤال',
      AppSettings.voiceConfirmBeforeSave: 'سؤال المستخدم قبل الحفظ',
      AppSettings.voicePendingAutoExpireDays: 'انتهاء صلاحية المعلقة',
      AppSettings.voiceFilterEmpty: 'إخفاء التسجيلات الصامتة',
      AppSettings.voiceFilterUnclear: 'إخفاء غير المفهومة',
      AppSettings.voiceConversationEnabled:
          'مفعّل: يسأل عن الحقول الناقصة ويبدأ التسجيل تلقائيًا',
      AppSettings.voiceAlwaysAskForItems:
          'مفعّل: يسأل دائمًا عن البيان',
      AppSettings.voiceMaxConversationRounds:
          'كم مرة يحاول السؤال قبل الاستسلام؟',
      AppSettings.overlayRecordMode:
          'ضغط مطول = آمن. نقرة = سريع لكن قد ينقر بالخطأ.',
      AppSettings.overlayAutoStart:
          'مفعّل: يظهر الزر تلقائياً بعد 3 ثوانٍ من فتح التطبيق',
      AppSettings.overlayNotifBtnRecord:
          'زر "🎤 ابدأ التسجيل" — يبدأ التسجيل',
      AppSettings.overlayNotifBtnQuickTx:
          'زر "➕ عملية" — نافذة عملية جديدة',
      AppSettings.overlayNotifBtnNotifications:
          'زر "📋 الإشعارات" — شاشة الإشعارات',
      AppSettings.overlayNotifBtnNewCustomer:
          'زر "👤 عميل جديد" — إضافة حساب',
      AppSettings.overlayNotifBtnStats:
          'زر "📊 الإحصائيات" — شاشة الإحصائيات',
      AppSettings.overlayNotifBtnStopOverlay:
          'زر "⏹️ إيقاف الزر" — يغلق الزر',
      AppSettings.enforceMaxBalance: 'تطبيق حد الرصيد الأقصى',
      AppSettings.warnOnExceed: 'إظهار تحذير عند التجاوز',
      AppSettings.blockOnExceed: 'منع الحفظ إذا تجاوز الحد',
      AppSettings.allowDebtOnInactive: 'السماح بالدين على موقوف',
      AppSettings.notifyDebtOnInactive: 'إشعار عند الدين على موقوف',
      AppSettings.lockEnabled: 'تفعيل قفل التطبيق',
      AppSettings.lockTimeoutMinutes: 'القفل التلقائي بعد هذه المدة',
      AppSettings.requirePasswordForDelete: 'طلب كلمة المرور قبل الحذف',
      AppSettings.requirePasswordForRestore: 'طلب كلمة المرور قبل الاستعادة',
      AppSettings.requirePasswordForDangerousSettings:
          'حماية الإعدادات الخطيرة',
      AppSettings.showDeletedBin: 'إظهار سلة المحذوفات',
      AppSettings.showTrackingInfo: 'عرض "من عدّل" في السجلات',
      AppSettings.showCloudId: 'للمطورين — يظهر UUID',
      AppSettings.compactMode: 'واجهة أصغر وأكثف',
      AppSettings.developerModeEnabled:
          'مفعّل: الأخطاء والتحذيرات الحرجة تُسجَّل في سجل الأحداث',
      AppSettings.developerModeVerbose:
          'مفعّل: كل خطوة تُسجَّل (أبطأ، للتشخيص العميق)',
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
                onPressed: _resetAll),
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
                  border: Border.all(color: Colors.blue.withOpacity(0.3))),
              child: const Row(children: [
                Icon(Icons.tune, color: Colors.blue, size: 24),
                SizedBox(width: 10),
                Expanded(
                    child: Text(
                        'التحكم الكامل في سلوك التطبيق. الإعدادات تُحفظ فورًا. الإعدادات الخطيرة تحتاج كلمة المرور.',
                        style: TextStyle(fontSize: 12, height: 1.5))),
              ]),
            ),
            // ... (جميع الأقسام السابقة كما هي)
            // للاختصار في الرد، أضفت قسم المطور فقط في النهاية
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
                  AppSettings.permanentDeleteAlwaysWins,
                  AppSettings.modificationAlwaysWins,
                ],
                children: [
                  _buildBoolTile(AppSettings.blockDeleteNonzeroBalance),
                  _buildBoolTile(AppSettings.blockDeleteWithTransactions),
                  _buildBoolTile(AppSettings.softDeleteEnabled),
                  _buildIntTile(AppSettings.retentionDays,
                      min: 1, max: 365, suffix: 'يوم'),
                  _buildBoolTile(AppSettings.autoCleanupDeleted),
                  const Divider(height: 1),
                  _buildBoolTile(AppSettings.blockCustomerDeletion),
                  _buildBoolTile(AppSettings.blockTransactionDeletion),
                  const Divider(height: 1),
                  _buildBoolTile(AppSettings.permanentDeleteAlwaysWins),
                  _buildBoolTile(AppSettings.modificationAlwaysWins),
                ]),
            _buildGroup(
                title: '🔀 نظام التكرار',
                groupName: 'التكرار',
                keys: const [
                  AppSettings.duplicateDetectionEnabled,
                  AppSettings.duplicateDetectionLevel,
                  AppSettings.compoundNameHandling,
                  AppSettings.detectHighSimilarity,
                  AppSettings.normalizeHamza,
                  AppSettings.normalizeTaaMarbuta,
                  AppSettings.blockSyncOnConfirmed,
                  AppSettings.blockSyncOnLikely,
                  AppSettings.blockSyncOnWeak,
                  AppSettings.blockSyncOnSimilar,
                  AppSettings.transactionDuplicateMode,
                  AppSettings.transactionWindowMinutes,
                  AppSettings.autoRenameFormat,
                  AppSettings.maxDuplicatesPerSync,
                  AppSettings.notifyOnMerge,
                  AppSettings.notifyOnRename,
                  AppSettings.notifyOnSkip,
                  AppSettings.notifyOnDuplicateDetected,
                ],
                children: [
                  _buildSubHeader('⚡ تشغيل/إيقاف'),
                  _buildBoolTile(AppSettings.duplicateDetectionEnabled),
                  _buildSubHeader('📊 مستوى الكشف'),
                  _buildChoiceTile<String>(
                    key: AppSettings.duplicateDetectionLevel,
                    currentValue: SettingsService.getString(
                        AppSettings.duplicateDetectionLevel,
                        defaultValue: 'balanced'),
                    options: const [
                      MapEntry('strict', 'صارم'),
                      MapEntry('balanced', 'متوازن'),
                      MapEntry('flexible', 'مرن'),
                      MapEntry('custom', 'مخصص'),
                    ],
                    onChanged: (v) => _changeString(
                        AppSettings.duplicateDetectionLevel, v),
                  ),
                  _buildSubHeader('🔤 تطبيع الأسماء'),
                  _buildChoiceTile<String>(
                    key: AppSettings.compoundNameHandling,
                    currentValue: SettingsService.getString(
                        AppSettings.compoundNameHandling,
                        defaultValue: 'auto'),
                    options: const [
                      MapEntry('auto', 'تلقائي'),
                      MapEntry('ask', 'اسألني'),
                      MapEntry('off', 'معطّل'),
                    ],
                    onChanged: (v) => _changeString(
                        AppSettings.compoundNameHandling, v),
                  ),
                  _buildBoolTile(AppSettings.detectHighSimilarity),
                  _buildBoolTile(AppSettings.normalizeHamza),
                  _buildBoolTile(AppSettings.normalizeTaaMarbuta),
                  _buildSubHeader('⏸️ متى توقف المزامنة؟'),
                  _buildBoolTile(AppSettings.blockSyncOnConfirmed),
                  _buildBoolTile(AppSettings.blockSyncOnLikely),
                  _buildBoolTile(AppSettings.blockSyncOnWeak),
                  _buildBoolTile(AppSettings.blockSyncOnSimilar),
                  _buildSubHeader('💼 كشف تكرار العمليات'),
                  _buildChoiceTile<String>(
                    key: AppSettings.transactionDuplicateMode,
                    currentValue: SettingsService.getString(
                        AppSettings.transactionDuplicateMode,
                        defaultValue: 'code'),
                    options: const [
                      MapEntry('code', 'رقم العملية'),
                      MapEntry('basic', 'أساسي'),
                      MapEntry('window', 'زمني'),
                    ],
                    onChanged: (v) => _changeString(
                        AppSettings.transactionDuplicateMode, v),
                  ),
                  _buildIntTile(AppSettings.transactionWindowMinutes,
                      min: 5, max: 120, suffix: 'دقيقة'),
                  _buildSubHeader('🔧 السلوك التلقائي'),
                  _buildChoiceTile<String>(
                    key: AppSettings.autoRenameFormat,
                    currentValue: SettingsService.getString(
                        AppSettings.autoRenameFormat,
                        defaultValue: '(2)'),
                    options: const [
                      MapEntry('(2)', 'أحمد (2)'),
                      MapEntry('-2', 'أحمد-2'),
                      MapEntry('_2', 'أحمد_2'),
                    ],
                    onChanged: (v) =>
                        _changeString(AppSettings.autoRenameFormat, v),
                  ),
                  _buildChoiceTile<int>(
                    key: AppSettings.maxDuplicatesPerSync,
                    currentValue: SettingsService.getInt(
                        AppSettings.maxDuplicatesPerSync,
                        defaultValue: 50),
                    options: const [
                      MapEntry(10, '10'),
                      MapEntry(50, '50'),
                      MapEntry(100, '100'),
                      MapEntry(999999, 'لا نهائي'),
                    ],
                    onChanged: (v) =>
                        _changeInt(AppSettings.maxDuplicatesPerSync, v),
                  ),
                  _buildSubHeader('🔔 الإشعارات'),
                  _buildBoolTile(AppSettings.notifyOnMerge),
                  _buildBoolTile(AppSettings.notifyOnRename),
                  _buildBoolTile(AppSettings.notifyOnSkip),
                  _buildBoolTile(AppSettings.notifyOnDuplicateDetected),
                ]),
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
                ]),
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
                  _buildIntTile(AppSettings.syncIntervalMinutes,
                      min: 1, max: 60, suffix: 'دقيقة'),
                  _buildBoolTile(AppSettings.syncOnDataChange),
                  _buildBoolTile(AppSettings.syncOnAppOpen),
                  _buildBoolTile(AppSettings.autoResolveConflicts),
                  _buildBoolTile(AppSettings.conflictNotification),
                  _buildBoolTile(AppSettings.deletionConflictRestore),
                  _buildBoolTile(AppSettings.syncLogs),
                  const Divider(height: 1),
                  _buildBoolTile(AppSettings.syncDeletedBin),
                ]),
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
                  _buildIntTile(AppSettings.logRetentionDays,
                      min: 1, max: 365, suffix: 'يوم'),
                  _buildIntTile(AppSettings.logMaxCount,
                      min: 100, max: 100000, suffix: 'حدث'),
                  _buildBoolTile(AppSettings.logAutoCleanup),
                  _buildBoolTile(AppSettings.logRemoteActivity),
                  _buildBoolTile(AppSettings.logTransactionEdits),
                  _buildBoolTile(AppSettings.logRequiresAckForWarnings),
                ]),
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
                  _buildIntTile(AppSettings.voicePendingAutoExpireDays,
                      min: 1, max: 365, suffix: 'يوم'),
                  _buildBoolTile(AppSettings.voiceFilterEmpty),
                  _buildBoolTile(AppSettings.voiceFilterUnclear),
                ]),
            _buildGroup(
                title: '💬 الحوار الصوتي التفاعلي',
                groupName: 'الحوار',
                keys: const [
                  AppSettings.voiceConversationEnabled,
                  AppSettings.voiceAlwaysAskForItems,
                  AppSettings.voiceMaxConversationRounds,
                ],
                children: [
                  _buildBoolTile(AppSettings.voiceConversationEnabled),
                  _buildBoolTile(AppSettings.voiceAlwaysAskForItems),
                  _buildIntTile(AppSettings.voiceMaxConversationRounds,
                      min: 1, max: 10, suffix: 'محاولة'),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.chat_bubble_outline,
                        color: Colors.teal),
                    title: const Text('✏️ تعديل نصوص الحوار والردود'),
                    subtitle: const Text(
                      'عدّل الأسئلة والردود الصوتية حسب لهجتك',
                      style: TextStyle(fontSize: 11),
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const VoicePromptsScreen(),
                        ),
                      ).then((_) {
                        if (mounted) setState(() {});
                      });
                    },
                  ),
                ]),
            _buildGroup(
                title: '🖼️ الزر العائم',
                groupName: 'الزر العائم',
                keys: const [
                  AppSettings.overlayRecordMode,
                  AppSettings.overlayAutoStart,
                  AppSettings.overlayNotifBtnRecord,
                  AppSettings.overlayNotifBtnQuickTx,
                  AppSettings.overlayNotifBtnNotifications,
                  AppSettings.overlayNotifBtnNewCustomer,
                  AppSettings.overlayNotifBtnStats,
                  AppSettings.overlayNotifBtnStopOverlay,
                ],
                children: [
                  _buildSubHeader('⚙️ تشغيل الزر'),
                  _buildBoolTile(AppSettings.overlayAutoStart),
                  _buildSubHeader('👆 طريقة التسجيل'),
                  _buildChoiceTile<String>(
                    key: AppSettings.overlayRecordMode,
                    currentValue: SettingsService.getString(
                        AppSettings.overlayRecordMode,
                        defaultValue: 'long_press'),
                    options: const [
                      MapEntry('long_press', 'ضغط مطول'),
                      MapEntry('tap', 'نقرة واحدة'),
                    ],
                    onChanged: (v) =>
                        _changeString(AppSettings.overlayRecordMode, v),
                  ),
                  _buildSubHeader('🔘 أزرار الإشعار الدائم'),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: Colors.amber.withOpacity(0.4)),
                      ),
                      child: const Row(children: [
                        Icon(Icons.info_outline,
                            color: Colors.amber, size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '⚠️ Android يدعم 3 أزرار كحد أقصى. أول 3 حسب الأولوية.',
                            style:
                                TextStyle(fontSize: 11, height: 1.4),
                          ),
                        ),
                      ]),
                    ),
                  ),
                  _buildBoolTile(AppSettings.overlayNotifBtnRecord),
                  _buildBoolTile(AppSettings.overlayNotifBtnQuickTx),
                  _buildBoolTile(AppSettings.overlayNotifBtnNotifications),
                  _buildBoolTile(AppSettings.overlayNotifBtnNewCustomer),
                  _buildBoolTile(AppSettings.overlayNotifBtnStats),
                  _buildBoolTile(AppSettings.overlayNotifBtnStopOverlay),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      '💡 الترتيب: تسجيل → عملية → إشعارات → عميل → إحصائيات → إيقاف',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ]),
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
                ]),
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
                  _buildIntTile(AppSettings.lockTimeoutMinutes,
                      min: 1, max: 120, suffix: 'دقيقة'),
                  _buildBoolTile(AppSettings.requirePasswordForDelete),
                  _buildBoolTile(AppSettings.requirePasswordForRestore),
                  _buildBoolTile(
                      AppSettings.requirePasswordForDangerousSettings),
                ]),
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
                ]),
            // 🆕 قسم المطور
            _buildGroup(
                title: '🔧 وضع المطور',
                groupName: 'المطور',
                keys: const [
                  AppSettings.developerModeEnabled,
                  AppSettings.developerModeVerbose,
                ],
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: Colors.blue.withOpacity(0.3)),
                      ),
                      child: const Row(children: [
                        Icon(Icons.info_outline,
                            color: Colors.blue, size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '⚠️ للتشخيص فقط — عند التفعيل، تُسجَّل الأخطاء والأحداث الحرجة في سجل الأحداث. عطّله عند الانتهاء.',
                            style:
                                TextStyle(fontSize: 11, height: 1.4),
                          ),
                        ),
                      ]),
                    ),
                  ),
                  _buildBoolTile(AppSettings.developerModeEnabled),
                  _buildBoolTile(AppSettings.developerModeVerbose),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.code, color: Colors.purple),
                    title: const Text('📋 فتح سجل المطور'),
                    subtitle: const Text(
                      'يعرض الأحداث المُسجَّلة بوضع المطور',
                      style: TextStyle(fontSize: 11),
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const LogsScreen(
                            initialCategory: LogCategory.developer,
                          ),
                        ),
                      ).then((_) {
                        if (mounted) setState(() {});
                      });
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.delete_sweep,
                        color: Colors.red),
                    title: const Text('🗑️ مسح سجلات المطور'),
                    subtitle: const Text(
                      'حذف كل الأحداث في فئة developer',
                      style: TextStyle(fontSize: 11),
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: _clearDeveloperLogs,
                  ),
                ]),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Future<void> _clearDeveloperLogs() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('مسح سجلات المطور؟'),
          content: const Text(
              'سيتم حذف كل الأحداث في فئة "مطور". لا يمكن التراجع.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء')),
            FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('مسح')),
          ],
        ),
      ),
    );
    if (confirm != true) return;
    try {
      final db = await DatabaseHelper.instance.database;
      await db.delete('log_events',
          where: 'category = ?', whereArgs: ['developer']);
      if (!mounted) return;
      _snack('✅ تم مسح سجلات المطور', Colors.green);
    } catch (e) {
      if (!mounted) return;
      _snack('❌ خطأ: $e', Colors.red);
    }
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
        title: Text(title,
            style:
                const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        leading: IconButton(
            icon: const Icon(Icons.restore, size: 20),
            tooltip: 'استعادة الافتراضي',
            onPressed: () => _resetGroup(groupName, keys)),
        children: children,
      ),
    );
  }

  Widget _buildSubHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(title,
          style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.grey)),
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
      title: Row(children: [
        Expanded(
            child: Text(_labelFor(key),
                style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        isModified ? FontWeight.bold : FontWeight.normal,
                    color: isDangerous ? Colors.red.shade700 : null))),
        if (isDangerous)
          Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4)),
              child: const Text('خطير',
                  style: TextStyle(
                      fontSize: 8,
                      color: Colors.red,
                      fontWeight: FontWeight.bold))),
        if (isModified)
          const Padding(
              padding: EdgeInsets.only(right: 4),
              child: Icon(Icons.edit, size: 12, color: Colors.orange)),
      ]),
      subtitle: Text(_descriptionFor(key),
          style: const TextStyle(fontSize: 11, color: Colors.grey)),
      secondary: IconButton(
          icon: const Icon(Icons.restore, size: 16),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          tooltip: 'استعادة الافتراضي',
          onPressed: () => _resetSetting(key)),
    );
  }

  Widget _buildIntTile(String key,
      {required int min, required int max, required String suffix}) {
    final value = SettingsService.getInt(key);
    final isModified = SettingsService.isModified(key);
    return ListTile(
      dense: true,
      title: Row(children: [
        Expanded(
            child: Text(_labelFor(key),
                style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        isModified ? FontWeight.bold : FontWeight.normal))),
        if (isModified)
          const Icon(Icons.edit, size: 12, color: Colors.orange),
      ]),
      subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_descriptionFor(key),
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 6),
            Row(children: [
              IconButton(
                  icon: const Icon(Icons.remove_circle_outline, size: 20),
                  onPressed:
                      value > min ? () => _changeInt(key, value - 1) : null),
              Expanded(
                  child: Center(
                      child: Text('$value $suffix',
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold)))),
              IconButton(
                  icon: const Icon(Icons.add_circle_outline, size: 20),
                  onPressed: value < max
                      ? () => _changeInt(key, value + 1)
                      : null),
            ]),
          ]),
      trailing: IconButton(
          icon: const Icon(Icons.restore, size: 16),
          tooltip: 'استعادة',
          onPressed: () => _resetSetting(key)),
    );
  }

  Widget _buildChoiceTile<T>({
    required String key,
    required T currentValue,
    required List<MapEntry<T, String>> options,
    required Function(T) onChanged,
  }) {
    final isModified = SettingsService.isModified(key);
    final validValue = options.any((o) => o.key == currentValue)
        ? currentValue
        : options.first.key;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
                child: Text(_labelFor(key),
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: isModified
                            ? FontWeight.bold
                            : FontWeight.normal))),
            if (isModified)
              const Icon(Icons.edit, size: 12, color: Colors.orange),
            IconButton(
                icon: const Icon(Icons.restore, size: 16),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'استعادة',
                onPressed: () => _resetSetting(key)),
          ]),
          Text(_descriptionFor(key),
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<T>(
              segments: options
                  .map((o) => ButtonSegment<T>(
                        value: o.key,
                        label: Text(o.value,
                            style: const TextStyle(fontSize: 11)),
                      ))
                  .toList(),
              selected: {validValue},
              onSelectionChanged: (v) => onChanged(v.first),
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Advanced Settings v1-v3: النسخ السابقة
// Advanced Settings v4: توسيع الزر العائم + 6 أزرار
// Advanced Settings v5: قسم وضع المطور
// - developerModeEnabled + developerModeVerbose
// - زر "فتح سجل المطور" → LogsScreen(initialCategory: LogCategory.developer)
// - زر "مسح سجلات المطور"
// - استيراد logs_screen
