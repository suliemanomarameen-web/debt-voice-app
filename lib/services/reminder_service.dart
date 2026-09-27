import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

class ReminderService {
  static final _notif = FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    tz_data.initializeTimeZones();
  }

  static Future<void> scheduleDaily({
    required String summary,
    int hour = 9,
    int minute = 0,
  }) async {
    final scheduled = _nextInstance(hour, minute);
    await _notif.zonedSchedule(
      100,
      'متابعة الديون اليومية',
      summary,
      scheduled,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'debt_channel',
          'دفتر الديون',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  static Future<void> scheduleForCustomer({
    required int customerId,
    required String customerName,
    required double amount,
    required int daysFromNow,
  }) async {
    final when = tz.TZDateTime.now(tz.local).add(Duration(days: daysFromNow));
    await _notif.zonedSchedule(
      customerId,
      'متابعة: $customerName',
      'الرصيد المتبقي: ${amount.toStringAsFixed(0)} ريال',
      when,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'debt_channel',
          'دفتر الديون',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  static tz.TZDateTime _nextInstance(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }
}
