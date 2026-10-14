import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'tabs/tabs_screen.dart';
import 'screens/overlay_widget.dart';
import 'screens/voice_screen.dart';
import 'screens/lock_screen.dart';
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

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ═══════════════════════════════════════════════════════
  // 1. تهيئة الخدمات الأساسية
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
  // 2. تهيئة خدمات المزامنة والنسخ
  // ═══════════════════════════════════════════════════════
  await AutoBackupService.init();
  await SyncService.init();
  await CloudBackupService.init();
  await AudioRecorderService.init();

  // ═══════════════════════════════════════════════════════
  // 3. إشعار الزر العائم بأن الصوت جاهز
  // ═══════════════════════════════════════════════════════
  try {
    await FlutterOverlayWindow.shareData({'action': 'speech_ready'});
  } catch (_) {}

  // ═══════════════════════════════════════════════════════
  // 4. إعداد رد نداء الإشعارات
  // ═══════════════════════════════════════════════════════
  NotificationService.onTap = _onNotificationTap;

  // ═══════════════════════════════════════════════════════
  // 5. بدء مستمع الزر العائم
  // ═══════════════════════════════════════════════════════
  OverlayHandler.listen();

  // ═══════════════════════════════════════════════════════
  // 6. تشغيل التطبيق
  // ═══════════════════════════════════════════════════════
  runApp(MultiProvider(
    providers: [ChangeNotifierProvider.value(value: theme)],
    child: const DebtApp(),
  ));
}

/// عند الضغط على إشعار "اختر العميل"
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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
      });
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
