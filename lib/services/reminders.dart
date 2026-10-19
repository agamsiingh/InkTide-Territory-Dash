import 'package:flutter/foundation.dart';

import '../game/event.dart';
import '../game/sim/skins.dart';
import '../game/world.dart';
import 'progress_store.dart';

/// One reminder to show at [when] (device local time).
class Reminder {
  const Reminder(this.id, this.when, this.title, this.body);
  final int id;
  final DateTime when;
  final String title;
  final String body;

  @override
  String toString() => 'Reminder($id, $when, $title)';
}

/// What the planner needs to know about the player (all plain data so the
/// plan is easy to test).
class ReminderContext {
  const ReminderContext({
    required this.countryName,
    required this.countryPercent,
    required this.nextCountryName,
    required this.skinName,
    required this.level,
    required this.coins,
    required this.claimable,
    required this.eventEnd,
    required this.ownsSkin,
    required this.priceOf,
  });

  final String countryName;
  final double countryPercent;
  final String? nextCountryName;
  final String skinName;
  final int level;
  final int coins;

  /// Event milestones reached but not yet claimed.
  final int claimable;

  /// End of the running event (UTC).
  final DateTime eventEnd;
  final bool Function(Skin) ownsSkin;
  final int Function(Skin) priceOf;

  factory ReminderContext.fromStore(ProgressStore s) {
    final cur = s.currentCountry;
    final ev = s.currentEvent;
    return ReminderContext(
      countryName: kCountries[cur].name,
      countryPercent: s.countryProgress[cur],
      nextCountryName: cur + 1 < kCountries.length ? kCountries[cur + 1].name : null,
      skinName: skinById(s.selectedSkin).name,
      level: s.level,
      coins: s.coins,
      claimable: [for (var i = 0; i < kMilestones.length; i++) if (s.canClaim(i)) i].length,
      eventEnd: ev.end,
      ownsSkin: s.isUnlocked,
      priceOf: (k) => (k.cost / 2).round(),
    );
  }
}

/// Reminders go out between these local times (no 3 a.m. pings).
const int kAwakeFromMinutes = 10 * 60;
const int kAwakeUntilMinutes = 21 * 60 + 30;

/// Never nag for longer than this after the last visit.
const int kMaxReminders = 6;

/// Moves [t] into the awake window. Night-time slots shift to the next
/// morning, or (for deadlines, [earlier]) back to the previous evening.
DateTime intoAwakeHours(DateTime t, {bool earlier = false}) {
  final day = DateTime(t.year, t.month, t.day);
  final mins = t.hour * 60 + t.minute;
  if (mins < kAwakeFromMinutes) {
    return earlier ? DateTime(day.year, day.month, day.day - 1, 21) : DateTime(day.year, day.month, day.day, 10, 30);
  }
  if (mins > kAwakeUntilMinutes) {
    return earlier ? DateTime(day.year, day.month, day.day, 21) : DateTime(day.year, day.month, day.day + 1, 10, 30);
  }
  return t;
}

T _pick<T>(List<T> items, int seed) => items[seed.abs() % items.length];

String _rival(int seed) => _pick(kBotNames, seed * 7 + 3);

