import 'package:flutter/foundation.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  static Future<bool> show() async {
    // 1) إذن الظهور فوق التطبيقات
    if (!await FlutterOverlayWindow.isPermissionGranted()) {
      final granted = await FlutterOverlayWindow.requestPermission();
      if (granted != true) return false;
    }

    // 2) تجاهل تحسين البطارية
    if (!await Permission.ignoreBatteryOptimizations.isGranted) {
      await Permission.ignoreBatteryOptimizations.request();
    }

    // 3) إذن الإشعارات
    if (!await Permission.notification.isGranted) {
      await Permission.notification.request();
    }

    // 4) إذن الميكروفون (في main isolate — Activity موجود)
    if (!await Permission.microphone.isGranted) {
      final micStatus = await Permission.microphone.request();
      if (!micStatus.isGranted) {
        debugPrint('⚠️ [OverlayService] Microphone permission denied');
      }
    }

    // 5) الإشعار الدائم مع زر "🎤 ابدأ التسجيل"
    await NotificationService.showPersistentWithActions(
      id: _notificationId,
      title: '✅ الزر العائم يعمل',
      body: 'اضغط على الزر البرتقالي أو استخدم "🎤 ابدأ التسجيل"',
      actions: const [
        NotificationAction(
          id: 'overlay_record',
          title: '🎤 ابدأ التسجيل',
          showsUserInterface: false,
          cancelNotification: false,
        ),
      ],
      payload: 'overlay_persistent',
    );

    // 6) اعرض النافذة العائمة
    bool opened = false;
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
        opened = true;
      } catch (e) {
        debugPrint('❌ [OverlayService] showOverlay error: $e');
        return false;
      }
    }

    // 7) بعد فتح الـ overlay — انتظر ثم أرسل الحالة
    if (opened) {
      await Future.delayed(const Duration(milliseconds: 800));

      try {
        await FlutterOverlayWindow.shareData({'action': 'speech_ready'});

        final prefs = await SharedPreferences.getInstance();
        final mode = prefs.getString('overlay_record_mode') ?? 'long_press';
        await FlutterOverlayWindow.shareData({
          'action': 'overlay_mode',
          'mode': mode,
        });

        debugPrint('✅ [OverlayService] Sent speech_ready + mode=$mode');
      } catch (e) {
        debugPrint('⚠️ [OverlayService] shareData error: $e');
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

  static Future<void> startRecordingFromNotification() async {
    try {
      if (!await FlutterOverlayWindow.isActive()) {
        debugPrint('⚠️ [OverlayService] Overlay not active — cannot start');
        return;
      }
      await FlutterOverlayWindow.shareData({
        'action': 'start_recording',
        'source': 'notification',
      });
      debugPrint('🎤 [OverlayService] Sent start_recording');
    } catch (e) {
      debugPrint('❌ [OverlayService] startRecordingFromNotification: $e');
    }
  }
}

// Overlay Service v1: النسخة الأساسية (show/hide/listen/sendData)
// Overlay Service v2: تحسينات جذرية للزر العائم
// Overlay Service v2.1: إصلاح توافق OverlayFlag بدلًا من OverlayDefaultFlag
