import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'tabs/tabs_screen.dart';
import 'screens/overlay_widget.dart';
import 'screens/voice_screen.dart';
import 'screens/lock_screen.dart';
import 'screens/duplicates_screen.dart';
import 'handlers/overlay_handler.dart';
import 'services/audio_recorder_service.dart';
import 'services/auto_backup_service.dart';
import 'services/cloud_backup_service.dart';
import 'services/keywords_service.dart';
import 'services/notification_service.dart';
import 'services/permission_service.dart';
import 'services/reminder_service.dart';
import 'services/speech_service.dart';
import 'services/sync_service.dart';
import 'services/theme_service.dart';
import 'services/tts_service.dart';
import 'services/settings_service.dart';
import 'services/device_service.dart';
import 'services/accountants_service.dart';
import 'services/duplicate_detector.dart';
import 'db/database_helper.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await DeviceService.getDeviceId();
  await AccountantsService.init();
  await SettingsService.init();
  await NotificationService.init();
  await ReminderService.init();
  await PermissionService.requestAll();

  final speech = SpeechService();
  await speech.init();

  await TtsService.init();
  await KeywordsService.init();

  final theme = ThemeService();
  await theme.load();

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

  await AutoBackupService.init();
  await SyncService.init();
  await CloudBackupService.init();
  await AudioRecorderService.init();

  try {
    await FlutterOverlayWindow.shareData({'action': 'speech_ready'});
  } catch (_) {}

  NotificationService.onTap = _onNotificationTap;
  OverlayHandler.listen();

  runApp(MultiProvider(
    providers: [ChangeNotifierProvider.value(value: theme)],
    child: const DebtApp(),
  ));
}

void _onNotificationTap(String? payload) {
  if (payload != 'choose_customer') return;

  final text = OverlayHandler.consumePendingVoiceText();
  if (text == null) return;

  navigatorKey.currentState?.push(
    MaterialPageRoute(
      builder: (_) => VoiceScreen(initialText: text),
    ),
  );
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
    // فحص التكرارات بعد بدء التطبيق
    Future.delayed(const Duration(milliseconds: 700), _checkDuplicates);
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

// main: تنظيف شواهد القبور القديمة (>90 يوماً) عند بدء التطبيق
// main: فحص التكرارات عند البدء والاستئناف + فتح شاشة التكرارات الإلزامية (المرحلة 5)
