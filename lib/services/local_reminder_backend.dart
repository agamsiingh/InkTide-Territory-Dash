import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import 'reminders.dart';

/// Schedules reminders on the device with flutter_local_notifications.
/// Everything is local: no server and no data leaves the phone.
class LocalReminderBackend implements ReminderBackend {
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'inktide_reminders',
      'Game reminders',
      channelDescription: 'Friendly nudges about rewards, deals and events',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      icon: 'ic_stat_inktide',
    ),
  );

  @override
  Future<void> init() async {
    if (_ready) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_inktide'),
      ),
    );
    _ready = true;
  }

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  @override
  Future<bool> requestPermission() async {
    await init();
    return await _android?.requestNotificationsPermission() ?? false;
  }

  @override
  Future<void> cancelAll() async {
    await init();
    await _plugin.cancelAll();
  }

  @override
  Future<void> schedule(Reminder r) async {
    await init();
    // The instant is what matters, so UTC is fine for a one-off alarm.
    final at = tz.TZDateTime.from(r.when.toUtc(), tz.UTC);
    try {
      await _plugin.zonedSchedule(
        id: r.id,
        scheduledDate: at,
        notificationDetails: _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: r.title,
        body: r.body,
      );
    } catch (e) {
      debugPrint('could not schedule reminder ${r.id}: $e');
    }
  }
}
