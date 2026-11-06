import 'package:flutter/foundation.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_settings.dart';
import 'notification_service.dart';
import 'settings_service.dart';

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

    // 5) الإشعار الدائم مع أزرار ديناميكية
    final actions = _buildNotificationActions();
    await NotificationService.showPersistentWithActions(
      id: _notificationId,
      title: '✅ الزر العائم يعمل',
      body: 'اضغط على الزر البرتقالي أو استخدم الأزرار أدناه',
      actions: actions,
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

  // ═══════════════════════════════════════════════════════════
  // 🆕 بناء الأزرار ديناميكياً حسب الإعدادات (3 كحد أقصى)
  // ═══════════════════════════════════════════════════════════
  static List<NotificationAction> _buildNotificationActions() {
    final actions = <NotificationAction>[];

    // الأولوية 1: 🎤 ابدأ التسجيل (لا يفتح التطبيق)
    if (SettingsService.getBool(
      AppSettings.overlayNotifBtnRecord,
      defaultValue: true,
    )) {
      actions.add(const NotificationAction(
        id: 'overlay_record',
        title: '🎤 ابدأ التسجيل',
        showsUserInterface: false,
        cancelNotification: false,
      ));
    }

    // الأولوية 2: ➕ عملية سريعة (يفتح التطبيق)
    if (SettingsService.getBool(
      AppSettings.overlayNotifBtnQuickTx,
      defaultValue: false,
    )) {
      actions.add(const NotificationAction(
        id: 'overlay_quick_tx',
        title: '➕ عملية',
        showsUserInterface: true,
        cancelNotification: false,
      ));
    }

    // الأولوية 3: 📋 الإشعارات (يفتح التطبيق)
    if (SettingsService.getBool(
      AppSettings.overlayNotifBtnNotifications,
      defaultValue: false,
    )) {
      actions.add(const NotificationAction(
        id: 'overlay_notifications',
        title: '📋 الإشعارات',
        showsUserInterface: true,
        cancelNotification: false,
      ));
    }

    // الأولوية 4: 👤 عميل جديد (يفتح التطبيق)
    if (SettingsService.getBool(
      AppSettings.overlayNotifBtnNewCustomer,
      defaultValue: false,
    )) {
      actions.add(const NotificationAction(
        id: 'overlay_new_customer',
        title: '👤 عميل جديد',
        showsUserInterface: true,
        cancelNotification: false,
      ));
    }

    // الأولوية 5: 📊 الإحصائيات (يفتح التطبيق)
    if (SettingsService.getBool(
      AppSettings.overlayNotifBtnStats,
      defaultValue: false,
    )) {
      actions.add(const NotificationAction(
        id: 'overlay_stats',
        title: '📊 الإحصائيات',
        showsUserInterface: true,
        cancelNotification: false,
      ));
    }

    // الأولوية 6: ⏹️ إيقاف الزر (لا يفتح التطبيق)
    if (SettingsService.getBool(
      AppSettings.overlayNotifBtnStopOverlay,
      defaultValue: false,
    )) {
      actions.add(const NotificationAction(
        id: 'overlay_stop',
        title: '⏹️ إيقاف الزر',
        showsUserInterface: false,
        cancelNotification: true,
      ));
    }

    // ⚠️ Android يدعم 3 أزرار كحد أقصى — نأخذ الأول 3 فقط
    if (actions.length > 3) {
      debugPrint('⚠️ [OverlayService] ${actions.length} actions requested, '
          'Android only supports 3 — keeping first 3');
      return actions.sublist(0, 3);
    }

    return actions;
  }

  // ═══════════════════════════════════════════════════════════
  // تحديث الإشعار (عند تغيير الإعدادات)
  // ═══════════════════════════════════════════════════════════
  static Future<void> refreshNotification() async {
    if (!await FlutterOverlayWindow.isActive()) return;

    try {
      final actions = _buildNotificationActions();
      await NotificationService.showPersistentWithActions(
        id: _notificationId,
        title: '✅ الزر العائم يعمل',
        body: 'اضغط على الزر البرتقالي أو استخدم الأزرار أدناه',
        actions: actions,
        payload: 'overlay_persistent',
      );
      debugPrint('✅ [OverlayService] Notification refreshed');
    } catch (e) {
      debugPrint('❌ [OverlayService] refreshNotification: $e');
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

  /// إرسال أمر بدء التسجيل للـ overlay
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
// - إرسال speech_ready بعد showOverlay + تأخير 800ms
// - إرسال وضع التسجيل (long_press / tap) للـ overlay
// - إشعار دائم بزر "🎤 ابدأ التسجيل"
// Overlay Service v2.1: إصلاح توافق OverlayFlag بدلًا من OverlayDefaultFlag
// Overlay Service v3: أزرار ديناميكية
// - _buildNotificationActions: يبني الأزرار حسب AppSettings (6 مفاتيح)
// - Android يدعم 3 أزرار كحد أقصى — نأخذ الأول 3
// - refreshNotification: تحديث الإشعار عند تغيير الإعدادات
