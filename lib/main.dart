import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:provider/provider.dart';
import 'handlers/overlay_handler.dart';
import 'screens/add_account_screen.dart';
import 'screens/duplicates_screen.dart';
import 'screens/lock_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/overlay_widget.dart';
import 'screens/stats_screen.dart';
import 'screens/voice_screen.dart';
import 'services/accountants_service.dart';
import 'services/audio_recorder_service.dart';
import 'services/auto_backup_service.dart';
import 'services/cloud_backup_service.dart';
import 'services/code_service.dart';
import 'services/device_service.dart';
import 'services/duplicate_detector.dart';
import 'services/keywords_service.dart';
import 'services/notification_action_handler.dart';
import 'services/notification_service.dart';
import 'services/overlay_service.dart';
import 'services/pending_notification_service.dart';
import 'services/permission_service.dart';
import 'services/reminder_service.dart';
import 'services/settings_service.dart';
import 'services/speech_service.dart';
import 'services/sync_service.dart';
import 'services/theme_service.dart';
import 'services/tts_service.dart';
import 'services/voice_prompts_service.dart';
import 'tabs/tabs_screen.dart';
import 'widgets/quick_transaction_dialog.dart';
import 'db/database_helper.dart';
import 'config/app_settings.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ═══════════════════════════════════════════════════════
  // 0. تهيئة الهوية والمحاسبين
  // ═══════════════════════════════════════════════════════
  await DeviceService.getDeviceId();
  await AccountantsService.init();

  // ═══════════════════════════════════════════════════════
  // 1. تحميل الإعدادات
  // ═══════════════════════════════════════════════════════
  await SettingsService.init();

  // ═══════════════════════════════════════════════════════
  // 2. تهيئة الخدمات الأساسية
  // ═══════════════════════════════════════════════════════
  await NotificationService.init();
  await ReminderService.init();
  await PermissionService.requestAll();

  final speech = SpeechService();
  await speech.init();

  await TtsService.init();
  await KeywordsService.init();
  await VoicePromptsService.init();
  await CodeService.migrateCountersIfNeeded();

  final theme = ThemeService();
  await theme.load();

  // ═══════════════════════════════════════════════════════
  // 3. تهيئة قاعدة البيانات + تنظيف
  // ═══════════════════════════════════════════════════════
  try {
    await DatabaseHelper.instance.database;

    if (SettingsService.getBool('auto_cleanup_deleted',
        defaultValue: true)) {
      final days =
          SettingsService.getInt('retention_days', defaultValue: 30);
      final cleaned =
          await DatabaseHelper.instance.cleanupDeleted(days: days);
      if (cleaned['customers']! > 0 || cleaned['transactions']! > 0) {
        debugPrint(
            '🧹 Cleaned: ${cleaned['customers']} customers, ${cleaned['transactions']} transactions');
      }
    }

    if (SettingsService.getBool('log_auto_cleanup',
        defaultValue: true)) {
      final logDays =
          SettingsService.getInt('log_retention_days', defaultValue: 30);
      await DatabaseHelper.instance.deleteLogsOlderThan(
        DateTime.now()
            .subtract(Duration(days: logDays))
            .toIso8601String(),
      );
    }
  } catch (e) {
    debugPrint('⚠️ DB cleanup error: $e');
  }

  // ═══════════════════════════════════════════════════════
  // 4. تهيئة خدمات المزامنة والنسخ
  // ═══════════════════════════════════════════════════════
  await AutoBackupService.init();
  await SyncService.init();
  await CloudBackupService.init();
  await AudioRecorderService.init();

  // ═══════════════════════════════════════════════════════
  // 5. إعداد رد نداء الإشعارات
  // ═══════════════════════════════════════════════════════
  NotificationService.onAction = (actionId, payload) async {
    debugPrint('🔔 [Main] onAction: $actionId');

    switch (actionId) {
      // 🎤 ابدأ التسجيل (احتياطي — عادةً يعمل عبر Background)
      case 'overlay_record':
        await OverlayService.startRecordingFromNotification();
        return;

      // ➕ عملية سريعة
      case 'overlay_quick_tx':
        _handleOverlayAction('open_quick_tx');
        return;

      // 📋 الإشعارات
      case 'overlay_notifications':
        _handleOverlayAction('open_notifications');
        return;

      // 👤 عميل جديد
      case 'overlay_new_customer':
        _handleOverlayAction('open_new_customer');
        return;

      // 📊 الإحصائيات
      case 'overlay_stats':
        _handleOverlayAction('open_stats');
        return;

      // ⏹️ إيقاف الزر العائم (احتياطي)
      case 'overlay_stop':
        await OverlayService.hide();
        return;
    }

    // باقي الإجراءات (حفظ/إلغاء/حدد/تمييز)
    NotificationActionHandler.handleAction(actionId, payload);
  };

  NotificationService.onTap = _onNotificationTap;

  // ═══════════════════════════════════════════════════════
  // 6. بدء مستمع الزر العائم
  // ═══════════════════════════════════════════════════════
  OverlayHandler.listen();

  // 🆕 مستمع ثانٍ للأوامر التي يرسلها الـ overlay (open_xxx)
  OverlayService.listen((data) {
    if (data is! Map) return;
    final action = data['action'] as String?;
    if (action == null) return;

    switch (action) {
      case 'open_quick_tx':
      case 'open_new_customer':
      case 'open_stats':
      case 'open_notifications':
        _handleOverlayAction(action);
        break;
    }
  });

  // ═══════════════════════════════════════════════════════
  // 7. تشغيل التطبيق
  // ═══════════════════════════════════════════════════════
  runApp(MultiProvider(
    providers: [ChangeNotifierProvider.value(value: theme)],
    child: const DebtApp(),
  ));

  // ═══════════════════════════════════════════════════════
  // 8. 🆕 تشغيل الزر العائم تلقائياً
  // ═══════════════════════════════════════════════════════
  _scheduleAutoStartOverlay();
}

