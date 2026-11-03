import 'package:flutter/foundation.dart';
import '../db/database_helper.dart';
import '../models/customer.dart';
import '../models/pending_notification.dart';
import '../services/audio_recorder_service.dart';
import '../services/notification_service.dart';
import '../services/overlay_service.dart';
import '../services/parser_service.dart';
import '../services/pending_notification_service.dart';
import '../services/query_service.dart';
import '../services/tts_service.dart';

/// معالج أوامر الزر العائم
///
/// ينشئ PendingNotification تلقائياً في DB + شريط Android
/// الأزرار تظهر في الإشعار، المستخدم يتخذ الإجراء من هناك
class OverlayHandler {
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
      await PendingNotificationService.create(
        PendingNotification.unclear(text: '', audioPath: audioPath),
      );
      await TtsService.speakDidNotHear();
      return;
    }
    if (text.isEmpty) return;

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
      await PendingNotificationService.create(
        PendingNotification.unclear(text: text, audioPath: audioPath),
      );
      await TtsService.speakDidNotUnderstand();
      return;
    }

    // ===== إنشاء حساب؟ =====
    if (parsed.intent == 'add_account') {
      await _handleAddAccount(parsed, text, audioPath);
      return;
    }

    // ===== عملية مالية =====
    await _handleTransaction(parsed, text, audioPath);
  }

  // ═══════════════════════════════════════════════════════════
  // إنشاء حساب جديد — مباشرة (بدون إشعار)
  // ═══════════════════════════════════════════════════════════
  static Future<void> _handleAddAccount(
    dynamic parsed,
    String text,
    String? audioPath,
  ) async {
    if (parsed.customerName.isEmpty) {
      await PendingNotificationService.create(
        PendingNotification.unclear(text: text, audioPath: audioPath),
      );
      await TtsService.speak('لم أفهم الاسم');
      return;
    }

    final db = DatabaseHelper.instance;
    final existing = await db.findExactCustomer(parsed.customerName);

    // ===== الحساب موجود مسبقاً =====
    if (existing != null) {
      await TtsService.speakExistsBefore(parsed.customerName);
      await NotificationService.show(
        'موجود مسبقا',
        parsed.customerName,
      );
      return;
    }

    // ===== إنشاء الحساب =====
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

  // ═══════════════════════════════════════════════════════════
  // عملية مالية — إنشاء إشعار
  // ═══════════════════════════════════════════════════════════
  static Future<void> _handleTransaction(
    dynamic parsed,
    String text,
    String? audioPath,
  ) async {
    final db = DatabaseHelper.instance;

    // بحث عن عميل مطابق تماماً
    final exact = await db.findExactCustomer(parsed.customerName);

    if (exact != null) {
      await _createSingleNotification(parsed, text, audioPath, exact);
      return;
    }

    // بحث جزئي
    final partial = await db.findCustomersContaining(parsed.customerName);

    if (partial.isEmpty) {
      // ===== لا يوجد حساب =====
      await PendingNotificationService.create(
        PendingNotification.noAccount(
          text: text,
          customerName: parsed.customerName,
          intent: parsed.intent,
          amount: parsed.amount,
          currency: parsed.currency,
          items: parsed.items,
          audioPath: audioPath,
        ),
      );
      await TtsService.speakNoAccount(parsed.customerName);
      return;
    }

    if (partial.length == 1) {
      await _createSingleNotification(parsed, text, audioPath, partial.first);
      return;
    }

    // ===== أكثر من حساب =====
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

  // ═══════════════════════════════════════════════════════════
  // إنشاء إشعار "حساب واحد"
  // ═══════════════════════════════════════════════════════════
  static Future<void> _createSingleNotification(
    dynamic parsed,
    String text,
    String? audioPath,
    Customer customer,
  ) async {
    await PendingNotificationService.create(
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

    await TtsService.speak(
      'سُجّل $typeLabel بمبلغ ${parsed.amount.toStringAsFixed(0)} '
      '${parsed.currency} على ${customer.name}. '
      'اضغط [حفظ] في الإشعار للتأكيد',
    );
  }
}

// Overlay Handler v1: النسخة الأساسية (pendingVoiceText static — يتسرب بين الجلسات)
// Overlay Handler v2: إنشاء PendingNotification لكل تسجيل + إشعارات تفاعلية بأزرار + إزالة static (بدون تسرب)
