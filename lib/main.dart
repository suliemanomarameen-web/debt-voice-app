import 'dart:async'; // 🆕 مطلوب لـ Timer
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
import 'models/customer.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// متغير عام لخدمة الصوت (نستخدمها لتشغيل STT من الخيط الرئيسي)
final SpeechService _globalSpeech = SpeechService();
bool _userCancelled = false;
bool _sttStarting = false; // 🆕 التعديل (أ): حماية من الاستدعاء المزدوج

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

    // 🆕 التعديل (ب): التحقق من وجود pending_overlay_record (لحماية الإشعارات عند إغلاق التطبيق)
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingRecord = prefs.getBool('pending_overlay_record') ?? false;
      final requestedAt = prefs.getInt('pending_overlay_record_at');
      final requestIsFresh = requestedAt != null &&
          DateTime.now().millisecondsSinceEpoch - requestedAt <= 120000;
      // Old/stale flags (including flags written by older app versions) must
      // never open the microphone on an ordinary app launch.
      await prefs.setBool('pending_overlay_record', false);
      await prefs.remove('pending_overlay_record_at');
      if (pendingRecord && requestIsFresh) {
        debugPrint('🔄 [Bootstrap] Fresh notification recording request found');
        Future.delayed(const Duration(seconds: 3), () {
          _startSTTInMain();
        });
      }
    } catch (e) {
      debugPrint('⚠️ [Bootstrap] Check pending overlay error: $e');
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

      // 🆕 التعديل (د): مسح المفتاح فوراً بما أننا نعالج الأمر مباشرة هنا
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('pending_overlay_record', false);
        await prefs.remove('pending_overlay_record_at');
        await prefs.setBool('pending_quick_tx', false);
        await prefs.setBool('pending_new_customer', false);
        await prefs.setBool('pending_open_stats', false);
        await prefs.setBool('pending_open_notifications', false);
        await prefs.setBool('pending_stop_overlay', false);
      } catch (e) {
        debugPrint('⚠️ [Main] clear pending flags error: $e');
      }

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
          case 'cancel_stt_in_main':
            _cancelSTTInMain();
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

    // 🆕 التعديل (هـ): Polling احتياطي لالتقاط أوامر الزر العائم عبر SharedPreferences
    Timer.periodic(const Duration(milliseconds: 300), (timer) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        if (prefs.getBool('pending_stt_start') == true) {
          await prefs.setBool('pending_stt_start', false);
          await LoggerService.devInfo('main', 'Poll: pending_stt_start → _startSTTInMain');
          _startSTTInMain();
        }
        if (prefs.getBool('pending_stt_cancel') == true) {
          await prefs.setBool('pending_stt_cancel', false);
          await LoggerService.devInfo('main', 'Poll: pending_stt_cancel → _cancelSTTInMain');
          _cancelSTTInMain();
        }
      } catch (_) {}
    });
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

