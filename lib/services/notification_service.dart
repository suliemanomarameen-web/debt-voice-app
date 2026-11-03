import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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

  static void _handleResponse(NotificationResponse resp) {
    final payload = resp.payload ?? '';
    final actionId = resp.actionId;

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

  static Future<void> cancel(int id) async {
    await _notif.cancel(id);
  }

  static Future<void> cancelAll() async {
    await _notif.cancelAll();
  }
}

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) async {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('🔔 [Notif BG] Action: ${response.actionId}');
}

// Notification Service v1: الخدمة الأساسية (show, showPersistent, cancel)
// Notification Service v2: دعم أزرار تفاعلية + Group Summary + payloads متعددة + onAction
// Notification Service v2.1: إضافة showsUserInterface + cancelNotification في NotificationAction
