import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final _notif = FlutterLocalNotificationsPlugin();
  static int _idCounter = 1;

  static Future<void> init() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);

    await _notif.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (resp) {
        // عند الضغط على الإشعار
      },
    );

    const channel = AndroidNotificationChannel(
      'debt_channel',
      'دفتر الديون',
      description: 'إشعارات التطبيق',
      importance: Importance.high,
    );

    await _notif
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  /// إشعار فوري عادي
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
}
