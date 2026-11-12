import 'package:flutter/foundation.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import '../db/database_helper.dart';
import '../models/customer.dart';
import '../models/pending_notification.dart';
import '../services/audio_recorder_service.dart';
import '../services/notification_service.dart';
import '../services/overlay_service.dart';
import '../services/parser_service.dart';
import '../services/pending_notification_service.dart';
import '../services/query_service.dart';
import '../services/settings_service.dart';
import '../services/tts_service.dart';
import '../services/voice_conversation_service.dart';
import '../config/app_settings.dart';

/// معالج أوامر الزر العائم
///
/// يستقبل `voice_text` من الـ overlay، ويوجّه المعالجة:
/// 1. نص فارغ → إشعار unclear
/// 2. استعلام → QueryService
/// 3. إنشاء حساب → معالجة مباشرة
/// 4. غير ذلك → VoiceConversationService (الحوار التفاعلي)
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

  // ═══════════════════════════════════════════════════════════
  // التوجيه الرئيسي
  // ═══════════════════════════════════════════════════════════
  static Future<void> _handleVoiceText(Map data) async {
    final text = data['text'] as String? ?? '';
    String? audioPath;

    try {
      audioPath = AudioRecorderService().currentRecordingPath;
    } catch (_) {}

    // ===== نص فارغ =====
    if (text == '__EMPTY__') {
      await PendingNotificationService.create(
        PendingNotification.unclear(
          text: '',
          audioPath: audioPath,
        ),
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

    // ===== تحليل مبدئي =====
    // لا نعالج إضافة الحساب كاختصار منفصل؛ يجب أن تمر عبر الحوار
    // حتى نسأل عن الاسم أو نؤكد إنشاء الحساب عند عدم وجوده.
    final check = ParserService.parsePartial(text);

    // ===== الحوار التفاعلي أو السلوك القديم =====
    final conversationEnabled = SettingsService.getBool(
      AppSettings.voiceConversationEnabled,
      defaultValue: true,
    );

    if (conversationEnabled) {
      await _handleConversation(text, audioPath);
    } else {
      await _handleLegacyTransaction(check, text, audioPath);
    }
  }

  // ═══════════════════════════════════════════════════════════
  // الحوار التفاعلي (الوضع الجديد — الافتراضي)
  // ═══════════════════════════════════════════════════════════
  static Future<void> _handleConversation(
    String text,
    String? audioPath,
  ) async {
    try {
      final result = await VoiceConversationService.processText(text);

      switch (result.step) {
        case ConversationStep.askQuestion:
          await _onAskQuestion(result);
          break;

        case ConversationStep.showCandidates:
          await _onShowCandidates(result, text, audioPath);
          break;

        case ConversationStep.saved:
          await _onSaved(result);
          break;

        case ConversationStep.failed:
          await _onFailed(result);
          break;
      }
    } catch (e) {
      debugPrint('❌ [OverlayHandler] conversation error: $e');
      await TtsService.speak('حدث خطأ');
      VoiceConversationService.cancelSession();
    }
  }

  // ═══════════════════════════════════════════════════════════
  // عند سؤال (حقل ناقص) → TTS + بدء التسجيل تلقائيًا
  // ═══════════════════════════════════════════════════════════
  static Future<void> _onAskQuestion(VoiceConversationResult result) async {
    final prompt = result.prompt;
    if (prompt == null || prompt.isEmpty) return;

    // 1. TTS — انتظر حتى ينتهي
    try {
      await TtsService.speak(prompt);
    } catch (e) {
      debugPrint('⚠️ [OverlayHandler] TTS error: $e');
    }

    // 2. أعلم الـ overlay ليبدأ التسجيل تلقائيًا
    if (result.startListening) {
      try {
        if (await FlutterOverlayWindow.isActive()) {
          await FlutterOverlayWindow.shareData({
            'action': 'start_recording',
            'source': 'conversation',
          });
          debugPrint('🎤 [OverlayHandler] Triggered start_recording');
        }
      } catch (e) {
        debugPrint('⚠️ [OverlayHandler] start_recording shareData: $e');
      }
    }
  }

  // ═══════════════════════════════════════════════════════════
  // عند اسم غامض → TTS + إنشاء إشعار معلّق
  // ═══════════════════════════════════════════════════════════
  static Future<void> _onShowCandidates(
    VoiceConversationResult result,
    String rawText,
    String? audioPath,
  ) async {
    final tts = result.ttsMessage ?? '';
    if (tts.isNotEmpty) {
      try {
        await TtsService.speak(tts);
      } catch (_) {}
    }

    final candidates = result.candidates ?? [];
    final session = VoiceConversationService.currentSession;

    if (candidates.isEmpty) {
      // لا مرشحين — اطلب إضافة حساب جديد عبر إشعار
      await PendingNotificationService.create(
        PendingNotification.noAccount(
          text: rawText,
          customerName: session?.customerName ?? '',
          intent: session?.intent ?? 'debt',
          amount: session?.amount ?? 0,
          currency: session?.currency ?? 'YER',
          items: session?.items ?? '',
          audioPath: audioPath,
        ),
      );
      VoiceConversationService.cancelSession();
      return;
    }

    // إشعار "multiple" بقائمة المرشحين
    final candidatesMaps = candidates
        .map((c) => {
              'id': c.id,
              'name': c.name,
              'phone': c.phone,
              'account_type': c.accountType,
            })
        .toList();

    await PendingNotificationService.create(
      PendingNotification.multiple(
        text: rawText,
        customerName: session?.customerName ?? '',
        intent: session?.intent ?? 'debt',
        amount: session?.amount ?? 0,
        currency: session?.currency ?? 'YER',
        items: session?.items ?? '',
        candidates: candidatesMaps,
        audioPath: audioPath,
        accountType: session?.accountType ?? 'customer',
      ),
    );

    VoiceConversationService.cancelSession();
  }

  // ═══════════════════════════════════════════════════════════
  // عند حفظ ناجح → TransactionHandler أظهر إشعاره الخاص
  // ═══════════════════════════════════════════════════════════
  static Future<void> _onSaved(VoiceConversationResult result) async {
    // TransactionHandler.save يُظهر إشعار نجاح بالفعل + TTS تأكيد
    // لا نحتاج فعل شيء إضافي، فقط إنهاء الجلسة
    VoiceConversationService.cancelSession();
  }

  // ═══════════════════════════════════════════════════════════
  // عند فشل (تجاوز محاولات) → TTS + إشعار فشل
  // ═══════════════════════════════════════════════════════════
  static Future<void> _onFailed(VoiceConversationResult result) async {
    final tts = result.ttsMessage ?? '';
    if (tts.isNotEmpty) {
      try {
        await TtsService.speak(tts);
      } catch (_) {}
    }

    await NotificationService.show(
      '❌ لم أفهم',
      result.errorMessage ?? 'فشل التعرف على العملية',
    );

    VoiceConversationService.cancelSession();
  }

  // ═══════════════════════════════════════════════════════════
  // إنشاء حساب (مستقل عن الحوار)
  // ═══════════════════════════════════════════════════════════
  static Future<void> _handleAddAccount(
    ParsedPartial parsed,
    String text,
    String? audioPath,
  ) async {
    final name = parsed.customerName ?? '';
    if (name.isEmpty) {
      await PendingNotificationService.create(
        PendingNotification.unclear(
          text: text,
          audioPath: audioPath,
        ),
      );
      await TtsService.speak('لم أفهم الاسم');
      return;
    }

    final db = DatabaseHelper.instance;
    final existing = await db.findExactCustomer(name);

    if (existing != null) {
      await TtsService.speakExistsBefore(name);
      await NotificationService.show('موجود مسبقا', name);
      return;
    }

    final id = await db.insertCustomer(Customer(
      name: name,
      accountType: parsed.accountType,
      createdAt: DateTime.now().toIso8601String(),
    ));

    await TtsService.speakAccountCreated(name);

    final typeAr = {
      'customer': 'عميل',
      'supplier': 'مورد',
      'other': 'أخرى',
    }[parsed.accountType] ?? 'عميل';

    await NotificationService.show(
      'تم إنشاء حساب',
      '$name ($typeAr)\nالرقم: #$id',
    );
  }

  // ═══════════════════════════════════════════════════════════
  // السلوك القديم (عند تعطيل الحوار)
  // ═══════════════════════════════════════════════════════════
  static Future<void> _handleLegacyTransaction(
    ParsedPartial parsed,
    String text,
    String? audioPath,
  ) async {
    if (!parsed.isComplete) {
      await PendingNotificationService.create(
        PendingNotification.unclear(
          text: text,
          audioPath: audioPath,
        ),
      );
      await TtsService.speakDidNotUnderstand();
      return;
    }

    final db = DatabaseHelper.instance;
    final customer = await db.findExactCustomer(parsed.customerName!);

    if (customer == null) {
      final partial = await db.findCustomersContaining(parsed.customerName!);

      if (partial.isEmpty) {
        await PendingNotificationService.create(
          PendingNotification.noAccount(
            text: text,
            customerName: parsed.customerName!,
            intent: parsed.intent!,
            amount: parsed.amount!,
            currency: parsed.currency,
            items: parsed.items ?? '',
            audioPath: audioPath,
          ),
        );
        await TtsService.speakNoAccount(parsed.customerName!);
        return;
      }

      if (partial.length == 1) {
        await _createSingleNotification(
          parsed: parsed,
          text: text,
          audioPath: audioPath,
          customer: partial.first,
        );
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
          customerName: parsed.customerName!,
          intent: parsed.intent!,
          amount: parsed.amount!,
          currency: parsed.currency,
          items: parsed.items ?? '',
          candidates: candidates,
          audioPath: audioPath,
        ),
      );
      await TtsService.speakMultipleAccounts();
      return;
    }

    await _createSingleNotification(
      parsed: parsed,
      text: text,
      audioPath: audioPath,
      customer: customer,
    );
  }

  static Future<void> _createSingleNotification({
    required ParsedPartial parsed,
    required String text,
    required String? audioPath,
    required Customer customer,
  }) async {
    await PendingNotificationService.create(
      PendingNotification.single(
        text: text,
        customerName: customer.name,
        intent: parsed.intent!,
        amount: parsed.amount!,
        currency: parsed.currency,
        items: parsed.items ?? '',
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
      'سُجّل $typeLabel بمبلغ ${parsed.amount!.toStringAsFixed(0)} '
      '${parsed.currency} على ${customer.name}. '
      'اضغط [حفظ] في الإشعار للتأكيد',
    );
  }
}

// Overlay Handler v1: النسخة الأساسية
// Overlay Handler v2: إنشاء PendingNotification لكل تسجيل
// Overlay Handler v3: ربط إعدادات الدين على حساب موقوف
// Overlay Handler v4: إعادة كتابة كاملة لاستخدام VoiceConversationService
// - توجيه ذكي: نص فارغ / استعلام / إضافة حساب / حوار
// - عند askQuestion: TTS ثم بدء التسجيل تلقائيًا
// - عند showCandidates: TTS + إشعار معلّق (single/multiple/noAccount)
// - عند saved: TransactionHandler أظهر إشعاره — لا شيء إضافي
// - عند failed: TTS + إشعار فشل
// - احتياطي: السلوك القديم عند تعطيل voiceConversationEnabled
