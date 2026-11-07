import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationAction {
  final String id;
  final String title;
  final bool showsUserInterface;
  final bool cancelNotification;

  const NotificationAction({
    required this.id,
    required this.title,
    this.showsUserInterface = true,
    this.cancelNotification = true,
  });
}

class NotificationService {
  static final _notif = FlutterLocalNotificationsPlugin();
  static int _idCounter = 100000;

  static void Function(String? payload)? onTap;
  static void Function(String actionId, String? payload)? onAction;

  static const String channelId = 'debt_channel';
  static const String channelName = 'دفتر الديون';
  static const String channelDesc = 'إشعارات التطبيق';

  static const String persistentChannelId = 'debt_persistent';
  static const String persistentChannelName = 'الزر العائم';
  static const String persistentChannelDesc =
      'إشعار دائم لإبقاء الزر العائم يعمل';

  static Future<void> init() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);

    await _notif.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (resp) {
        _handleResponse(resp);
      },
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    const channel = AndroidNotificationChannel(
      channelId,
      channelName,
      description: channelDesc,
      importance: Importance.high,
    );

    const persistChannel = AndroidNotificationChannel(
      persistentChannelId,
      persistentChannelName,
      description: persistentChannelDesc,
      importance: Importance.low,
    );

    final androidImpl = _notif.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.createNotificationChannel(channel);
    await androidImpl?.createNotificationChannel(persistChannel);
    await androidImpl?.requestNotificationsPermission();
  }

  // ═══════════════════════════════════════════════════════════
  // 🆕 المعالج الأمامي — يكتب flags أيضاً
  // ═══════════════════════════════════════════════════════════
  //
  // عندما التطبيق في المقدمة (أو في recent apps)، Android يستدعي
  // هذا المعالج بدلاً من المعالج الخلفي. نكتب flag لكل action
  // حتى يقرأه overlay_widget polling.
  static void _handleResponse(NotificationResponse resp) {
    final payload = resp.payload ?? '';
    final actionId = resp.actionId;

    // 🆕 اكتب flags لكل action
    if (actionId != null && actionId.isNotEmpty) {
      _writeFlagForAction(actionId);
    }

    if (actionId != null &&
        actionId.isNotEmpty &&
        actionId != 'default_action') {
      debugPrint('🔔 [Notif] Action: $actionId, payload: $payload');
      onAction?.call(actionId, payload);
      return;
    }

    debugPrint('🔔 [Notif] Tap: $payload (id=${resp.id})');
    onTap?.call(payload);
  }

  // 🆕 يكتب flag في SharedPreferences حسب actionId
  static Future<void> _writeFlagForAction(String actionId) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      switch (actionId) {
        case 'overlay_record':
          await prefs.setBool('pending_overlay_record', true);
          debugPrint('🔔 [Notif] Set flag: pending_overlay_record');
          break;

        case 'overlay_quick_tx':
          await prefs.setBool('pending_quick_tx', true);
          break;

        case 'overlay_new_customer':
          await prefs.setBool('pending_new_customer', true);
          break;

        case 'overlay_stats':
          await prefs.setBool('pending_open_stats', true);
          break;

        case 'overlay_notifications':
          await prefs.setBool('pending_open_notifications', true);
          break;

        case 'overlay_stop':
          await prefs.setBool('pending_stop_overlay', true);
          break;
      }
    } catch (e) {
      debugPrint('❌ [Notif] _writeFlagForAction: $e');
    }
  }

  static Future<void> show(
    String title,
    String body, {
    String? payload,
    int? notificationId,
    String? groupKey,
  }) async {
    final id = notificationId ?? (_idCounter++);
    await _notif.show(
      id,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          channelDescription: channelDesc,
          importance: Importance.high,
          priority: Priority.high,
          styleInformation: BigTextStyleInformation(body),
          groupKey: groupKey,
        ),
      ),
      payload: payload,
    );
  }

  static Future<void> showWithActions({
    required String title,
    required String body,
    required List<NotificationAction> actions,
    required String payload,
    int? notificationId,
    String? groupKey,
    Importance importance = Importance.high,
  }) async {
    final id = notificationId ?? (_idCounter++);

    await _notif.show(
      id,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          channelDescription: channelDesc,
          importance: importance,
          priority: Priority.high,
          styleInformation: BigTextStyleInformation(body),
          groupKey: groupKey,
          actions: actions
              .map((a) => AndroidNotificationAction(
                    a.id,
                    a.title,
                    showsUserInterface: a.showsUserInterface,
                    cancelNotification: a.cancelNotification,
                  ))
              .toList(),
        ),
      ),
      payload: payload,
    );
  }

  static Future<void> showGroupSummary({
    required String groupKey,
    required String title,
    required String body,
    String? payload,
  }) async {
    const summaryId = 999999;
    await _notif.show(
      summaryId,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          channelDescription: channelDesc,
          importance: Importance.high,
          priority: Priority.high,
          groupKey: groupKey,
          setAsGroupSummary: true,
          styleInformation: BigTextStyleInformation(body),
        ),
      ),
      payload: payload,
    );
  }

  static Future<void> showPersistent({
    required int id,
    required String title,
    required String body,
  }) async {
    await _notif.show(
      id,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          persistentChannelId,
          persistentChannelName,
          channelDescription: persistentChannelDesc,
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          autoCancel: false,
          showWhen: false,
        ),
      ),
    );
  }

  static Future<void> showPersistentWithActions({
    required int id,
    required String title,
    required String body,
    required List<NotificationAction> actions,
    String? payload,
  }) async {
    await _notif.show(
      id,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          persistentChannelId,
          persistentChannelName,
          channelDescription: persistentChannelDesc,
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          autoCancel: false,
          showWhen: false,
          onlyAlertOnce: true,
          styleInformation: BigTextStyleInformation(body),
          actions: actions
              .map((a) => AndroidNotificationAction(
                    a.id,
                    a.title,
                    showsUserInterface: a.showsUserInterface,
                    cancelNotification: a.cancelNotification,
                  ))
              .toList(),
        ),
      ),
      payload: payload,
    );
  }

  static Future<void> cancel(int id) async {
    await _notif.cancel(id);
  }

  static Future<void> cancelAll() async {
    await _notif.cancelAll();
  }
}

