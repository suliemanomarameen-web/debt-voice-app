import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'tabs/tabs_screen.dart';
import 'screens/overlay_widget.dart';
import 'screens/voice_screen.dart';
import 'screens/lock_screen.dart';
import 'services/auto_backup_service.dart';
import 'services/notification_service.dart';
import 'services/overlay_service.dart';
import 'services/permission_service.dart';
import 'services/speech_service.dart';
import 'services/parser_service.dart';
import 'services/query_service.dart';
import 'services/theme_service.dart';
import 'services/reminder_service.dart';
import 'services/tts_service.dart';
import 'db/database_helper.dart';
import 'models/customer.dart';
import 'models/transaction.dart';

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

  // 🔄 النسخ الاحتياطي التلقائي
  await AutoBackupService.init();

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

      if (text == '__EMPTY__') {
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
        await TtsService.speakDidNotUnderstand();
        await NotificationService.show('لم أفهم', 'النص: "$text"');
        return;
      }

      if (parsed.intent == 'add_account') {
        if (parsed.customerName.isEmpty) {
          await TtsService.speak('لم أفهم الاسم');
          await NotificationService.show('لم أفهم الاسم', '');
          return;
        }
        final existing = await db.findExactCustomer(parsed.customerName);
        if (existing != null) {
          await TtsService.speakExistsBefore(parsed.customerName);
          await NotificationService.show('موجود مسبقا', parsed.customerName);
          return;
        }
        final id = await db.insertCustomer(Customer(
          name: parsed.customerName,
          accountType: parsed.accountType,
          createdAt: DateTime.now().toIso8601String(),
        ));
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
        await _saveTransactionFor(customer, parsed, db);
        return;
      }
      final partial = await db.findCustomersContaining(parsed.customerName);
      if (partial.isEmpty) {
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
      await _saveTransactionFor(partial.first, parsed, db);
    }
  });
}

Future<void> _saveTransactionFor(
    Customer customer, dynamic parsed, DatabaseHelper db) async {
  final storedType = (parsed.intent == 'return') ? 'payment' : parsed.intent;

  await db.insertTransaction(Transaction(
    customerId: customer.id!,
    amount: parsed.amount,
    currency: parsed.currency,
    type: storedType,
    items: parsed.intent == 'return'
        ? 'مرتجع${parsed.items.isEmpty ? "" : ": ${parsed.items}"}'
        : parsed.items,
    createdAt: DateTime.now().toIso8601String(),
  ));

  final newBalance = await db.customerBalance(customer.id!);
  final label = {
    'debt': 'دين',
    'payment': 'سداد',
    'return': 'مرتجع',
  }[parsed.intent] ?? 'عملية';

  await TtsService.confirmTransaction(
    type: label,
    amount: parsed.amount,
    customerName: customer.name,
    newBalance: newBalance,
    currency: parsed.currency,
  );

  final detail = StringBuffer();
  detail.write('${customer.name}\n');
  detail.write('المبلغ: ${parsed.amount.toStringAsFixed(0)} ${parsed.currency}');
  if (parsed.items.isNotEmpty) {
    detail.write('\nالأصناف: ${parsed.items}');
  }
  detail.write('\nالرصيد: ${newBalance.toStringAsFixed(0)} ${parsed.currency}');

  await NotificationService.show('تم تسجيل $label', detail.toString());
}

class DebtApp extends StatelessWidget {
  const DebtApp({super.key});
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
