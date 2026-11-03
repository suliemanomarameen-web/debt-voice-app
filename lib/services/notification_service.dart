import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationAction {
  final String id;
  final String title;

  const NotificationAction({required this.id, required this.title});
}

class NotificationService {
  static final _notif = FlutterLocalNotificationsPlugin();
  static int _idCounter = 100000;

  /// رد نداء عند الضغط على أي إشعار (فتح التطبيق)
  static void Function(String? payload)? onTap;

  /// 🆕 رد نداء عند الضغط على زر في الإشعار (بدون فتح التطبيق)
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

    // إذا ضغط زر (actionId != null وليس default)
    if (actionId != null &&
        actionId.isNotEmpty &&
        actionId != 'default_action') {
      debugPrint('🔔 [Notif] Action: $actionId, payload: $payload');
      onAction?.call(actionId, payload);
      return;
    }

    // إذا فتح التطبيق من الإشعار
    debugPrint('🔔 [Notif] Tap: $payload (id=${resp.id})');
    onTap?.call(payload);
  }

  // ═══════════════════════════════════════════════════════════
  // إشعارات عادية (بدون أزرار)
  // ═══════════════════════════════════════════════════════════

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

  // ═══════════════════════════════════════════════════════════
  // إشعارات بأزرار
  // ═══════════════════════════════════════════════════════════

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
                    showsUserInterface: false,
                    cancelNotification: false,
                  ))
              .toList(),
        ),
      ),
      payload: payload,
    );
  }

  // ═══════════════════════════════════════════════════════════
  // ملخص مجموعة
  // ═══════════════════════════════════════════════════════════

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

  // ═══════════════════════════════════════════════════════════
  // الإشعار الدائم (الزر العائم)
  // ═══════════════════════════════════════════════════════════

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

  // ═══════════════════════════════════════════════════════════
  // إلغاء
  // ═══════════════════════════════════════════════════════════

  static Future<void> cancel(int id) async {
    await _notif.cancel(id);
  }

  static Future<void> cancelAll() async {
    await _notif.cancelAll();
  }
}

/// Top-level function للـ background actions
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) async {
  WidgetsFlutterBinding.ensureInitialized();

  final payload = response.payload ?? '';
  final actionId = response.actionId;

  debugPrint('🔔 [Notif BG] Action: $actionId, payload: $payload');

  // في الـ background، لا يمكن استدعاء onAction مباشرة.
  // الحل: الإجراءات تُنفّذ هنا (في المرحلة 3 سيُضاف منطق الحفظ مباشرة).
  // مؤقتاً: لا شيء — الإجراء سيُنفّذ عند فتح التطبيق عبر onAction
}

// Notification Service v2: دعم أزرار تفاعلية + Group Summary + payloads متعددة
