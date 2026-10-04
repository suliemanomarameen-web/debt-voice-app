import 'package:url_launcher/url_launcher.dart';

class WhatsAppService {
  /// فتح واتساب مع رسالة تذكير بالرصيد
  static Future<void> sendReminder({
    String? phone,
    required String customerName,
    required double balance,
  }) async {
    final String formattedBalance = balance.toStringAsFixed(0);

    final String message = '''
السلام عليكم $customerName،
نود تذكيركم بالرصيد المتبقي:
$formattedBalance ريال

شكراً لتعاملكم معنا
''';

    await _openWhatsApp(phone: phone, message: message);
  }

  /// إرسال رسالة تأكيد عملية جديدة للعميل
  static Future<void> sendTransactionNotification({
    String? phone,
    required String customerName,
    required String type,
    required double amount,
    required double newBalance,
  }) async {
    if (phone == null || phone.isEmpty) return;

    String typeLabel;
    String emoji;
    switch (type) {
      case 'debt':
        typeLabel = 'دين جديد';
        emoji = '📌';
        break;
      case 'payment':
        typeLabel = 'دفعة سداد';
        emoji = '✅';
        break;
      case 'return':
        typeLabel = 'مرتجع';
        emoji = '🔄';
        break;
      default:
        typeLabel = 'عملية';
        emoji = '📝';
    }

    final String message = '''
السلام عليكم $customerName،
$emoji تم تسجيل عملية جديدة في حسابكم:

📋 النوع: $typeLabel
💰 المبلغ: ${amount.toStringAsFixed(0)} ريال

📊 الرصيد المتبقي: ${newBalance.toStringAsFixed(0)} ريال

شكراً لتعاملكم معنا
''';

    await _openWhatsApp(phone: phone, message: message);
  }

  /// دالة مساعدة لفتح واتساب
  static Future<void> _openWhatsApp({
    String? phone,
    required String message,
  }) async {
    final String encodedMessage = Uri.encodeComponent(message);

    final Uri whatsappUrl;
    if (phone != null && phone.isNotEmpty) {
      final String cleanPhone = phone.replaceAll(RegExp(r'[^\d]'), '');
      whatsappUrl = Uri.parse('https://wa.me/$cleanPhone?text=$encodedMessage');
    } else {
      whatsappUrl = Uri.parse('https://wa.me/?text=$encodedMessage');
    }

    if (await canLaunchUrl(whatsappUrl)) {
      await launchUrl(whatsappUrl, mode: LaunchMode.externalApplication);
    } else {
      throw Exception('تعذر فتح واتساب. تأكد من تثبيت التطبيق.');
    }
  }
}
