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

  /// تشغيل الزر العائم (مع معالجة Huawei)
  ///
  /// الخطوات:
  /// 1. طلب إذن الظهور فوق التطبيقات
  /// 2. طلب تجاهل تحسين البطارية
  /// 3. طلب إذن الإشعارات
  /// 4. **طلب إذن الميكروفون** (جديد — قبل فتح الـ overlay)
  /// 5. إظهار الإشعار الدائم بأزرار
  /// 6. فتح الـ overlay
  /// 7. **إرسال speech_ready ومعلومات الوضع** (جديد — بعد الفتح)
  static Future<bool> show() async {
    // 1) إذن الظهور فوق التطبيقات
    if (!await FlutterOverlayWindow.isPermissionGranted()) {
      final granted = await FlutterOverlayWindow.requestPermission();
      if (granted != true) return false;
    }

    // 2) تجاهل تحسين البطارية (مهم على Huawei/Xiaomi/Oppo)
    if (!await Permission.ignoreBatteryOptimizations.isGranted) {
      await Permission.ignoreBatteryOptimizations.request();
    }

    // 3) إذن الإشعارات (Android 13+)
    if (!await Permission.notification.isGranted) {
      await Permission.notification.request();
    }

    // 4) 🆕 إذن الميكروفون — هنا في main isolate (Activity موجود)
    //    لا يمكن طلبه من overlay isolate (لن يظهر حوار)
    if (!await Permission.microphone.isGranted) {
      final micStatus = await Permission.microphone.request();
      if (!micStatus.isGranted) {
        debugPrint('⚠️ [OverlayService] Microphone permission denied');
        // نكمل — المستخدم قد يمنحه لاحقًا، لكن التسجيل لن يعمل
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
          flag: OverlayDefaultFlag.defaultFlag,
        );
        opened = true;
      } catch (e) {
        debugPrint('❌ [OverlayService] showOverlay error: $e');
        return false;
      }
    }

    // 7) 🆕 بعد فتح الـ overlay — انتظر ثم أرسل الحالة
    if (opened) {
      // انتظر حتى يكون overlayMain قد بدأ وبدأ يستمع
      await Future.delayed(const Duration(milliseconds: 800));

      try {
        // أرسل speech_ready
        await FlutterOverlayWindow.shareData({'action': 'speech_ready'});

        // أرسل وضع التسجيل المحفوظ
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

  /// 🆕 إرسال أمر بدء التسجيل للـ overlay من داخل التطبيق
  ///
  /// يُستخدم عند الضغط على "🎤 ابدأ التسجيل" من الإشعار الدائم.
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
// - طلب إذن الميكروفون في main isolate قبل فتح الـ overlay
// - إرسال speech_ready بعد showOverlay + تأخير 800ms (بدل main())
// - إرسال وضع التسجيل (long_press / tap) للـ overlay
// - إشعار دائم بزر "🎤 ابدأ التسجيل"
// - دالة startRecordingFromNotification() لبدء التسجيل من الإشعار
