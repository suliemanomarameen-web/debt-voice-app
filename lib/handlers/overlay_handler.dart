import 'package:flutter/foundation.dart';
import '../db/database_helper.dart';
import '../models/customer.dart';
import '../models/pending_notification.dart';
import '../services/audio_recorder_service.dart';
import '../services/notification_action_handler.dart';
import '../services/notification_service.dart';
import '../services/overlay_service.dart';
import '../services/parser_service.dart';
import '../services/pending_notification_service.dart';
import '../services/query_service.dart';
import '../services/settings_service.dart';
import '../services/tts_service.dart';
import '../config/app_settings.dart';

/// معالج أوامر الزر العائم
class OverlayHandler {
  static void listen() {
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
        await _handleVoiceText(data);
      }
    });
  }

  /// 🆕 قراءة مدة انتهاء الإشعارات من الإعدادات (بالدقائق)
  static int _getExpireMinutes() {
    try {
      final days = SettingsService.getInt(
        AppSettings.voicePendingAutoExpireDays,
        defaultValue: 30,
      );
      if (days < 1) return 5;
      return days * 24 * 60;
    } catch (_) {
      return 5;
    }
  }

  static Future<void> _handleVoiceText(Map data) async {
    final text = data['text'] as String? ?? '';
    String? audioPath;

    try {
      audioPath = AudioRecorderService().currentRecordingPath;
    } catch (_) {}

    if (text == '__EMPTY__') {
      await PendingNotificationService.create(
        PendingNotification.unclear(
          text: '',
          audioPath: audioPath,
          expiresInMinutes: _getExpireMinutes(),
        ),
      );
      await TtsService.speakDidNotHear();
      return;
    }
    if (text.isEmpty) return;

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
      await PendingNotificationService.create(
        PendingNotification.unclear(
          text: text,
          audioPath: audioPath,
          expiresInMinutes: _getExpireMinutes(),
        ),
      );
      await TtsService.speakDidNotUnderstand();
      return;
    }

    if (parsed.intent == 'add_account') {
      await _handleAddAccount(parsed, text, audioPath);
      return;
    }

    await _handleTransaction(parsed, text, audioPath);
  }

  static Future<void> _handleAddAccount(
    dynamic parsed,
    String text,
    String? audioPath,
  ) async {
    if (parsed.customerName.isEmpty) {
      await PendingNotificationService.create(
        PendingNotification.unclear(
          text: text,
          audioPath: audioPath,
          expiresInMinutes: _getExpireMinutes(),
        ),
      );
      await TtsService.speak('لم أفهم الاسم');
      return;
    }

    final db = DatabaseHelper.instance;
    final existing = await db.findExactCustomer(parsed.customerName);

    if (existing != null) {
      await TtsService.speakExistsBefore(parsed.customerName);
      await NotificationService.show(
        'موجود مسبقا',
        parsed.customerName,
      );
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
  }

  static Future<void> _handleTransaction(
    dynamic parsed,
    String text,
    String? audioPath,
  ) async {
    final db = DatabaseHelper.instance;

    final exact = await db.findExactCustomer(parsed.customerName);

    if (exact != null) {
      await _createSingleNotification(parsed, text, audioPath, exact);
      return;
    }

    final partial = await db.findCustomersContaining(parsed.customerName);

    if (partial.isEmpty) {
      await PendingNotificationService.create(
        PendingNotification.noAccount(
          text: text,
          customerName: parsed.customerName,
          intent: parsed.intent,
          amount: parsed.amount,
          currency: parsed.currency,
          items: parsed.items,
          audioPath: audioPath,
          expiresInMinutes: _getExpireMinutes(),
        ),
      );
      await TtsService.speakNoAccount(parsed.customerName);
      return;
    }

    if (partial.length == 1) {
      await _createSingleNotification(parsed, text, audioPath, partial.first);
      return;
    }

    final candidates = partial.map((c) => {
          'id': c.id,
          'name': c.name,
          'phone': c.phone,
          'account_type': c.accountType,
        }).toList();

    await PendingNotificationService.create(
      PendingNotification.multiple(
        text: text,
        customerName: parsed.customerName,
        intent: parsed.intent,
        amount: parsed.amount,
        currency: parsed.currency,
        items: parsed.items,
        candidates: candidates,
        audioPath: audioPath,
      ),
    );
    await TtsService.speakMultipleAccounts();
  }

  /// 🆕 إنشاء إشعار "حساب واحد"
  ///
  /// يطبّق منطق الحفظ التلقائي:
  /// - إذا `voiceConfirmBeforeSave = false` و `voiceAutoSaveHighConfidence = true`
  ///   → يحفظ فورًا بدون انتظار تدخل المستخدم
  /// - غير ذلك → يُظهر الإشعار بأزرار (سلوك افتراضي)
  static Future<void> _createSingleNotification(
    dynamic parsed,
    String text,
    String? audioPath,
    Customer customer,
  ) async {
    final notifId = await PendingNotificationService.create(
      PendingNotification.single(
        text: text,
        customerName: customer.name,
        intent: parsed.intent,
        amount: parsed.amount,
        currency: parsed.currency,
        items: parsed.items,
        matchedCustomerId: customer.id!,
        matchedCustomerName: customer.name,
        audioPath: audioPath,
        accountType: customer.accountType,
      ),
    );

    final typeLabel = {
      'debt': 'دين',
      'payment': 'سداد',
      'return': 'مرتجع',
    }[parsed.intent] ?? 'عملية';

    // 🆕 منطق الحفظ التلقائي
    final autoSave = SettingsService.getBool(
      AppSettings.voiceAutoSaveHighConfidence,
      defaultValue: true,
    );
    final confirmBefore = SettingsService.getBool(
      AppSettings.voiceConfirmBeforeSave,
      defaultValue: true,
    );

    // الحفظ التلقائي فقط عندما:
    // - autoSave مفعّل
    // - confirmBefore معطّل
    // - تم إنشاء الإشعار بنجاح (لدينا id)
    if (autoSave && !confirmBefore && notifId > 0) {
      try {
        final result = await NotificationActionHandler.saveToCustomer(
          notificationId: notifId,
          customerId: customer.id!,
        );

        if (result['success'] == true) {
          await PendingNotificationService.markSaved(notifId);

          await TtsService.speak(
            'سُجّل $typeLabel بمبلغ ${parsed.amount.toStringAsFixed(0)} '
            '${parsed.currency} على ${customer.name}',
          );
          return;
        }
        // فشل الحفظ → نترك الإشعار للمراجعة
        debugPrint('⚠️ [OverlayHandler] auto-save failed: ${result['message']}');
      } catch (e) {
        debugPrint('❌ [OverlayHandler] auto-save error: $e');
        // نترك الإشعار للمراجعة
      }
    }

    // السلوك الافتراضي: الإشعار ينتظر تدخل المستخدم
    await TtsService.speak(
      'سُجّل $typeLabel بمبلغ ${parsed.amount.toStringAsFixed(0)} '
      '${parsed.currency} على ${customer.name}. '
      'اضغط [حفظ] في الإشعار للتأكيد',
    );
  }
}

// Overlay Handler v1: النسخة الأساسية
// Overlay Handler v2: إنشاء PendingNotification لكل تسجيل
// Overlay Handler v3: ربط voiceAutoSaveHighConfidence وvoiceConfirmBeforeSave وvoicePendingAutoExpireDays
