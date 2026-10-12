import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'whatsapp_service.dart';

/// خدمة موحّدة تُستدعى بعد إضافة أي عملية
/// - تُرسل واتساب تلقائياً (إذا مُفعّل)
/// - مستقبلاً: إشعارات، TTS، إحصائيات، إلخ
class NotificationDispatcher {
  /// يُستدعى بعد إضافة عملية جديدة
  ///
  /// [customerId]   - معرّف العميل
  /// [customerName] - اسم العميل (للعرض في الرسالة)
  /// [phone]        - رقم الهاتف (يمكن أن يكون null)
  /// [type]         - نوع العملية (debt/payment/return)
  /// [amount]       - المبلغ
  /// [newBalance]   - الرصيد الجديد بعد العملية
  /// [source]       - مصدر العملية (voice/overlay/manual/customer_screen)
  static Future<void> afterTransactionAdded({
    required int customerId,
    required String customerName,
    required String? phone,
    required String type,
    required double amount,
    required double newBalance,
    required String source,
  }) async {
    // 1) واتساب (إذا مُفعّل + يوجد رقم هاتف)
    await _maybeSendWhatsApp(
      phone: phone,
      customerName: customerName,
      type: type,
      amount: amount,
      newBalance: newBalance,
    );

    // 2) مستقبلاً: إشعارات، إحصائيات، إلخ
    // ...
  }

  // ═══════════════════════════════════════════════════════════
  // واتساب
  // ═══════════════════════════════════════════════════════════
  static Future<void> _maybeSendWhatsApp({
    required String? phone,
    required String customerName,
    required String type,
    required double amount,
    required double newBalance,
  }) async {
    try {
      // 1) فحص إعداد "الواتساب التلقائي"
      final sp = await SharedPreferences.getInstance();
      final autoWhatsApp = sp.getBool('auto_whatsapp') ?? false;

      if (!autoWhatsApp) {
        debugPrint('ℹ️ [NotifDispatcher] WhatsApp disabled');
        return;
      }

      // 2) فحص وجود رقم هاتف
      if (phone == null || phone.trim().isEmpty) {
        debugPrint('ℹ️ [NotifDispatcher] No phone number');
        return;
      }

      // 3) تأخير بسيط قبل الفتح (لتجنب تعارض)
      await Future.delayed(const Duration(milliseconds: 400));

      // 4) إرسال
      await WhatsAppService.sendTransactionNotification(
        phone: phone,
        customerName: customerName,
        type: type,
        amount: amount,
        newBalance: newBalance,
      );

      debugPrint('✅ [NotifDispatcher] WhatsApp sent to $customerName');
    } catch (e) {
      // لا نُعيد رمي الخطأ — فقط نسجّله
      debugPrint('❌ [NotifDispatcher] WhatsApp error: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // أدوات مساعدة
  // ═══════════════════════════════════════════════════════════

  /// فحص سريع: هل يجب إرسال واتساب؟
  /// مفيد للواجهة (مثلاً: عرض أيقونة في الزر)
  static Future<bool> shouldSendWhatsApp() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getBool('auto_whatsapp') ?? false;
  }
}
