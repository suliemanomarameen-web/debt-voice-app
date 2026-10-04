import 'package:url_launcher/url_launcher.dart';

class WhatsAppService {
  /// فتح واتساب مع رسالة جاهزة
  /// [phone] رقم هاتف العميل (اختياري). إذا كان فارغاً، سيتم فتح واتساب بدون رقم محدد.
  /// [customerName] اسم العميل
  /// [balance] الرصيد المتبقي
  static Future<void> sendReminder({
    String? phone,
    required String customerName,
    required double balance,
  }) async {
    // تنسيق المبلغ
    final String formattedBalance = balance.toStringAsFixed(0);

    // تجهيز نص الرسالة
    final String message = '''
السلام عليكم $customerName،
نود تذكيركم بالرصيد المتبقي:
$formattedBalance ريال

شكراً لتعاملكم معنا
''';

    // تشفير النص
    final String encodedMessage = Uri.encodeComponent(message);

    // تجهيز الرابط
    final Uri whatsappUrl;
    if (phone != null && phone.isNotEmpty) {
      final String cleanPhone = phone.replaceAll(RegExp(r'[^\d]'), '');
      whatsappUrl = Uri.parse('https://wa.me/$cleanPhone?text=$encodedMessage');
    } else {
      whatsappUrl = Uri.parse('https://wa.me/?text=$encodedMessage');
    }

    // محاولة فتح الرابط
    if (await canLaunchUrl(whatsappUrl)) {
      await launchUrl(whatsappUrl, mode: LaunchMode.externalApplication);
    } else {
      throw Exception('تعذر فتح واتساب. تأكد من تثبيت التطبيق.');
    }
  }
}
