import 'package:flutter_overlay_window/flutter_overlay_window.dart';

class OverlayService {
  /// هل الإذن ممنوح؟
  static Future<bool> isPermissionGranted() async {
    return await FlutterOverlayWindow.isPermissionGranted();
  }

  /// طلب إذن الظهور فوق التطبيقات
  static Future<bool?> requestPermission() async {
    return await FlutterOverlayWindow.requestPermission();
  }

  /// هل النافذة العائمة نشطة الآن؟
  static Future<bool> isActive() async {
    return await FlutterOverlayWindow.isActive();
  }

  /// تشغيل الزر العائم
  static Future<void> show() async {
    if (!await FlutterOverlayWindow.isPermissionGranted()) {
      await FlutterOverlayWindow.requestPermission();
    }
    if (!await FlutterOverlayWindow.isActive()) {
      await FlutterOverlayWindow.showOverlay(
        enableDrag: true,
        height: 80,
        width: 80,
        alignment: OverlayAlignment.centerRight,
        visibility: NotificationVisibility.visibilityPublic,
        positionGravity: PositionGravity.auto,
        flag: OverlayFlag.defaultFlag,
      );
    }
  }

  /// إيقاف الزر العائم
  static Future<void> hide() async {
    if (await FlutterOverlayWindow.isActive()) {
      await FlutterOverlayWindow.closeOverlay();
    }
  }

  /// الاستماع لرسائل من النافذة العائمة
  static void listen(void Function(dynamic) handler) {
    FlutterOverlayWindow.overlayListener.listen(handler);
  }

  /// إرسال بيانات من/إلى النافذة العائمة
  static Future<void> sendData(Map<String, dynamic> data) async {
    await FlutterOverlayWindow.shareData(data);
  }
}