/// تشغيل STT من الخيط الرئيسي (مع استمرارية الحوار)
void _startSTTInMain() async {
  // 🆕 التعديل (ج): حماية من الاستدعاء المزدوج
  if (_sttStarting || _globalSpeech.isListening) {
    await LoggerService.devInfo('main', 'STT already starting/listening — skipping');
    return;
  }
  _sttStarting = true;

  try {
    _userCancelled = false;
    await LoggerService.devInfo('main', 'Starting STT in main isolate');

    FlutterOverlayWindow.shareData({'action': 'stt_started'});

    if (!VoiceConversationService.hasActiveSession) {
      VoiceConversationService.startSession(source: 'overlay_main');
    }

    Future<void> handleConversationInput(String rawText) async {
      if (_userCancelled) {
        _userCancelled = false;
        return;
      }

      final finalText = rawText.trim();
      if (finalText.isNotEmpty && finalText != '__EMPTY__') {
        await LoggerService.devInfo('main', 'STT result: "$finalText"');
        FlutterOverlayWindow.shareData(
            {'action': 'stt_result', 'text': finalText});
      } else {
        await LoggerService.devInfo(
            'main', 'Genuine silence/no-match — count as one dialog attempt');
      }

      if (finalText.isNotEmpty && _isCancelCommand(finalText)) {
        await LoggerService.devInfo('main', 'Cancel command detected');
        VoiceConversationService.cancelSession();
        await TtsService.speak(VoicePromptsService.getResponse(
            VoicePromptsService.rCancelled));
        FlutterOverlayWindow.shareData(
            {'action': 'stt_result', 'text': 'cancelled'});
        return;
      }

      try {
        final result =
            await VoiceConversationService.processText(finalText);
        await LoggerService.devInfo(
            'main', 'VoiceConversationResult: ${result.step.name}');

        if (result.ttsMessage != null && result.ttsMessage!.isNotEmpty) {
          // TTS completion is awaited before another microphone session starts.
          await TtsService.speak(result.ttsMessage!);
        }

        if (result.startListening) {
          await Future.delayed(const Duration(milliseconds: 350));
          _sttStarting = false;
          _startSTTInMain();
        } else if (result.targetScreen != null) {
          await _handleVoiceTargetScreen(result);
        } else {
          VoiceConversationService.cancelSession();
          FlutterOverlayWindow.shareData(
              {'action': 'stt_result', 'text': 'conversation_finished'});
        }
      } catch (e) {
        await LoggerService.devError('main', 'processText error: $e');
        VoiceConversationService.cancelSession();
        await TtsService.speak('حدث خطأ أثناء معالجة الأمر، حاول مرة أخرى');
      }
    }

    final listenHandler = (String text, bool isFinal) async {
      if (!isFinal) return;
      await _globalSpeech.stop();
      await handleConversationInput(text);
    };

    await _globalSpeech.listen(
      listenFor: const Duration(minutes: 5),
      pauseFor: const Duration(seconds: 5),
      onResult: listenHandler,
      onSilence: () async {
        await handleConversationInput('');
      },
    );

    // لا نعيد تهيئة المحرك تلقائياً عند فشل بدء الالتقاط؛ إعادة المحاولة
    // هنا كانت تتداخل مع جلسة جديدة أو تعيد فتح الميكروفون بعد توقف المستخدم.

  } catch (e) {
    await LoggerService.devError('main', 'STT listen error: $e');
    FlutterOverlayWindow.shareData({
      'action': 'stt_result',
      'text': '__ERROR__',
    });
  } finally {
    _sttStarting = false; // 🆕 التعديل (ج): تصفير الحماية دائماً عند الخروج
  }
}

/// إيقاف مؤقت (عند رفع الإصبع من الزر العائم)
void _stopSTTInMain() async {
  await LoggerService.devInfo('main', 'Stopping STT (temporary pause)');
  try {
    // رفع الإصبع يوقف الالتقاط الحالي مع السماح بتسليم الكلام الذي قيل،
    // ولا يُعامل كإلغاء للحوار أو كصمت مصطنع.
    await _globalSpeech.stop(suppressCallbacks: false);
  } catch (e) {
    await LoggerService.devError('main', 'STT stop error: $e');
  }
}

/// إلغاء كامل (عند النقر على الزر العائم أثناء التسجيل)
void _cancelSTTInMain() async {
  await LoggerService.devInfo('main', 'Cancelling STT (user action)');
  _userCancelled = true;
  try {
    await _globalSpeech.stop();
  } catch (e) {}
  VoiceConversationService.cancelSession();
  FlutterOverlayWindow.shareData({'action': 'stt_result', 'text': 'cancelled'});
}

bool _isCancelCommand(String text) {
  final t = text.trim();
  final cancelWord = VoicePromptsService.getPrompt(
    VoicePromptsService.pCancelWord,
  ).trim();
  if (t == cancelWord) return true;
  const singles = {'إلغاء', 'الغاء', 'الغي', 'الغى', 'ألغي', 'ألغى'};
  if (singles.contains(t)) return true;
  const phrases = {
    'الغ العمليه', 'الغ العملية',
    'الغي العمليه', 'الغي العملية',
    'إلغاء العمليه', 'إلغاء العملية',
    'الغاء العمليه', 'الغاء العملية',
  };
  for (final p in phrases) {
    if (t.contains(p)) return true;
  }
  return false;
}

