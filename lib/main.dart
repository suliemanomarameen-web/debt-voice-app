import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'tabs/tabs_screen.dart';
import 'screens/overlay_widget.dart';
import 'screens/voice_screen.dart';
import 'screens/lock_screen.dart';
import 'services/accountant_service.dart';
import 'services/audio_recorder_service.dart';
import 'services/auto_backup_service.dart';
import 'services/cloud_backup_service.dart';
import 'services/code_service.dart';
import 'services/logger_service.dart';
import 'services/notification_service.dart';
import 'services/overlay_service.dart';
import 'services/permission_service.dart';
import 'services/speech_service.dart';
import 'services/parser_service.dart';
import 'services/query_service.dart';
import 'services/sync_service.dart';
import 'services/theme_service.dart';
import 'services/reminder_service.dart';
import 'services/tts_service.dart';
import 'db/database_helper.dart';
import 'models/customer.dart';
import 'models/transaction.dart';
import 'models/log_event.dart';

String? pendingVoiceText;
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await NotificationService.init();
  await ReminderService.init();
  await PermissionService.requestAll();

  final speech = SpeechService();
  await speech.init();

  await TtsService.init();

  final theme = ThemeService();
  await theme.load();

  await AutoBackupService.init();
  await SyncService.init();
  await CloudBackupService.init();
  await AudioRecorderService.init();

  try {
    await FlutterOverlayWindow.shareData({'action': 'speech_ready'});
  } catch (_) {}

  NotificationService.onTap = (payload) {
    if (payload == 'choose_customer' && pendingVoiceText != null) {
      final text = pendingVoiceText!;
      pendingVoiceText = null;
      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => VoiceScreen(initialText: text),
        ),
      );
    }
  };

  _setupOverlayListener();
  runApp(MultiProvider(
    providers: [ChangeNotifierProvider.value(value: theme)],
    child: const DebtApp(),
  ));
}

void _setupOverlayListener() {
  OverlayService.listen((data) async {
    if (data is! Map) return;

    if (data['action'] == 'need_setup') {
      await NotificationService.show(
        'يحتاج إعداد',
        'افتح التطبيق - الإعدادات - فعّل الأذونات',
      );
      return;
    }

    if (data['action'] == 'voice_text') {
      final text = data['text'] as String? ?? '';
      String? audioPath; // 🆕 مسار التسجيل الصوتي

      // 🆕 محاولة جلب آخر تسجيل صوتي من خدمة التسجيل (إن وُجد)
      try {
        audioPath = AudioRecorderService().currentRecordingPath;
      } catch (_) {}

      if (text == '__EMPTY__') {
        // 🆕 تسجيل حدث صوتي فارغ
        await LoggerService.logVoiceEmpty(audioPath: audioPath);

        await TtsService.speakDidNotHear();
        await NotificationService.show(
          'لم أسمع شيئا',
          'اضغط مطولا على الزر وتحدث بوضوح',
        );
        return;
      }
      if (text.isEmpty) return;

      final db = DatabaseHelper.instance;

      if (QueryService.isQuery(text)) {
        final result = await QueryService.query(text);
        await TtsService.speak(result.spokenAnswer);
        await NotificationService.show(
          result.hasAccount ? 'استعلام: ${result.customerName}' : 'استعلام',
          result.spokenAnswer,
        );
        return;
      }

      final parsed = ParserService.parse(text);
      if (parsed == null) {
        // 🆕 تسجيل حدث صوتي فاشل (لم يُفهم)
        await LoggerService.logVoiceFail(
          reason: 'لم يُفهم النص',
          text: text,
          audioPath: audioPath,
        );

        await TtsService.speakDidNotUnderstand();
        await NotificationService.show('لم أفهم', 'النص: "$text"');
        return;
      }

      if (parsed.intent == 'add_account') {
        if (parsed.customerName.isEmpty) {
          await LoggerService.logVoiceFail(
            reason: 'لم يُذكر اسم الحساب',
            text: text,
            audioPath: audioPath,
          );
          await TtsService.speak('لم أفهم الاسم');
          await NotificationService.show('لم أفهم الاسم', '');
          return;
        }
        final existing = await db.findExactCustomer(parsed.customerName);
        if (existing != null) {
          await LoggerService.logVoiceFail(
            reason: 'الحساب موجود مسبقاً',
            text: text,
            audioPath: audioPath,
          );
          await TtsService.speakExistsBefore(parsed.customerName);
          await NotificationService.show('موجود مسبقا', parsed.customerName);
          return;
        }
        final id = await db.insertCustomer(Customer(
          name: parsed.customerName,
          accountType: parsed.accountType,
          createdAt: DateTime.now().toIso8601String(),
        ));

        // 🆕 تسجيل الحدث
        await LoggerService.logCustomerAdded(parsed.customerName);
        await LoggerService.logVoiceSuccess(
          text: text,
          audioPath: audioPath,
          parsedAction: 'إنشاء حساب',
        );

        await TtsService.speakAccountCreated(parsed.customerName);
        final typeAr = {
          'customer': 'عميل',
          'supplier': 'مورد',
          'other': 'أخرى',
        }[parsed.accountType] ?? 'عميل';
        await NotificationService.show(
          'تم إنشاء حساب',
          '${parsed.customerName} ($typeAr)\nالرقم: #$id',
        );
        return;
      }

      final customer = await db.findExactCustomer(parsed.customerName);
      if (customer != null) {
        await _saveTransactionFor(customer, parsed, db, audioPath: audioPath);
        return;
      }
      final partial = await db.findCustomersContaining(parsed.customerName);
      if (partial.isEmpty) {
        await LoggerService.logVoiceFail(
          reason: 'لا يوجد حساب بهذا الاسم',
          text: text,
          audioPath: audioPath,
        );
        await TtsService.speakNoAccount(parsed.customerName);
        await NotificationService.show('لا يوجد حساب', parsed.customerName);
        return;
      }
      if (partial.length > 1) {
        pendingVoiceText = text;
        await TtsService.speakMultipleAccounts();
        await NotificationService.show(
          'يوجد أكثر من حساب',
          'اضغط هنا لاختيار الحساب',
          payload: 'choose_customer',
        );
        return;
      }
      await _saveTransactionFor(partial.first, parsed, db, audioPath: audioPath);
    }
  });
}

