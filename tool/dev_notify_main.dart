// Throwaway probe (not shipped): asks for notification permission and schedules
// one real reminder ~25 s from now through the same backend the game uses, so
// it can be watched firing on a phone.
// Run: flutter run --release -t tool/dev_notify_main.dart -d <device>
import 'package:flutter/material.dart';
import 'package:inktide/services/local_reminder_backend.dart';
import 'package:inktide/services/reminders.dart';

void main() => runApp(const MaterialApp(home: _Probe()));

class _Probe extends StatefulWidget {
  const _Probe();
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  String status = 'starting...';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    final backend = LocalReminderBackend();
    try {
      await backend.init();
      final granted = await backend.requestPermission();
      final plan = planReminders(
        DateTime.now(),
        ReminderContext(
          countryName: 'Canada',
          countryPercent: 62,
          nextCountryName: 'United States',
          skinName: 'Sunny',
          level: 4,
          coins: 1120,
          claimable: 2,
          eventEnd: DateTime.now().toUtc().add(const Duration(days: 2)),
          ownsSkin: (_) => false,
          priceOf: (s) => (s.cost / 2).round(),
        ),
      );
      final first = plan.first;
      final when = DateTime.now().add(const Duration(seconds: 25));
      await backend.cancelAll();
      await backend.schedule(Reminder(first.id, when, first.title, first.body));
      setState(() => status = 'permission: $granted\nscheduled for $when\n\n${first.title}\n${first.body}\n\nNow press HOME.');
    } catch (e) {
      setState(() => status = 'FAILED: $e');
    }
  }

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(status, textAlign: TextAlign.center))));
}
