import 'package:flutter/material.dart';
import 'tabs/tabs_screen.dart';
import 'screens/overlay_widget.dart';
import 'services/notification_service.dart';
import 'services/overlay_service.dart';
import 'services/parser_service.dart';
import 'db/database_helper.dart';
import 'models/customer.dart';
import 'models/transaction.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.init();
  _setupOverlayListener();
  runApp(const DebtApp());
}

void _setupOverlayListener() {
  OverlayService.listen((data) async {
    if (data is Map && data['action'] == 'voice_text') {
      final text = data['text'] as String? ?? '';
      if (text.isEmpty) return;

      final parsed = ParserService.parse(text);
      if (parsed == null) {
        await NotificationService.show(
          'لم أفهم الجملة',
          'جرّب: "سجل على محمد 500 ريال"',
        );
        return;
      }

      final db = DatabaseHelper.instance;

      if (parsed.intent == 'add_account') {
        final existing = await db.findExactCustomer(parsed.customerName);
        if (existing != null) {
          await NotificationService.show(
            'الحساب موجود مسبقاً',
            '"${parsed.customerName}" مسجل بالفعل',
          );
          return;
        }
        await db.insertCustomer(Customer(
          name: parsed.customerName,
          accountType: parsed.accountType,
          createdAt: DateTime.now().toIso8601String(),
        ));
        await NotificationService.show(
          '✅ تم إنشاء حساب',
          '${parsed.customerName} (${parsed.accountType})',
        );
        return;
      }

      final customer = await db.findExactCustomer(parsed.customerName);
      if (customer == null) {
        final partial = await db.findCustomersContaining(parsed.customerName);
        if (partial.isEmpty) {
          await NotificationService.show(
            '❌ لا يوجد حساب',
            '"${parsed.customerName}"',
          );
          return;
        }
        if (partial.length > 1) {
          await NotificationService.show(
            '⚠️ يوجد أكثر من حساب',
            'افتح التطبيق للاختيار',
          );
          return;
        }
        await _saveTransactionFor(partial.first, parsed, db);
        return;
      }

      await _saveTransactionFor(customer, parsed, db);
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

  await NotificationService.show(
    '✅ $label بمبلغ ${parsed.amount.toStringAsFixed(0)} ${parsed.currency}',
    '${customer.name} — الرصيد: ${newBalance.toStringAsFixed(0)}',
  );
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
