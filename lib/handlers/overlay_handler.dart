import 'package:flutter/foundation.dart';
import '../db/database_helper.dart';
import '../models/customer.dart';
import '../services/audio_recorder_service.dart';
import '../services/logger_service.dart';
import '../services/notification_service.dart';
import '../services/overlay_service.dart';
import '../services/parser_service.dart';
import '../services/query_service.dart';
import '../services/tts_service.dart';
import 'transaction_handler.dart';

/// معالج أوامر الزر العائم
class OverlayHandler {
  /// النص المعلّق (بانتظار اختيار العميل)
  static String? pendingVoiceText;

  /// رد نداء عند الضغط على إشعار "اختر العميل"
  static void Function(String text)? onChooseCustomer;

  /// تهيئة المستمع للزر العائم
  static void listen() {
    OverlayService.listen((data) async {
      if (data is! Map) return;

      // ===== يحتاج إعداد =====
      if (data['action'] == 'need_setup') {
        await NotificationService.show(
          'يحتاج إعداد',
          'افتح التطبيق - الإعدادات - فعّل الأذونات',
        );
        return;
      }

      // ===== نص صوتي =====
      if (data['action'] == 'voice_text') {
        await _handleVoiceText(data);
      }
    });
  }

  // ═══════════════════════════════════════════════════════════
  // معالجة النص الصوتي
  // ═══════════════════════════════════════════════════════════
  static Future<void> _handleVoiceText(Map data) async {
    final text = data['text'] as String? ?? '';
    String? audioPath;

    // محاولة جلب آخر تسجيل صوتي
    try {
      audioPath = AudioRecorderService().currentRecordingPath;
    } catch (_) {}

    // ===== نص فارغ =====
    if (text == '__EMPTY__') {
      await LoggerService.logVoicePending(
        rawText: '',
        audioPath: audioPath,
      );
      await TtsService.speakDidNotHear();
      await NotificationService.show(
        'لم أسمع شيئا',
        'اضغط مطولا على الزر وتحدث بوضوح',
      );
      return;
    }
    if (text.isEmpty) return;

    final db = DatabaseHelper.instance;

    // ===== استعلام؟ =====
    if (QueryService.isQuery(text)) {
      final result = await QueryService.query(text);
      await TtsService.speak(result.spokenAnswer);
      await NotificationService.show(
        result.hasAccount ? 'استعلام: ${result.customerName}' : 'استعلام',
        result.spokenAnswer,
      );
      return;
    }

    // ===== تحليل النص =====
    final parsed = ParserService.parse(text);
    if (parsed == null) {
      await LoggerService.logVoicePending(
        rawText: text,
        audioPath: audioPath,
      );
      await TtsService.speakDidNotUnderstand();
      await NotificationService.show(
        '🔴 تسجيل معلّق',
        'لم أفهم: "$text"\nافتح السجل → المعلقات للمراجعة',
      );
      return;
    }

    // ===== إنشاء حساب؟ =====
    if (parsed.intent == 'add_account') {
      await _handleAddAccount(parsed, text, audioPath, db);
      return;
    }

    // ===== عملية مالية =====
    await _handleTransaction(parsed, text, audioPath, db);
  }

  // ═══════════════════════════════════════════════════════════
  // إنشاء حساب جديد
  // ═══════════════════════════════════════════════════════════
  static Future<void> _handleAddAccount(
    dynamic parsed,
    String text,
    String? audioPath,
    DatabaseHelper db,
  ) async {
    if (parsed.customerName.isEmpty) {
      await LoggerService.logVoicePending(
        rawText: text,
        audioPath: audioPath,
        partialParse: {
          'intent': 'add_account',
          'customerName': '',
        },
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
  }

  // ═══════════════════════════════════════════════════════════
  // عملية مالية
  // ═══════════════════════════════════════════════════════════
  static Future<void> _handleTransaction(
    dynamic parsed,
    String text,
    String? audioPath,
    DatabaseHelper db,
  ) async {
    // بحث عن عميل مطابق تماماً
    final customer = await db.findExactCustomer(parsed.customerName);
    if (customer != null) {
      await TransactionHandler.save(
        customer: customer,
        parsed: parsed,
        db: db,
        source: 'overlay',
        audioPath: audioPath,
      );
      return;
    }

    // بحث جزئي
    final partial = await db.findCustomersContaining(parsed.customerName);

    if (partial.isEmpty) {
      await LoggerService.logVoicePending(
        rawText: text,
        audioPath: audioPath,
        partialParse: {
          'intent': parsed.intent,
          'amount': parsed.amount,
          'customerName': parsed.customerName,
          'items': parsed.items,
        },
      );
      await TtsService.speakNoAccount(parsed.customerName);
      await NotificationService.show(
        '🔴 تسجيل معلّق',
        'لا يوجد حساب باسم "${parsed.customerName}"\nافتح السجل → المعلقات',
      );
      return;
    }

    // أكثر من عميل مطابق
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

    // عميل واحد مطابق
    await TransactionHandler.save(
      customer: partial.first,
      parsed: parsed,
      db: db,
      source: 'overlay',
      audioPath: audioPath,
    );
  }

  // ═══════════════════════════════════════════════════════════
  // عند الضغط على إشعار "اختر العميل"
  // ═══════════════════════════════════════════════════════════
  static String? consumePendingVoiceText() {
    final text = pendingVoiceText;
    pendingVoiceText = null;
    return text;
  }
}
