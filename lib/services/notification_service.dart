import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final _notif = FlutterLocalNotificationsPlugin();
  static int _idCounter = 1;

  static Future<void> init() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);

    await _notif.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (resp) {},
    );

    const channel = AndroidNotificationChannel(
      'debt_channel',
      'دفتر الديون',
      description: 'إشعارات التطبيق',
      importance: Importance.high,
    );

    const persistChannel = AndroidNotificationChannel(
      'debt_persistent',
      'الزر العائم',
      description: 'إشعار دائم لإبقاء الزر العائم يعمل',
      importance: Importance.low,
    );

    final androidImpl = _notif.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.createNotificationChannel(channel);
    await androidImpl?.createNotificationChannel(persistChannel);
    await androidImpl?.requestNotificationsPermission();
  }

  static Future<void> show(String title, String body) async {
    await _notif.show(
      _idCounter++,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'debt_channel',
          'دفتر الديون',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
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
          'debt_persistent',
          'الزر العائم',
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
}