// ═══════════════════════════════════════════════════════════════
// 🆕 التشغيل التلقائي للزر العائم
// ═══════════════════════════════════════════════════════════════
void _scheduleAutoStartOverlay() {
  final enabled = SettingsService.getBool(
    AppSettings.overlayAutoStart,
    defaultValue: true,
  );
  if (!enabled) {
    debugPrint('🖼️ [AutoStart] Disabled by settings');
    return;
  }

  // انتظر 3 ثوانٍ حتى تستقر Activity بعد runApp
  Future.delayed(const Duration(seconds: 3), () async {
    try {
      if (await FlutterOverlayWindow.isActive()) {
        debugPrint('🖼️ [AutoStart] Overlay already active — skip');
        return;
      }
      debugPrint('🖼️ [AutoStart] Starting overlay automatically');
      await OverlayService.show();
    } catch (e) {
      debugPrint('❌ [AutoStart] Error: $e');
    }
  });
}

// ═══════════════════════════════════════════════════════════════
// 🆕 معالج أوامر الإشعار الدائم (فتح الشاشات)
// ═══════════════════════════════════════════════════════════════
void _handleOverlayAction(String action) {
  final ctx = navigatorKey.currentContext;
  if (ctx == null) {
    debugPrint('⚠️ [OverlayAction] No context for: $action');
    return;
  }

  debugPrint('🖼️ [OverlayAction] Handling: $action');

  switch (action) {
    case 'open_quick_tx':
      QuickTransactionDialog.show(ctx);
      break;

    case 'open_new_customer':
      navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => const AddAccountScreen()),
      );
      break;

    case 'open_stats':
      navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => const StatsScreen()),
      );
      break;

    case 'open_notifications':
      navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => const NotificationsScreen()),
      );
      break;

    default:
      debugPrint('⚠️ [OverlayAction] Unknown: $action');
  }
}

// ═══════════════════════════════════════════════════════════════
// عند الضغط على إشعار
// ═══════════════════════════════════════════════════════════════
void _onNotificationTap(String? payload) {
  if (payload == null || payload.isEmpty) return;

  if (payload == 'open_notifications') {
    navigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
    );
    return;
  }

  if (payload.startsWith('voice_notif:')) {
    final idStr = payload.substring('voice_notif:'.length);
    final id = int.tryParse(idStr);
    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => NotificationsScreen(highlightId: id),
      ),
    );
    return;
  }
}

class DebtApp extends StatefulWidget {
  const DebtApp({super.key});
  @override
  State<DebtApp> createState() => _DebtAppState();
}

class _DebtAppState extends State<DebtApp> with WidgetsBindingObserver {
  bool _duplicatesScreenOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    Future.delayed(const Duration(milliseconds: 700), _checkDuplicates);
    Future.delayed(const Duration(seconds: 2), _initVoiceNotifications);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.resumed) {
      debugPrint('📱 App resumed');
      Future.delayed(const Duration(seconds: 2), () {
        SyncService.checkAndSyncIfNeeded();
        _checkDuplicates();
        _initVoiceNotifications();
      });
    }
  }

  Future<void> _checkDuplicates() async {
    if (_duplicatesScreenOpen) return;

    try {
      final hasDuplicates = await DuplicateDetector.shouldBlockSync();
      if (!hasDuplicates || !mounted) return;

      final state = navigatorKey.currentState;
      if (state == null) return;

      _duplicatesScreenOpen = true;

      await state.push(MaterialPageRoute(
        builder: (_) => const DuplicatesScreen(forceBlock: true),
      ));
    } catch (e) {
      debugPrint('❌ [App] _checkDuplicates error: $e');
    } finally {
      _duplicatesScreenOpen = false;
    }
  }

  Future<void> _initVoiceNotifications() async {
    try {
      await PendingNotificationService.applyRetention();
      await PendingNotificationService.expireOldNotifications();
      await PendingNotificationService.replayPending();
      await PendingNotificationService.updateGroupSummaries();
    } catch (e) {
      debugPrint('❌ [_initVoiceNotifications] error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeService>();
    return MaterialApp(
      title: 'دفتر الديون',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: theme.light,
      darkTheme: theme.dark,
      themeMode: theme.mode,
      home: const LockScreen(child: TabsScreen()),
    );
  }
}

@pragma("vm:entry-point")
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: OverlayWidget(),
  ));
}

// main v1: الأساسية
// main v2: فحص التكرارات عند البدء والاستئناف
// main v3: تهيئة PendingNotificationService + ربط onAction و onTap
// main v3.2: _onNotificationTap يفتح شاشة الإشعارات
// main v4: ربط الحوار الصوتي التفاعلي
// main v5: معالجة الأوامر الستة من الإشعار + التشغيل التلقائي
// - _scheduleAutoStartOverlay: تشغيل تلقائي بعد 3 ثوانٍ
// - _handleOverlayAction: فتح الشاشات (عملية، عميل جديد، إحصائيات، إشعارات)
// - مستمع ثانٍ لـ OverlayService.listen (open_xxx من polling)
// - معالجة onAction لجميع الأزرار الستة (احتياطي)
// - استيراد: quick_transaction_dialog, stats_screen, add_account_screen, app_settings
