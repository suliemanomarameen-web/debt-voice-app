import 'package:flutter/foundation.dart';
import '../db/database_helper.dart';
import '../models/customer.dart';
import '../models/transaction.dart';
import '../services/accountant_service.dart';
import '../services/code_service.dart';
import '../services/logger_service.dart';
import '../services/notification_dispatcher.dart';
import '../services/notification_service.dart';
import '../services/tts_service.dart';

/// معالج حفظ العملية — يُستخدم من Overlay و VoiceScreen
class TransactionHandler {
  /// حفظ عملية جديدة
  ///
  /// يعيد `true` إذا نجح الحفظ، `false` إذا فشل
  static Future<bool> save({
    required Customer customer,
    required dynamic parsed,
    required DatabaseHelper db,
    required String source,
    String? audioPath,
  }) async {
    try {
      final normalizedType = CodeService.normalizeType(parsed.intent);
      final storedType =
          (normalizedType == 'return') ? 'payment' : normalizedType;

      // 1. منع التكرار خلال 30 ثانية
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
            text: '${parsed.amount} - ${customer.name}',
            audioPath: audioPath,
          );
          await TtsService.speak('هذه العملية مسجلة بالفعل');
          await NotificationService.show(
            'عملية مكررة',
            'تم تجاهل العملية (مسجلة خلال آخر 30 ثانية)',
          );
          return false;
        }
      } catch (e) {
        debugPrint('Duplicate check error: $e');
      }

      // 2. جلب اسم المحاسب
      String? accountant;
      try {
        accountant = await AccountantService.getAccountantName();
      } catch (e) {
        debugPrint('❌ Accountant name error: $e');
      }

      // 3. توليد الرمز
      String? code;
      try {
        code = await CodeService.generateCode(normalizedType);
      } catch (e) {
        debugPrint('❌ Code generation error: $e');
      }

      // 4. إدراج العملية
      await db.insertTransaction(Transaction(
        customerId: customer.id!,
        code: code,
        accountant: accountant,
        source: source,
        amount: parsed.amount,
        currency: parsed.currency,
        type: storedType,
        items: normalizedType == 'return'
            ? 'مرتجع${parsed.items.isEmpty ? "" : ": ${parsed.items}"}'
            : parsed.items,
        createdAt: DateTime.now().toIso8601String(),
      ));

      // 5. حساب الرصيد الجديد
      final newBalance = await db.customerBalance(customer.id!);

      final label = {
        'debt': 'دين',
        'payment': 'سداد',
        'return': 'مرتجع',
      }[normalizedType] ?? 'عملية';

      // 6. تسجيل الحدث
      await LoggerService.logTransactionAdded(
        typeLabel: label,
        customerName: customer.name,
        amount: parsed.amount,
        currency: parsed.currency,
        code: code,
        accountant: accountant,
        source: source,
        audioPath: audioPath,
      );

      await LoggerService.logVoiceSuccess(
        text: '$label ${parsed.amount.toStringAsFixed(0)} ${customer.name}',
        audioPath: audioPath,
        parsedAction: label,
      );

      // 7. إشعار صوتي
      await TtsService.confirmTransaction(
        type: label,
        amount: parsed.amount,
        customerName: customer.name,
        newBalance: newBalance,
        currency: parsed.currency,
      );

      // 8. بناء تفاصيل الإشعار
      final detail = StringBuffer();
      detail.write('${customer.name}\n');
      if (code != null) detail.write('الرمز: $code\n');
      if (accountant != null && accountant.isNotEmpty) {
        detail.write('المحاسب: $accountant\n');
      }
      detail.write(
          'المبلغ: ${parsed.amount.toStringAsFixed(0)} ${parsed.currency}');
      if (parsed.items.isNotEmpty) {
        detail.write('\nالأصناف: ${parsed.items}');
      }
      detail.write(
          '\nالرصيد: ${newBalance.toStringAsFixed(0)} ${parsed.currency}');

      await NotificationService.show('تم تسجيل $label', detail.toString());

      // 9. الإشعارات (واتساب، إلخ)
      await NotificationDispatcher.afterTransactionAdded(
        customerId: customer.id!,
        customerName: customer.name,
        phone: customer.phone,
        type: normalizedType,
        amount: parsed.amount,
        newBalance: newBalance,
        source: source,
      );

      return true;
    } catch (e) {
      debugPrint('❌ [TransactionHandler] save error: $e');
      return false;
    }
  }
}
