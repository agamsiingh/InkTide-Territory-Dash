import 'package:flutter_test/flutter_test.dart';
import 'package:inktide/game/sim/skins.dart';
import 'package:inktide/services/progress_store.dart';
import 'package:inktide/services/reminders.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeBackend implements ReminderBackend {
  final List<Reminder> live = [];
  int cancels = 0, permissionAsks = 0;
  bool grant = true;
  @override
  Future<void> init() async {}
  @override
  Future<bool> requestPermission() async {
    permissionAsks++;
    return grant;
  }

  @override
  Future<void> cancelAll() async {
    cancels++;
    live.clear();
  }

  @override
  Future<void> schedule(Reminder r) async => live.add(r);
}

class ThrowingBackend implements ReminderBackend {
  @override
  Future<void> init() => throw StateError('no plugin');
  @override
  Future<bool> requestPermission() => throw StateError('no plugin');
  @override
  Future<void> cancelAll() => throw StateError('no plugin');
  @override
  Future<void> schedule(Reminder r) => throw StateError('no plugin');
}

ReminderContext ctx({
  double pct = 40,
  int claimable = 0,
  bool ownsDeal = false,
  DateTime? eventEnd,
}) =>
    ReminderContext(
      countryName: 'Canada',
      countryPercent: pct,
      nextCountryName: 'United States',
      skinName: 'Sunny',
      level: 4,
      coins: 321,
      claimable: claimable,
      eventEnd: eventEnd ?? DateTime.utc(2030),
      ownsSkin: (_) => ownsDeal,
      priceOf: (s) => (s.cost / 2).round(),
    );

bool awake(DateTime t) {
  final m = t.hour * 60 + t.minute;
  return m >= kAwakeFromMinutes && m <= kAwakeUntilMinutes;
}