/// Builds the reminder schedule for a player who has just left the app at
/// [now] (device local time). Deterministic for the same inputs.
///
/// Tone is playful marketing, but nothing is made up: skin deals, event end
/// times and progress numbers come from the real game state.
List<Reminder> planReminders(DateTime now, ReminderContext c) {
  final out = <Reminder>[];
  int dayKey(DateTime t) => t.year * 400 + t.month * 31 + t.day;

  // 1. A few hours later: come back and play.
  final t1 = intoAwakeHours(now.add(const Duration(hours: 4)));
  final k1 = dayKey(t1);
  if (c.claimable > 0) {
    out.add(Reminder(
      1,
      t1,
      _pick(['🎁 Free loot is waiting!', '🎁 Your reward is getting cold'], k1),
      '${c.claimable} Ink Festival ${c.claimable == 1 ? 'reward is' : 'rewards are'} ready to claim. Zero effort, all loot.',
    ));
  } else {
    out.add(Reminder(
      1,
      t1,
      _pick(['Your island misses you 🥺', 'Psst… your rivals are painting your map 🎨', 'Territory emergency! 🚨'], k1),
      '${_rival(k1)} is plotting to steal your ${c.countryName} land. Come back and defend it!',
    ));
  }

  // 2. Tomorrow evening: that day's half-price skin.
  final t2 = DateTime(now.year, now.month, now.day + 1, 19);
  final deal = featuredSkin(t2);
  if (!c.ownsSkin(deal)) {
    out.add(Reminder(
      2,
      t2,
      '🔥 ${deal.name} is 50% OFF today',
      'Cute alert! Grab ${deal.name} for ${c.priceOf(deal)} coins - today only.',
    ));
  } else {
    out.add(Reminder(
      2,
      t2,
      '🎨 New deal in the shop',
      'Check today\'s half-price skin and make your collection cuter.',
    ));
  }

  // 3. Two days out: country progress, or just the level.
  final t3 = DateTime(now.year, now.month, now.day + 2, 12, 30);
  final pct = c.countryPercent;
  if (pct >= 1 && pct < 100) {
    final left = (100 - pct).ceil();
    final next = c.nextCountryName;
    out.add(Reminder(
      3,
      t3,
      '${c.countryName} is ${pct.floor()}% filled 🌍',
      next == null ? 'Only $left% to go. So close!' : 'Only $left% to go. Finish it and unlock $next!',
    ));
  } else {
    out.add(Reminder(
      3,
      t3,
      'Level ${c.level} is waiting 🎯',
      '${_rival(dayKey(t3))} says you can\'t beat it. Prove them wrong?',
    ));
  }

  // 4. Four days out: miss-you.
  final t4 = DateTime(now.year, now.month, now.day + 4, 18, 30);
  out.add(Reminder(
    4,
    t4,
    'Knock knock… it\'s your ${c.skinName} 🧊',
    'It is getting dusty in there. One quick match?',
  ));

  // 5. A week out: last nudge.
  final t5 = DateTime(now.year, now.month, now.day + 7, 18, 30);
  out.add(Reminder(
    5,
    t5,
    'We saved your seat 💛',
    'The rivals got sharper while you were away. ${c.coins} coins are waiting for you.',
  ));

  // 6. Event deadline: three hours before it ends (only if it is still ahead).
  final end = c.eventEnd.toLocal();
  final t6 = intoAwakeHours(end.subtract(const Duration(hours: 3)), earlier: true);
  if (t6.isAfter(now.add(const Duration(hours: 1))) && t6.isBefore(end)) {
    out.add(Reminder(
      6,
      t6,
      '⏰ Ink Festival ends soon!',
      c.claimable > 0
          ? '${c.claimable} reward${c.claimable == 1 ? '' : 's'} still unclaimed. Grab ${c.claimable == 1 ? 'it' : 'them'} before it\'s gone!'
          : 'Collect ink drops and claim your rewards before the event ends.',
    ));
  }

  out.sort((a, b) => a.when.compareTo(b.when));
  // No two reminders within 90 minutes of each other (keep the earlier one,
  // except the event deadline, which always wins).
  final kept = <Reminder>[];
  for (final r in out) {
    final clash = kept.isNotEmpty && r.when.difference(kept.last.when) < const Duration(minutes: 90);
    if (clash && r.id != 6) continue;
    if (clash && r.id == 6) kept.removeLast();
    kept.add(r);
  }
  return kept.where((r) => r.when.isAfter(now)).take(kMaxReminders).toList();
}

/// Platform side: schedule / cancel. Faked in tests.
abstract class ReminderBackend {
  Future<void> init();

  /// Asks the user for notification permission. Returns true if granted.
  Future<bool> requestPermission();
  Future<void> cancelAll();
  Future<void> schedule(Reminder r);
}

/// Keeps reminders in sync with whether the player is in the app: they are
/// scheduled when the app goes to the background and cancelled the moment the
/// player comes back, so they only ever fire while the game is not being played.
class ReminderService {
  ReminderService(this.store, this.backend);

  final ProgressStore store;
  final ReminderBackend backend;

  /// Reminders currently scheduled (for tests / diagnostics).
  final List<Reminder> scheduled = [];

  Future<void> init() async {
    try {
      await backend.init();
      await backend.cancelAll();
    } catch (e) {
      debugPrint('reminders init failed: $e');
    }
  }

  /// Player left the app: line up the reminders.
  Future<void> onBackground({DateTime? now}) async {
    try {
      await backend.cancelAll();
      scheduled.clear();
      if (!store.notificationsEnabled || !store.notifPermissionGranted) return;
      final plan = planReminders(now ?? DateTime.now(), ReminderContext.fromStore(store));
      for (final r in plan) {
        await backend.schedule(r);
        scheduled.add(r);
      }
    } catch (e) {
      debugPrint('reminders schedule failed: $e');
    }
  }

  /// Player is back: nothing should ping them now.
  Future<void> onForeground() async {
    try {
      scheduled.clear();
      await backend.cancelAll();
    } catch (e) {
      debugPrint('reminders cancel failed: $e');
    }
  }

  /// Asks for permission once, at a friendly moment (after the first match).
  Future<void> requestPermissionOnce() async {
    if (store.notifPermissionAsked || !store.notificationsEnabled) return;
    await store.update((s) => s.notifPermissionAsked = true);
    final granted = await _ask();
    await store.update((s) => s.notifPermissionGranted = granted);
  }

  Future<bool> _ask() async {
    try {
      return await backend.requestPermission();
    } catch (e) {
      debugPrint('notification permission failed: $e');
      return false;
    }
  }

  /// Settings switch. Turning on asks for permission if it was never granted.
  Future<void> setEnabled(bool on) async {
    await store.update((s) => s.notificationsEnabled = on);
    if (!on) {
      scheduled.clear();
      try {
        await backend.cancelAll();
      } catch (e) {
        debugPrint('reminders cancel failed: $e');
      }
      return;
    }
    if (!store.notifPermissionGranted) {
      final granted = await _ask();
      await store.update((s) {
        s.notifPermissionAsked = true;
        s.notifPermissionGranted = granted;
      });
    }
  }
}

/// Does nothing (tests, unsupported platforms).
class NoopReminderBackend implements ReminderBackend {
  @override
  Future<void> init() async {}
  @override
  Future<bool> requestPermission() async => false;
  @override
  Future<void> cancelAll() async {}
  @override
  Future<void> schedule(Reminder r) async {}
}
