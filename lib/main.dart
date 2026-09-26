import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'tabs/tabs_screen.dart';
import 'screens/overlay_widget.dart';
import 'services/notification_service.dart';
import 'services/overlay_service.dart';
import 'services/permission_service.dart';
import 'services/speech_service.dart';
import 'services/parser_service.dart';
import 'db/database_helper.dart';
import 'models/customer.dart';
import 'models/transaction.dart';

// متغير عالمي لحمل النص القادم من الزر العائم
String? pendingVoiceText;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await NotificationService.init();
  await PermissionService.requestAll();

  final speech = SpeechService();
  await speech.init();

  try {
    await FlutterOverlayWindow.shareData({'action': 'speech_ready'});
  } catch (_) {}

  _setupOverlayListener();
  runApp(const DebtApp());
}

void _setupOverlayListener() {
  OverlayService.listen((data) async {
    if (data is! Map) return;

    if (data['action'] == 'need_setup') {
      await NotificationService.show(
        '⚠️ يحتاج إعداد',
        'افتح التطبيق → الإعدادات → فعّل الأذونات',
      );
      return;
    }

    if (data['action'] == 'voice_text') {
      final text = data['text'] as String? ?? '';

      if (text == '__EMPTY__') {
        await NotificationService.show(
          '🎙️ لم أسمع شيئاً',
          'اضغط مطولاً على الزر وتحدّث بوضوح',
        );
        return;
      }

      if (text.isEmpty) return;

      final parsed = ParserService.parse(text);
      if (parsed == null) {
        await NotificationService.show('لم أفهم', 'النص: "$text"');
        return;
      }

      final db = DatabaseHelper.instance;

      // إنشاء حساب
      if (parsed.intent == 'add_account') {
        final existing = await db.findExactCustomer(parsed.customerName);
        if (existing != null) {
          await NotificationService.show('موجود مسبقاً', parsed.customerName);
          return;
        }
        await db.insertCustomer(Customer(
          name: parsed.customerName,
          accountType: parsed.accountType,
          createdAt: DateTime.now().toIso8601String(),
        ));
        await NotificationService.show('✅ تم إنشاء حساب', parsed.customerName);
        return;
      }

      // معاملة عادية: ابحث
      final customer = await db.findExactCustomer(parsed.customerName);
      if (customer != null) {
        await _saveTransactionFor(customer, parsed, db);
        return;
      }

      final partial = await db.findCustomersContaining(parsed.customerName);
      if (partial.isEmpty) {
        await NotificationService.show('❌ لا يوجد حساب', parsed.customerName);
        return;
      }
      if (partial.length > 1) {
        // احفظ النص لحين فتح التطبيق
        pendingVoiceText = text;
        await NotificationService.show(
          '⚠️ يوجد أكثر من حساب',
          'اضغط هنا لاختيار الحساب',
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

  // الإشعار يعرض: النوع + المبلغ + الأصناف + الرصيد
  final detail = StringBuffer();
  detail.write('${customer.name}\n');
  detail.write('المبلغ: ${parsed.amount.toStringAsFixed(0)} ${parsed.currency}');
  if (parsed.items.isNotEmpty) {
    detail.write('\nالأصناف: ${parsed.items}');
  }
  detail.write('\nالرصيد: ${newBalance.toStringAsFixed(0)} ${parsed.currency}');

  await NotificationService.show('✅ $label', detail.toString());
}

class DebtApp extends StatelessWidget {
  const DebtApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'دفتر الديون',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF1B6B3A),
      ),
      home: const TabsScreen(),
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
