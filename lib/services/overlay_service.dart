import 'package:flutter/foundation.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_settings.dart';
import 'notification_service.dart';
import 'logger_service.dart';
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

  static Future<bool> show() async {
    await LoggerService.devInfo('overlay', 'show() called');

    if (!await FlutterOverlayWindow.isPermissionGranted()) {
      final granted = await FlutterOverlayWindow.requestPermission();
      if (granted != true) {
        await LoggerService.devWarn('overlay', 'Overlay permission denied');
        return false;
      }
    }

    if (!await Permission.ignoreBatteryOptimizations.isGranted) {
      await Permission.ignoreBatteryOptimizations.request();
    }

    if (!await Permission.notification.isGranted) {
      await Permission.notification.request();
    }

    if (!await Permission.microphone.isGranted) {
      final micStatus = await Permission.microphone.request();
      if (!micStatus.isGranted) {
        await LoggerService.devWarn(
            'overlay', 'Microphone permission denied');
      }
    }

    final actions = _buildNotificationActions();
    await LoggerService.devInfo(
        'overlay', 'Building notification with ${actions.length} actions');
    await NotificationService.showPersistentWithActions(
      id: _notificationId,
      title: '✅ الزر العائم يعمل',
      body: 'اضغط على الزر البرتقالي أو استخدم الأزرار أدناه',
      actions: actions,
      payload: 'overlay_persistent',
    );

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
        await LoggerService.devError(
            'overlay', 'showOverlay error: $e');
        return false;
      }
    }

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

        await LoggerService.devInfo(
            'overlay', 'Sent speech_ready + mode=$mode');
      } catch (e) {
        await LoggerService.devError(
            'overlay', 'shareData error: $e');
      }
    }

    await LoggerService.devInfo(
        'overlay', 'show() completed (opened=$opened)');
    return true;
  }

  static List<NotificationAction> _buildNotificationActions() {
    final actions = <NotificationAction>[];

    if (SettingsService.getBool(
      AppSettings.overlayNotifBtnRecord,
      defaultValue: true,
    )) {
      actions.add(const NotificationAction(
        id: 'overlay_record',
        title: '🎤 ابدأ التسجيل',
        showsUserInterface: true,
        cancelNotification: false,
      ));
    }

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

    if (actions.length > 3) {
      LoggerService.devWarn('overlay',
          '${actions.length} actions requested, Android only supports 3 — keeping first 3');
      return actions.sublist(0, 3);
    }

    return actions;
  }

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
      await LoggerService.devInfo('overlay', 'Notification refreshed');
    } catch (e) {
      await LoggerService.devError(
          'overlay', 'refreshNotification: $e');
    }
  }

  static Future<void> hide() async {
    await LoggerService.devInfo('overlay', 'hide() called');
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
        await LoggerService.devWarn(
            'overlay', 'startRecordingFromNotification: overlay not active');
        return;
      }
      await FlutterOverlayWindow.shareData({
        'action': 'start_recording',
        'source': 'notification',
      });
      await LoggerService.devInfo(
          'overlay', 'Sent start_recording');
    } catch (e) {
      await LoggerService.devError(
          'overlay', 'startRecordingFromNotification: $e');
    }
  }
}

// Overlay Service v1: النسخة الأساسية
// Overlay Service v2: تحسينات جذرية
// Overlay Service v2.1: إصلاح توافق OverlayFlag
// Overlay Service v3: أزرار ديناميكية + refreshNotification
// Overlay Service v4: زر التسجيل showsUserInterface: true
// Overlay Service v5: سجلات المطور (devInfo/devWarn/devError)
