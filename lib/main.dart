import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
import 'services/logger_service.dart';
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
import 'services/voice_conversation_service.dart';
import 'services/voice_prompts_service.dart';
import 'tabs/tabs_screen.dart';
import 'widgets/quick_transaction_dialog.dart';
import 'db/database_helper.dart';
import 'config/app_settings.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// متغير عام لخدمة الصوت (نستخدمها لتشغيل STT من الخيط الرئيسي)
final SpeechService _globalSpeech = SpeechService();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BootstrapApp());
}

class BootstrapApp extends StatefulWidget {
  const BootstrapApp({super.key});
  @override
  State<BootstrapApp> createState() => _BootstrapAppState();
}

class _BootstrapAppState extends State<BootstrapApp> {
  String? _error;
  bool _ready = false;
  ThemeService? _theme;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      await _initializeServices();
      if (mounted) setState(() => _ready = true);
    } catch (e, stack) {
      debugPrint('💥 [Bootstrap] Error: $e\n$stack');
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _initializeServices() async {
    await DeviceService.getDeviceId();
    await AccountantsService.init();
    await SettingsService.init();
    await NotificationService.init();
    await ReminderService.init();

    try {
      await PermissionService.requestAll();
    } catch (e) {
      debugPrint('⚠️ [Bootstrap] Permissions error: $e');
    }

    try {
      await _globalSpeech.init();
    } catch (e) {
      debugPrint('⚠️ [Bootstrap] Speech error: $e');
    }

    try {
      await TtsService.init();
    } catch (e) {
      debugPrint('⚠️ [Bootstrap] TTS error: $e');
    }

    try {
      await KeywordsService.init();
    } catch (e) {
      debugPrint('⚠️ [Bootstrap] Keywords error: $e');
    }

    try {
      await VoicePromptsService.init();
    } catch (e) {
      debugPrint('⚠️ [Bootstrap] VoicePrompts error: $e');
    }

    try {
      await CodeService.migrateCountersIfNeeded();
    } catch (e) {
      debugPrint('⚠️ [Bootstrap] CodeCounter error: $e');
    }

    _theme = ThemeService();
    try {
      await _theme!.load();
    } catch (e) {
      debugPrint('⚠️ [Bootstrap] Theme error: $e');
    }

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
      debugPrint('⚠️ [Bootstrap] DB cleanup error: $e');
    }

    try {
      await AutoBackupService.init();
    } catch (e) {
      debugPrint('⚠️ [Bootstrap] AutoBackup error: $e');
    }

    try {
      await SyncService.init();
    } catch (e) {
      debugPrint('⚠️ [Bootstrap] Sync error: $e');
    }

    try {
      await CloudBackupService.init();
    } catch (e) {
      debugPrint('⚠️ [Bootstrap] CloudBackup error: $e');
    }

    try {
      await AudioRecorderService.init();
    } catch (e) {
      debugPrint('⚠️ [Bootstrap] AudioRecorder error: $e');
    }

    NotificationService.onAction = (actionId, payload) async {
      debugPrint('🔔 [Main] onAction: $actionId');
      await LoggerService.devInfo('main', 'onAction: $actionId');

      switch (actionId) {
        case 'overlay_record':
          try {
            debugPrint('🎤 [Main] Starting recording from notification');
            await LoggerService.devInfo(
                'main', 'overlay_record — starting STT in main');

            if (!await FlutterOverlayWindow.isActive()) {
              await OverlayService.show();
              await Future.delayed(const Duration(milliseconds: 1000));
            }

            _startSTTInMain();
          } catch (e) {
            debugPrint('❌ [Main] start_recording error: $e');
            await LoggerService.devError(
                'main', 'start_recording: $e');
          }
          return;

        case 'overlay_quick_tx':
          _handleOverlayAction('open_quick_tx');
          return;

        case 'overlay_notifications':
          _handleOverlayAction('open_notifications');
          return;

        case 'overlay_new_customer':
          _handleOverlayAction('open_new_customer');
          return;

        case 'overlay_stats':
          _handleOverlayAction('open_stats');
          return;

        case 'overlay_stop':
          await OverlayService.hide();
          return;
      }

      NotificationActionHandler.handleAction(actionId, payload);
    };

    NotificationService.onTap = _onNotificationTap;

    // ملاحظة: تم إزالة OverlayHandler.listen() هنا 
    // لأنه كان يعترض الرسائل القادمة من overlay_widget قبل أن تصل إلى OverlayService.listen

    try {
      OverlayService.listen((data) {
        if (data is! Map) return;
        final action = data['action'] as String?;
        if (action == null) return;

        switch (action) {
          case 'start_stt_in_main':
            _startSTTInMain();
            break;
          case 'stop_stt_in_main':
            _stopSTTInMain();
            break;
          case 'open_quick_tx':
          case 'open_new_customer':
          case 'open_stats':
          case 'open_notifications':
            _handleOverlayAction(action);
            break;
        }
      });
    } catch (e) {
      debugPrint('⚠️ [Bootstrap] OverlayService.listen error: $e');
    }

    _scheduleAutoStartOverlay();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline,
                        color: Colors.red, size: 60),
                    const SizedBox(height: 20),
                    const Text(
                      'خطأ في التهيئة',
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'افتح السجل (adb logcat) لمعرفة التفاصيل',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SelectableText(
                        _error!,
                        style: const TextStyle(
                            fontSize: 11, fontFamily: 'monospace'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (!_ready || _theme == null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: const Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 20),
                  Text('جاري التهيئة...'),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return MultiProvider(
      providers: [ChangeNotifierProvider.value(value: _theme!)],
      child: const DebtApp(),
    );
  }
}

/// تشغيل STT من الخيط الرئيسي
void _startSTTInMain() async {
  await LoggerService.devInfo('main', 'Starting STT in main isolate');
  try {
    VoiceConversationService.startSession(source: 'overlay_main');

    await _globalSpeech.listen(
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      onResult: (text, isFinal) async {
        if (isFinal) {
          _globalSpeech.stop();
          final finalText = text.isEmpty ? '__EMPTY__' : text;
          LoggerService.devInfo('main', 'STT result: "$finalText"');

          FlutterOverlayWindow.shareData({
            'action': 'stt_result',
            'text': finalText,
          });

          try {
            final result = await VoiceConversationService.processText(finalText);
            LoggerService.devInfo('main', 'VoiceConversationResult: ${result.step.name}');

            if (result.ttsMessage != null && result.ttsMessage!.isNotEmpty) {
              TtsService.speak(result.ttsMessage!);
            }
          } catch (e) {
            await LoggerService.devError('main', 'processText error: $e');
          }
        }
      },
    );
  } catch (e) {
    await LoggerService.devError('main', 'STT listen error: $e');
    FlutterOverlayWindow.shareData({
      'action': 'stt_result',
      'text': '__ERROR__',
    });
  }
}

/// إيقاف STT من الخيط الرئيسي
void _stopSTTInMain() async {
  await LoggerService.devInfo('main', 'Stopping STT in main isolate');
  try {
    await _globalSpeech.stop();
  } catch (e) {
    await LoggerService.devError('main', 'STT stop error: $e');
  }
}

void _scheduleAutoStartOverlay() {
  final enabled = SettingsService.getBool(
    AppSettings.overlayAutoStart,
    defaultValue: true,
  );
  if (!enabled) {
    LoggerService.devInfo('auto-start', 'Disabled by settings');
    return;
  }

  Future.delayed(const Duration(seconds: 8), () async {
    try {
      if (!SettingsService.getBool(
        AppSettings.overlayAutoStart,
        defaultValue: true,
      )) {
        await LoggerService.devInfo('auto-start', 'Disabled during wait');
        return;
      }

      if (navigatorKey.currentContext == null) {
        await LoggerService.devWarn('auto-start', 'No context yet — skip');
        return;
      }

      if (await FlutterOverlayWindow.isActive()) {
        await LoggerService.devInfo('auto-start', 'Overlay already active');
        return;
      }

      await LoggerService.devInfo('auto-start', 'Starting overlay');
      await OverlayService.show();
    } catch (e) {
      await LoggerService.devError('auto-start', 'Error: $e');
    }
  });
}

void _handleOverlayAction(String action) {
  final ctx = navigatorKey.currentContext;
  if (ctx == null) {
    debugPrint('⚠️ [OverlayAction] No context for: $action');
    LoggerService.devWarn('overlay-action', 'No context for: $action');
    return;
  }

  debugPrint('🖼️ [OverlayAction] Handling: $action');
  LoggerService.devInfo('overlay-action', 'Handling: $action');

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
      LoggerService.devWarn('overlay-action', 'Unknown: $action');
  }
}

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
void overlayMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await DatabaseHelper.instance.database;
  } catch (e) {
    debugPrint('⚠️ [OverlayMain] DB init error: $e');
  }
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: OverlayWidget(),
  ));
}

// main v1: الأساسية
// main v2: فحص التكرارات
// main v3: PendingNotificationService + onAction + onTap
// main v3.2: _onNotificationTap
// main v4: الحوار الصوتي التفاعلي
// main v5: الأوامر الستة + التشغيل التلقائي
// main v6: BootstrapApp (إصلاح الشاشة السوداء)
// main v7: سجلات المطور (devInfo/devWarn/devError)
// main v8: تشغيل وإيقاف التعرف على الصوت من الخيط الرئيسي (STT in Main Isolate)
// main v9: إصلاح استدعاء VoiceConversationService (static) وبدء جلسة جديدة
// main v10: إزالة OverlayHandler.listen() لإصلاح تعارض استماع الزر العائم
