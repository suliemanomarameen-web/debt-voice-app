import 'package:flutter_overlay_window/flutter_overlay_window.dart';
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

  static Future<void> show() async {
    if (!await FlutterOverlayWindow.isPermissionGranted()) {
      final granted = await FlutterOverlayWindow.requestPermission();
      if (granted != true) return;
    }

    await NotificationService.showPersistent(
      id: _notificationId,
      title: '✅ الزر العائم يعمل',
      body: 'اضغط مطولاً على الأيقونة البرتقالية للتسجيل',
    );

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
