import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'tabs/tabs_screen.dart';
import 'screens/overlay_widget.dart';
import 'screens/voice_screen.dart';
import 'screens/lock_screen.dart';
import 'screens/duplicates_screen.dart';
import 'screens/notifications_screen.dart';
import 'handlers/overlay_handler.dart';
import 'services/audio_recorder_service.dart';
import 'services/auto_backup_service.dart';
import 'services/cloud_backup_service.dart';
import 'services/keywords_service.dart';
import 'services/notification_action_handler.dart';
import 'services/notification_service.dart';
import 'services/pending_notification_service.dart';
import 'services/permission_service.dart';
import 'services/reminder_service.dart';
import 'services/speech_service.dart';
import 'services/sync_service.dart';
import 'services/theme_service.dart';
import 'services/tts_service.dart';
import 'services/settings_service.dart';
// 🆕 استيرادات جديدة
import 'services/device_service.dart';
import 'services/accountants_service.dart';
import 'services/duplicate_detector.dart';
import 'db/database_helper.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ═══════════════════════════════════════════════════════
  // 0. 🆕 تهيئة الهوية والمحاسبين (قبل أي شيء)
  // ═══════════════════════════════════════════════════════
  await DeviceService.getDeviceId(); // يضمن وجود device_id
  await AccountantsService.init();   // يحمّل المحاسبين المحليين

  // ═══════════════════════════════════════════════════════
  // 1. تحميل الإعدادات أولاً (قبل أي شيء آخر)
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

  final theme = ThemeService();
  await theme.load();

  // ═══════════════════════════════════════════════════════
  // 3. تهيئة قاعدة البيانات + تنظيف المحذوفات القديمة
  // ═══════════════════════════════════════════════════════
  try {
    await DatabaseHelper.instance.database;

    if (SettingsService.getBool('auto_cleanup_deleted',
        defaultValue: true)) {
      final days = SettingsService.getInt('retention_days',
          defaultValue: 30);
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
  // 5. إشعار الزر العائم بأن الصوت جاهز
  // ═══════════════════════════════════════════════════════
  try {
    await FlutterOverlayWindow.shareData({'action': 'speech_ready'});
  } catch (_) {}

  // ═══════════════════════════════════════════════════════
  // 6. إعداد رد نداء الإشعارات (Actions + Tap)
  // ═══════════════════════════════════════════════════════
  // 🆕 زر في الإشعار → handleAction (حفظ/إلغاء/حدد/تمييز)
  NotificationService.onAction = (actionId, payload) {
    NotificationActionHandler.handleAction(actionId, payload);
  };

  // 🆕 فتح الإشعار → _onNotificationTap (فتح شاشة الإشعارات)
  NotificationService.onTap = _onNotificationTap;

  // ═══════════════════════════════════════════════════════
  // 7. بدء مستمع الزر العائم
  // ═══════════════════════════════════════════════════════
  OverlayHandler.listen();

  // ═══════════════════════════════════════════════════════
  // 8. تشغيل التطبيق
  // ═══════════════════════════════════════════════════════
  runApp(MultiProvider(
    providers: [ChangeNotifierProvider.value(value: theme)],
    child: const DebtApp(),
  ));
}

/// عند الضغط على إشعار
///
/// - "open_notifications" → فتح شاشة الإشعارات (كل الإشعارات)
/// - "voice_notif:X"      → فتح شاشة الإشعارات (مع إبراز X)
/// - أي شيء آخر           → لا يفعل شيئاً
void _onNotificationTap(String? payload) {
  if (payload == null || payload.isEmpty) return;

  // ===== فتح سجل الإشعارات =====
  if (payload == 'open_notifications') {
    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => const NotificationsScreen(),
      ),
    );
    return;
  }

  // ===== فتح إشعار محدد =====
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
  // 🆕 يمنع فتح شاشة التكرارات مرتين في نفس الوقت
  bool _duplicatesScreenOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // 🆕 فحص التكرارات بعد بدء التطبيق
    Future.delayed(const Duration(milliseconds: 700), _checkDuplicates);

    // 🆕 تهيئة إشعارات الصوت (احتفاظ + انتهاء + إعادة عرض)
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
      debugPrint('📱 App resumed - checking sync status');
      Future.delayed(const Duration(seconds: 2), () {
        SyncService.checkAndSyncIfNeeded();
        _checkDuplicates();
        _initVoiceNotifications();
      });
    }
  }

  /// 🆕 يفتح شاشة التكرارات إذا وُجدت تكرارات معلّقة
  Future<void> _checkDuplicates() async {
    if (_duplicatesScreenOpen) return;

    try {
      final hasDuplicates = await DuplicateDetector.shouldBlockSync();
      if (!hasDuplicates || !mounted) return;

      final state = navigatorKey.currentState;
      if (state == null) return;

      _duplicatesScreenOpen = true;

      final route = MaterialPageRoute(
        builder: (_) => const DuplicatesScreen(forceBlock: true),
      );

      await state.push(route);

      _duplicatesScreenOpen = false;
    } catch (e) {
      debugPrint('❌ [App] _checkDuplicates error: $e');
      _duplicatesScreenOpen = false;
    }
  }

  /// 🆕 تهيئة إشعارات الصوت
  /// - تطبيق سياسة الاحتفاظ
  /// - انتهاء الإشعارات القديمة
  /// - إعادة عرض المعلّقة في شريط Android
  Future<void> _initVoiceNotifications() async {
    try {
      // 1. تطبيق الاحتفاظ (حذف القديمة)
      await PendingNotificationService.applyRetention();

      // 2. انتهاء غير المفهومة
      await PendingNotificationService.expireOldNotifications();

      // 3. إعادة عرض المعلّقة في الشريط
      await PendingNotificationService.replayPending();

      // 4. تحديث المجموعات
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

// main v1: الأساسية (تهيئة الخدمات + التطبيق)
// main v2: فحص التكرارات عند البدء والاستئناف + فتح شاشة التكرارات الإلزامية (المرحلة 5)
// main v3: تهيئة PendingNotificationService (احتفاظ + انتهاء + إعادة عرض) + ربط onAction و onTap
// main v3.2: _onNotificationTap يفتح شاشة الإشعارات (open_notifications / voice_notif:X) + استيراد notifications_screen
