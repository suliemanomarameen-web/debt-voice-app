import 'package:flutter/foundation.dart';
import '../db/database_helper.dart';
import '../models/customer.dart';
import '../models/transaction.dart';
import '../services/accountant_service.dart';
import '../services/code_service.dart';
import '../services/logger_service.dart';
import '../services/notification_dispatcher.dart';
import '../services/notification_service.dart';
import '../services/settings_service.dart';
import '../services/tts_service.dart';
import '../config/app_settings.dart';

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

      // 🆕 2. فحص الدين على حساب موقوف
      if (normalizedType == 'debt' && !customer.isActive) {
        final allow = SettingsService.getBool(
          AppSettings.allowDebtOnInactive,
          defaultValue: true,
        );

        if (!allow) {
          // منع تام
          if (SettingsService.getBool(
            AppSettings.notifyDebtOnInactive,
            defaultValue: true,
          )) {
            await LoggerService.logDebtOnInactiveAccount(
              customerName: customer.name,
              amount: parsed.amount.toDouble(),
              currency: parsed.currency,
              accountant: await AccountantService.getAccountantName(),
              relatedId: customer.id?.toString(),
            );
          }
          await TtsService.speak(
            'حساب ${customer.name} موقوف — الدين معطّل من الإعدادات',
          );
          await NotificationService.show(
            '⚠️ الدين على حساب موقوف معطّل',
            'الحساب "${customer.name}" موقوف\n'
                'الإعداد الحالي: منع الدين',
          );
          return false;
        }

        // مسموح — سجّل تحذيراً فقط إذا الإعداد مفعل
        if (SettingsService.getBool(
          AppSettings.notifyDebtOnInactive,
          defaultValue: true,
        )) {
          await LoggerService.logDebtOnInactiveAccount(
            customerName: customer.name,
            amount: parsed.amount.toDouble(),
            currency: parsed.currency,
            accountant: await AccountantService.getAccountantName(),
            relatedId: customer.id?.toString(),
          );
        }
      }

      // 3. فحص حد الرصيد
      final balanceCheck = await _checkMaxBalance(
        customer: customer,
        db: db,
        normalizedType: normalizedType,
        amount: parsed.amount.toDouble(),
      );

      if (balanceCheck == _BalanceCheckResult.blocked) {
        await LoggerService.logOverLimit(
          customerName: customer.name,
          balance: await db.customerBalance(customer.id!),
          maxBalance: customer.maxBalance ?? 0,
        );
        await TtsService.speak(
          'تجاوزت حد الرصيد المسموح لـ ${customer.name}',
        );
        await NotificationService.show(
          '⚠️ تجاوز الحد الأقصى',
          'الرصيد سيتجاوز ${customer.maxBalance?.toStringAsFixed(0) ?? "0"} ريال\n'
              'تم منع الحفظ',
        );
        return false;
      }

      if (balanceCheck == _BalanceCheckResult.warning) {
        await TtsService.speak(
          'تنبيه: رصيد ${customer.name} سيتجاوز الحد المسموح',
        );
        await NotificationService.show(
          '⚠️ تنبيه: تجاوز الحد',
          'الرصيد الجديد سيتجاوز ${customer.maxBalance?.toStringAsFixed(0) ?? "0"} ريال\n'
              'سيتم حفظ العملية',
        );
      }

      // 4. جلب اسم المحاسب
      String? accountant;
      try {
        accountant = await AccountantService.getAccountantName();
      } catch (e) {
        debugPrint('❌ Accountant name error: $e');
      }

      // 5. توليد الرمز
      String? code;
      try {
        code = await CodeService.generateCode(normalizedType);
      } catch (e) {
        debugPrint('❌ Code generation error: $e');
      }

      // 6. إدراج العملية
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

      // 7. حساب الرصيد الجديد
      final newBalance = await db.customerBalance(customer.id!);

      final label = {
        'debt': 'دين',
        'payment': 'سداد',
        'return': 'مرتجع',
      }[normalizedType] ?? 'عملية';

      // 8. تسجيل الحدث
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

      // 9. إشعار صوتي
      await TtsService.confirmTransaction(
        type: label,
        amount: parsed.amount,
        customerName: customer.name,
        newBalance: newBalance,
        currency: parsed.currency,
      );

      // 10. بناء تفاصيل الإشعار
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

      // 11. الإشعارات (واتساب، إلخ)
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

  /// فحص حد الرصيد قبل الحفظ
  static Future<_BalanceCheckResult> _checkMaxBalance({
    required Customer customer,
    required DatabaseHelper db,
    required String normalizedType,
    required double amount,
  }) async {
    try {
      if (!SettingsService.getBool(
        AppSettings.enforceMaxBalance,
        defaultValue: true,
      )) {
        return _BalanceCheckResult.ok;
      }

      if (customer.maxBalance == null || customer.maxBalance! <= 0) {
        return _BalanceCheckResult.ok;
      }

      final currentBalance = await db.customerBalance(customer.id!);
      final projectedBalance = normalizedType == 'debt'
          ? currentBalance + amount
          : currentBalance - amount;

      if (projectedBalance <= customer.maxBalance!) {
        return _BalanceCheckResult.ok;
      }

      if (SettingsService.getBool(
        AppSettings.blockOnExceed,
        defaultValue: false,
      )) {
        return _BalanceCheckResult.blocked;
      }

      if (SettingsService.getBool(
        AppSettings.warnOnExceed,
        defaultValue: true,
      )) {
        return _BalanceCheckResult.warning;
      }

      return _BalanceCheckResult.ok;
    } catch (e) {
      debugPrint('⚠️ [TransactionHandler] _checkMaxBalance: $e');
      return _BalanceCheckResult.ok;
    }
  }
}

enum _BalanceCheckResult {
  ok,
  warning,
  blocked,
}

// Overlay Handler v1: النسخة الأساسية (pendingVoiceText static — يتسرب بين الجلسات)
// Overlay Handler v2: إنشاء PendingNotification لكل تسجيل + إشعارات تفاعلية بأزرار + إزالة static (بدون تسرب)

// Transaction Handler v2: ربط إعدادات حد الرصيد بالمنطق
// Transaction Handler v3: ربط إعدادات الدين على حساب موقوف