Future<(ProgressStore, FakeBackend, ReminderService)> setup([Map<String, Object> prefs = const {}]) async {
  SharedPreferences.setMockInitialValues(Map<String, Object>.of(prefs));
  final store = await ProgressStore.open();
  final be = FakeBackend();
  return (store, be, ReminderService(store, be));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('planner', () {
    test('never pings at night, at any hour the player leaves', () {
      for (var hour = 0; hour < 24; hour++) {
        final now = DateTime(2026, 10, 19, hour, 17);
        for (final r in planReminders(now, ctx(eventEnd: now.add(const Duration(hours: 20)).toUtc()))) {
          expect(awake(r.when), isTrue, reason: 'left at $hour:17, got ${r.when} (${r.title})');
          expect(r.when.isAfter(now), isTrue);
        }
      }
    });

    test('at most six, in order, unique ids, none closer than 90 minutes', () {
      final now = DateTime(2026, 10, 19, 15);
      final plan = planReminders(now, ctx(eventEnd: now.add(const Duration(days: 3)).toUtc()));
      expect(plan.length, inInclusiveRange(3, kMaxReminders));
      expect(plan.map((r) => r.id).toSet().length, plan.length);
      for (var i = 1; i < plan.length; i++) {
        expect(plan[i].when.isAfter(plan[i - 1].when), isTrue);
        expect(plan[i].when.difference(plan[i - 1].when) >= const Duration(minutes: 90) || plan[i].id == 6, isTrue);
      }
      // Stops after a week: nothing beyond day 7.
      expect(plan.last.when.isBefore(now.add(const Duration(days: 8))), isTrue);
    });

    test('is deterministic for the same input', () {
      final now = DateTime(2026, 10, 19, 15);
      final a = planReminders(now, ctx()), b = planReminders(now, ctx());
      expect([for (final r in a) '${r.id}|${r.when}|${r.title}|${r.body}'],
          [for (final r in b) '${r.id}|${r.when}|${r.title}|${r.body}']);
    });

    test('unclaimed event rewards headline the first nudge', () {
      final now = DateTime(2026, 10, 19, 12);
      final plan = planReminders(now, ctx(claimable: 2));
      expect(plan.first.title, contains('🎁'));
      expect(plan.first.body, contains('2 Ink Festival rewards are ready'));
      expect(planReminders(now, ctx(claimable: 1)).first.body, contains('1 Ink Festival reward is ready'));
    });

    test("the skin-deal nudge names that day's real half-price skin and price", () {
      final now = DateTime(2026, 10, 19, 12);
      final deal = planReminders(now, ctx()).firstWhere((r) => r.id == 2);
      final skin = featuredSkin(deal.when);
      expect(deal.title, '🔥 ${skin.name} is 50% OFF today');
      expect(deal.body, contains('${(skin.cost / 2).round()} coins'));
      final owned = planReminders(now, ctx(ownsDeal: true)).firstWhere((r) => r.id == 2);
      expect(owned.title, isNot(contains('50% OFF')), reason: 'no deal pitch for a skin you own');
    });

    test('progress nudge quotes the real percentage', () {
      final now = DateTime(2026, 10, 19, 12);
      final r = planReminders(now, ctx(pct: 62.4)).firstWhere((r) => r.id == 3);
      expect(r.title, 'Canada is 62% filled 🌍');
      expect(r.body, contains('Only 38% to go'));
      expect(r.body, contains('United States'));
      final fresh = planReminders(now, ctx(pct: 0)).firstWhere((r) => r.id == 3);
      expect(fresh.title, contains('Level 4'));
    });

    test('event deadline reminder only appears while the event is ahead, and before it ends', () {
      final now = DateTime(2026, 10, 19, 12);
      final ends = now.add(const Duration(hours: 30));
      final plan = planReminders(now, ctx(eventEnd: ends.toUtc()));
      final ev = plan.where((r) => r.id == 6).toList();
      expect(ev, hasLength(1));
      expect(ev.single.when.isBefore(ends), isTrue);
      expect(ev.single.title, contains('Ink Festival'));
      // Ends in 20 minutes: too late to remind.
      final soon = planReminders(now, ctx(eventEnd: now.add(const Duration(minutes: 20)).toUtc()));
      expect(soon.where((r) => r.id == 6), isEmpty);
    });

    test('a deadline in the small hours moves to the evening before, not after the end', () {
      final now = DateTime(2026, 10, 19, 9);
      final ends = DateTime(2026, 10, 21, 2); // local 2 a.m.
      final ev = planReminders(now, ctx(eventEnd: ends.toUtc())).firstWhere((r) => r.id == 6);
      expect(ev.when, DateTime(2026, 10, 20, 21));
    });
  });

  group('service', () {
    test('schedules when the app goes to the background and clears when it returns', () async {
      final (store, be, svc) = await setup({'notifPermissionGranted': true});
      expect(store.notificationsEnabled, isTrue);
      await svc.onBackground(now: DateTime(2026, 10, 19, 15));
      expect(be.live, isNotEmpty);
      expect(be.live.length, svc.scheduled.length);
      await svc.onForeground();
      expect(be.live, isEmpty, reason: 'no reminder can fire while the player is playing');
      expect(svc.scheduled, isEmpty);
    });

    test('going to the background twice does not double up', () async {
      final (_, be, svc) = await setup({'notifPermissionGranted': true});
      await svc.onBackground(now: DateTime(2026, 10, 19, 15));
      final n = be.live.length;
      await svc.onBackground(now: DateTime(2026, 10, 19, 15, 5));
      expect(be.live.length, n);
    });

    test('nothing is scheduled without permission or when switched off', () async {
      final (_, be, svc) = await setup();
      await svc.onBackground(now: DateTime(2026, 10, 19, 15));
      expect(be.live, isEmpty, reason: 'permission never granted');
      final (_, be2, svc2) = await setup({'notifPermissionGranted': true, 'notificationsEnabled': false});
      await svc2.onBackground(now: DateTime(2026, 10, 19, 15));
      expect(be2.live, isEmpty);
    });

    test('permission is requested once, after the first match, and the answer is saved', () async {
      final (store, be, svc) = await setup();
      await svc.requestPermissionOnce();
      await svc.requestPermissionOnce();
      expect(be.permissionAsks, 1);
      expect(store.notifPermissionGranted, isTrue);
      final again = await ProgressStore.open();
      expect(again.notifPermissionAsked, isTrue);
      expect(again.notifPermissionGranted, isTrue);
      // A refusal is remembered and never re-asked.
      final (s2, be2, svc2) = await setup();
      be2.grant = false;
      await svc2.requestPermissionOnce();
      await svc2.requestPermissionOnce();
      expect(be2.permissionAsks, 1);
      expect(s2.notifPermissionGranted, isFalse);
    });

    test('the settings switch turns reminders off (cancelling) and back on (asking if needed)', () async {
      final (store, be, svc) = await setup({'notifPermissionGranted': true});
      await svc.onBackground(now: DateTime(2026, 10, 19, 15));
      expect(be.live, isNotEmpty);
      await svc.setEnabled(false);
      expect(store.notificationsEnabled, isFalse);
      expect(be.live, isEmpty);
      await svc.setEnabled(true);
      expect(store.notificationsEnabled, isTrue);
      expect(be.permissionAsks, 0, reason: 'already granted');
      final (s2, be2, svc2) = await setup({'notificationsEnabled': false});
      await svc2.setEnabled(true);
      expect(be2.permissionAsks, 1);
      expect(s2.notifPermissionGranted, isTrue);
    });

    test('a failing backend never throws into the game', () async {
      SharedPreferences.setMockInitialValues({'notifPermissionGranted': true});
      final store = await ProgressStore.open();
      final svc = ReminderService(store, ThrowingBackend());
      await svc.init();
      await svc.onBackground(now: DateTime(2026, 10, 19, 15));
      await svc.onForeground();
      await svc.requestPermissionOnce();
      await svc.setEnabled(false);
      await svc.setEnabled(true);
    });
  });
}
