import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:permission_handler/permission_handler.dart';
import 'notification_service.dart';

class OverlayService {
  static const int _notificationId = 9999;

  static Future<bool> isPermissionGranted() async {
    return await FlutterOverlayWindow.isPermissionGranted();
  }

  static Future<bool?> requestPermission() async {
    return await FlutterOverlayWindow.requestPermission();
  }

  static Future<bool> isActive() async {
    return await FlutterOverlayWindow.isActive();
  }

  /// تشغيل الزر العائم (مع معالجة Huawei)
  static Future<bool> show() async {
    // 1) اطلب إذن الظهور فوق التطبيقات
    if (!await FlutterOverlayWindow.isPermissionGranted()) {
      final granted = await FlutterOverlayWindow.requestPermission();
      if (granted != true) return false;
    }

    // 2) اطلب تجاهل تحسين البطارية (مهم جداً على Huawei/Xiaomi/Oppo)
    if (!await Permission.ignoreBatteryOptimizations.isGranted) {
      await Permission.ignoreBatteryOptimizations.request();
    }

    // 3) اطلب إذن الإشعارات (Android 13+)
    if (!await Permission.notification.isGranted) {
      await Permission.notification.request();
    }

    // 4) الإشعار الدائم (يُبقي الزر نشطاً على Huawei)
    await NotificationService.showPersistent(
      id: _notificationId,
      title: '✅ الزر العائم يعمل',
      body: 'اضغط مطولاً على الأيقونة البرتقالية للتسجيل',
    );

    // 5) اعرض النافذة العائمة
    if (!await FlutterOverlayWindow.isActive()) {
      try {
        await FlutterOverlayWindow.showOverlay(
          enableDrag: true,
          height: 80,
          width: 80,
          alignment: OverlayAlignment.centerRight,
          visibility: NotificationVisibility.visibilityPublic,
          positionGravity: PositionGravity.auto,
          flag: OverlayFlag.defaultFlag,
        );
      } catch (e) {
        print('Overlay error: $e');
        return false;
      }
    }

    return true;
  }

  static Future<void> hide() async {
    if (await FlutterOverlayWindow.isActive()) {
      await FlutterOverlayWindow.closeOverlay();
    }
    await NotificationService.cancel(_notificationId);
  }

  static void listen(void Function(dynamic) handler) {
    FlutterOverlayWindow.overlayListener.listen(handler);
  }

  static Future<void> sendData(Map<String, dynamic> data) async {
    await FlutterOverlayWindow.shareData(data);
  }
}
