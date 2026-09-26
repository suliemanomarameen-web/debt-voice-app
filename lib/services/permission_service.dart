import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  /// يطلب كل الأذونات المطلوبة دفعة واحدة
  static Future<Map<String, bool>> requestAll() async {
    final results = <String, bool>{};

    // الميكروفون
    results['microphone'] = await _ask(Permission.microphone);

    // الإشعارات
    results['notification'] = await _ask(Permission.notification);

    // تجاهل تحسين البطارية
    results['battery'] = await _ask(Permission.ignoreBatteryOptimizations);

    // الظهور فوق التطبيقات (منفصل - يُطلب من OverlayService)
    results['overlay'] = true;

    return results;
  }

  static Future<bool> _ask(Permission p) async {
    if (await p.isGranted) return true;
    final status = await p.request();
    return status.isGranted;
  }

  /// هل الأذونات الأساسية ممنوحة؟
  static Future<bool> allGranted() async {
    final mic = await Permission.microphone.isGranted;
    return mic;
  }
}