// ═══════════════════════════════════════════════════════════════
// 🆕 المعالج الخلفي لأزرار الإشعار
// ═══════════════════════════════════════════════════════════════
//
// يعمل عندما التطبيق في الخلفية (مغلق أو في تطبيق آخر).
// يكتب flags في SharedPreferences ليقرأها overlay_widget polling.
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) async {
  WidgetsFlutterBinding.ensureInitialized();

  final actionId = response.actionId;
  debugPrint('🔔 [Notif BG] Action: $actionId');

  if (actionId == null || actionId.isEmpty) return;

  try {
    final prefs = await SharedPreferences.getInstance();

    switch (actionId) {
      case 'overlay_record':
        await prefs.setBool('pending_overlay_record', true);
        debugPrint('🔔 [Notif BG] Set pending_overlay_record = true');
        break;

      case 'overlay_quick_tx':
        await prefs.setBool('pending_quick_tx', true);
        break;

      case 'overlay_new_customer':
        await prefs.setBool('pending_new_customer', true);
        break;

      case 'overlay_stats':
        await prefs.setBool('pending_open_stats', true);
        break;

      case 'overlay_notifications':
        await prefs.setBool('pending_open_notifications', true);
        break;

      case 'overlay_stop':
        await prefs.setBool('pending_stop_overlay', true);
        break;
    }
  } catch (e) {
    debugPrint('❌ [Notif BG] Error: $e');
  }
}

// Notification Service v1: الخدمة الأساسية
// Notification Service v2: أزرار تفاعلية + Group Summary + onAction
// Notification Service v2.1: showsUserInterface + cancelNotification
// Notification Service v3: showPersistentWithActions
// Notification Service v4: notificationTapBackground يكتب flags
// Notification Service v5: إصلاح زر التسجيل
// - _handleResponse يكتب flag لكل action (قبل استدعاء onAction)
// - _writeFlagForAction: دالة مساعدة
// - الآن overlay_widget يستقبل الأوامر في كل الحالات (foreground + background)
