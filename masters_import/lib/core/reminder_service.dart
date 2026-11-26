import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class ReminderService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    if (kIsWeb) {
      // Web doesn't support local notifications
      return;
    }

    tzdata.initializeTimeZones();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
  }

  static Future<void> scheduleDaily(int hour, int minute) async {
    if (kIsWeb) {
      // Web doesn't support local notifications
      return;
    }

    await _plugin.cancelAll();
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    await _plugin.zonedSchedule(
      0,
      'Время фокуса',
      'Пара минут фокуса — и день станет лучше.',
      scheduled,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'focus_reminder',
          'Напоминания',
          channelDescription: 'Ежедневное напоминание о фокусе',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  static Future<void> cancel() async {
    if (kIsWeb) {
      return;
    }
    await _plugin.cancelAll();
  }

  static Future<void> scheduleAppointmentReminder(
    String title,
    DateTime startAt,
  ) async {
    if (kIsWeb) {
      return;
    }
    try {
      tzdata.initializeTimeZones();
      final now = DateTime.now();
      var notifyAt = DateTime(
        startAt.year,
        startAt.month,
        startAt.day,
        9,
        0,
      ).subtract(const Duration(days: 1));
      if (!notifyAt.isAfter(now)) {
        notifyAt = startAt.subtract(const Duration(hours: 1));
      }
      if (!notifyAt.isAfter(now)) {
        return;
      }
      final scheduled = tz.TZDateTime.from(notifyAt, tz.local);
      final details = const NotificationDetails(
        android: AndroidNotificationDetails(
          'appointment_reminder',
          'Напоминания о записях',
          channelDescription: 'Напоминания о предстоящих записях',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(),
      );
      await _plugin.zonedSchedule(
        title.hashCode,
        title,
        'Напоминание о записи: $title',
        scheduled,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (_) {
      // Never crash on unsupported platforms
    }
  }

  static Future<void> cancelAppointmentReminder(String id) async {
    if (kIsWeb) {
      return;
    }
    try {
      await _plugin.cancel(id.hashCode);
    } catch (_) {
      // ignore
    }
  }

  static Future<void> scheduleRecurringReminder({
    required String id,
    required String title,
    required String direction,
    required DateTime dueAt,
    required int amountCents,
    required String? accountName,
  }) async {
    if (kIsWeb) {
      return;
    }
    try {
      tzdata.initializeTimeZones();
      final now = DateTime.now();
      var notifyAt = DateTime(dueAt.year, dueAt.month, dueAt.day, 9, 0);
      if (notifyAt.isBefore(now)) {
        notifyAt = dueAt.subtract(const Duration(hours: 1));
      }
      if (notifyAt.isBefore(now)) {
        return;
      }

      final notificationTitle = direction == 'in'
          ? 'Платёж ожидается: $title'
          : 'Оплата: $title';
      final money = (amountCents / 100).toStringAsFixed(2);
      final accountSuffix = accountName == null || accountName.trim().isEmpty
          ? ''
          : ' • $accountName';
      final body = '$money$accountSuffix';

      final scheduled = tz.TZDateTime.from(notifyAt, tz.local);
      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          'recurring_payment',
          'Регулярные платежи',
          channelDescription: 'Напоминания о регулярных платежах',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(),
      );
      await _plugin.zonedSchedule(
        id.hashCode.abs(),
        notificationTitle,
        body,
        scheduled,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (_) {
      // Never crash on unsupported platforms
    }
  }

  static Future<void> cancelRecurringReminder(String id) async {
    if (kIsWeb) {
      return;
    }
    try {
      await _plugin.cancel(id.hashCode.abs());
    } catch (_) {
      // ignore
    }
  }
}