/// 🆕 التنقل بين الشاشات من الزر العائم بعد تنفيذ الأمر الصوتي
Future<void> _handleVoiceTargetScreen(VoiceConversationResult result) async {
  final ctx = navigatorKey.currentContext;
  if (ctx == null) return;

  switch (result.targetScreen) {
    case 'stats':
      navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => const StatsScreen()),
      ).then((_) => VoiceConversationService.cancelSession());
      break;

    case 'edit':
      if (result.matchedCustomer != null) {
        navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => AddAccountScreen(existing: result.matchedCustomer),
          ),
        ).then((_) => VoiceConversationService.cancelSession());
      } else {
        VoiceConversationService.cancelSession();
      }
      break;

    case 'print':
    case 'send':
      if (result.matchedCustomer != null) {
        await _showStatementDialog(result.matchedCustomer!);
      }
      VoiceConversationService.cancelSession();
      break;

    case 'search':
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(
          content: Text('استخدم تبويب العملاء للبحث'),
          backgroundColor: Colors.blue,
        ),
      );
      VoiceConversationService.cancelSession();
      break;

    default:
      VoiceConversationService.cancelSession();
  }
}

/// 🆕 عرض كشف الحساب في نافذة (للطباعة والإرسال)
Future<void> _showStatementDialog(Customer customer) async {
  final ctx = navigatorKey.currentContext;
  if (ctx == null) return;
  final db = DatabaseHelper.instance;
  final balance = await db.customerBalance(customer.id!);
  final txList = await db.customerTransactions(customer.id!);

  await showDialog(
    context: ctx,
    builder: (c) => Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Text('كشف حساب ${customer.name}'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: balance > 0
                        ? Colors.red.withOpacity(0.1)
                        : Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        balance > 0
                            ? Icons.arrow_upward
                            : Icons.arrow_downward,
                        color: balance > 0 ? Colors.red : Colors.green,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'الرصيد: ${balance.abs().toStringAsFixed(0)} ريال',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: balance > 0 ? Colors.red : Colors.green,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'آخر العمليات:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const Divider(),
                if (txList.isEmpty)
                  const Text('لا توجد عمليات',
                      style: TextStyle(color: Colors.grey))
                else
                  ...txList.take(10).map((t) {
                    final typeLabel = t.type == 'debt'
                        ? 'دين'
                        : t.type == 'payment'
                            ? 'سداد'
                            : 'مرتجع';
                    final color =
                        t.type == 'debt' ? Colors.red : Colors.green;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Icon(Icons.circle, size: 8, color: color),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '$typeLabel — ${t.amount.toStringAsFixed(0)} ${t.currency}',
                              style: TextStyle(
                                  fontSize: 13, color: color),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    ),
  );
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
// main v8: تشغيل وإيقاف التعرف على الصوت من الخيط الرئيسي
// main v9: إصلاح استدعاء VoiceConversationService (static) وبدء جلسة جديدة
// main v10: إزالة OverlayHandler.listen() + إصلاح استمرارية الحوار
// main v11: استمرارية الحوار الصوتي وإلغاء يدوي بدون توقف عند الصمت
// main v12: إصلاح فشل تشغيل الصوت في المرة الأولى + دعم الاستعلام
// main v13: دعم targetScreen من الزر العائم (إحصائيات، تعديل، طباعة)
// main v14: إصلاح شامل للزر العائم (حماية _sttStarting، مسح pending flags، قراءة المفتاح عند البدء)
// main v15: إضافة Polling لالتقاط أوامر الزر العائم عبر SharedPreferences (pending_stt_start، pending_stt_cancel)