Future<void> _saveTransactionFor(
    Customer customer, dynamic parsed, DatabaseHelper db,
    {String? audioPath}) async {
  final normalizedType = CodeService.normalizeType(parsed.intent);
  final storedType = (normalizedType == 'return') ? 'payment' : normalizedType;

  // منع التكرار
  try {
    final isDuplicate = await db.transactionExistsRecent(
      customerId: customer.id!,
      amount: parsed.amount.toDouble(),
      type: storedType,
      window: const Duration(seconds: 30),
    );

    if (isDuplicate) {
      await LoggerService.logVoiceFail(
        reason: 'عملية مكررة (خلال 30 ثانية)',
        text: 'مبلغ: ${parsed.amount}',
        audioPath: audioPath,
      );
      await TtsService.speak('هذه العملية مسجلة بالفعل');
      await NotificationService.show(
        'عملية مكررة',
        'تم تجاهل العملية (مسجلة خلال آخر 30 ثانية)',
      );
      return;
    }
  } catch (e) {
    debugPrint('Duplicate check error: $e');
  }

  // توليد الرمز
  String? code;
  try {
    code = await CodeService.generateCode(normalizedType);
  } catch (e) {
    debugPrint('❌ Code generation error: $e');
  }

  // جلب اسم المحاسب
  String? accountant;
  try {
    accountant = await AccountantService.getAccountantName();
  } catch (_) {}

  await db.insertTransaction(Transaction(
    customerId: customer.id!,
    code: code,
    accountant: accountant,
    source: 'overlay', // 🆕 من الزر العائم
    amount: parsed.amount,
    currency: parsed.currency,
    type: storedType,
    items: normalizedType == 'return'
        ? 'مرتجع${parsed.items.isEmpty ? "" : ": ${parsed.items}"}'
        : parsed.items,
    createdAt: DateTime.now().toIso8601String(),
  ));

  final newBalance = await db.customerBalance(customer.id!);
  final label = {
    'debt': 'دين',
    'payment': 'سداد',
    'return': 'مرتجع',
  }[normalizedType] ?? 'عملية';

  // 🆕 تسجيل الحدث
  await LoggerService.logTransactionAdded(
    typeLabel: label,
    customerName: customer.name,
    amount: parsed.amount,
    currency: parsed.currency,
    code: code,
    accountant: accountant,
    source: 'overlay',
    audioPath: audioPath,
  );

  await LoggerService.logVoiceSuccess(
    text: '${label} ${parsed.amount} ${customer.name}',
    audioPath: audioPath,
    parsedAction: label,
  );

  await TtsService.confirmTransaction(
    type: label,
    amount: parsed.amount,
    customerName: customer.name,
    newBalance: newBalance,
    currency: parsed.currency,
  );

  final detail = StringBuffer();
  detail.write('${customer.name}\n');
  if (code != null) detail.write('الرمز: $code\n');
  if (accountant != null && accountant.isNotEmpty) {
    detail.write('المحاسب: $accountant\n');
  }
  detail.write('المبلغ: ${parsed.amount.toStringAsFixed(0)} ${parsed.currency}');
  if (parsed.items.isNotEmpty) {
    detail.write('\nالأصناف: ${parsed.items}');
  }
  detail.write('\nالرصيد: ${newBalance.toStringAsFixed(0)} ${parsed.currency}');

  await NotificationService.show('تم تسجيل $label', detail.toString());
}

// ============================================================
// ============ DebtApp ============
// ============================================================
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
