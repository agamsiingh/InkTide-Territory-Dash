import 'dart:math' as math;

import 'package:flutter/material.dart' hide Simulation;
import 'package:flutter_test/flutter_test.dart';
import 'package:inktide/app.dart';
import 'package:inktide/game/inktide_game.dart';
import 'package:inktide/game/sim/levels.dart';
import 'package:inktide/game/sim/skins.dart';
import 'package:inktide/game/sim/simulation.dart';
import 'package:inktide/services/feedback.dart';
import 'package:inktide/services/progress_store.dart';
import 'package:inktide/services/reminders.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../helpers/pin_clock.dart';

// NOTE: the menu has repeating animations (AnimationController.repeat), so
// pumpAndSettle() would time out. Every wait below uses fixed pump steps.

const _frame = Duration(milliseconds: 50);

Future<void> pumpFor(WidgetTester tester, Duration total) async {
  var elapsed = Duration.zero;
  while (elapsed < total) {
    await tester.pump(_frame);
    elapsed += _frame;
  }
}

/// Pumps frames until [cond] is true or [timeout] (of fake time) elapses.
/// [onFrame] runs before every frame (used for steering).
Future<bool> pumpUntil(
  WidgetTester tester,
  bool Function() cond, {
  Duration timeout = const Duration(seconds: 10),
  void Function()? onFrame,
}) async {
  var elapsed = Duration.zero;
  while (!cond() && elapsed < timeout) {
    onFrame?.call();
    await tester.pump(_frame);
    elapsed += _frame;
  }
  return cond();
}

void usePhoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

Future<ProgressStore> launchApp(WidgetTester tester, {Map<String, Object> prefs = const {}}) async {
  usePhoneSize(tester);
  SharedPreferences.setMockInitialValues(<String, Object>{'tutorialSeen': true, ...prefs});
  final store = await ProgressStore.open();
  await tester.pumpWidget(InkTideApp(store: store, skipSplash: true, reminderBackend: NoopReminderBackend()));
  await pumpFor(tester, const Duration(milliseconds: 800));
  expect(find.byKey(const Key('playButton')), findsOneWidget);
  return store;
}

/// Removes the app so timers / tickers are disposed before the test ends.
Future<void> tearDownApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(_frame);
}

Future<void> tapKey(WidgetTester tester, String key, {Duration settle = const Duration(milliseconds: 400)}) async {
  final f = find.byKey(Key(key));
  expect(f, findsOneWidget, reason: 'expected one widget with key $key');
  await tester.tap(f);
  await pumpFor(tester, settle);
}

/// Heading that brings the human toward the arena centre (keeps it away from
/// the border during short waits). Keeps the current heading near the centre
/// to avoid circling over its own trail.
double safeHeading(Simulation sim) {
  final h = sim.human;
  final cx = sim.arena.width / 2, cy = sim.arena.height / 2;
  final dx = cx - h.x, dy = cy - h.y;
  if (dx * dx + dy * dy < 25) return h.desiredHeading;
  return math.atan2(dy, dx);
}

double nearestBorderHeading(Simulation sim) {
  final h = sim.human;
  final w = sim.arena.width.toDouble(), hh = sim.arena.height.toDouble();
  final options = <(double, double)>[
    (h.x, math.pi),
    (w - h.x, 0.0),
    (h.y, -math.pi / 2),
    (hh - h.y, math.pi / 2),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  return options.first.$2;
}

void keepSafe() {
  final g = InkTideGame.current;
  if (g != null && g.isLoaded) g.steer(safeHeading(g.sim));
}

/// From the menu: taps PLAY and waits for the countdown to finish.
Future<InkTideGame> startMatch(WidgetTester tester) async {
  await tapKey(tester, 'playButton', settle: const Duration(milliseconds: 500));
  expect(find.byKey(const Key('pauseButton')), findsOneWidget);
  final loaded = await pumpUntil(tester, () => InkTideGame.current?.isLoaded ?? false,
      timeout: const Duration(seconds: 3));
  expect(loaded, isTrue, reason: 'InkTideGame should load');
  final playing = await pumpUntil(
    tester,
    () => InkTideGame.current!.phase == MatchPhase.playing,
    timeout: const Duration(seconds: 4),
    onFrame: keepSafe,
  );
  expect(playing, isTrue, reason: 'countdown should end with GO');
  // Let the "GO!" overlay disappear (it is removed 650 ms after GO).
  await pumpUntil(tester, () => false, timeout: const Duration(milliseconds: 800), onFrame: keepSafe);
  return InkTideGame.current!;
}

void main() {
  setUp(() {
    GameFeedback.enabled = false;
    InkTideGame.current = null;
    pinClockAwayFromDeals();
  });
  tearDown(unpinClock);

  group('menu & screens', () {
    testWidgets('menu shows play, skins, how-to and settings', (tester) async {
      final store = await launchApp(tester);
      expect(find.byKey(const Key('skinsButton')), findsOneWidget);
      expect(find.byKey(const Key('howToButton')), findsOneWidget);
      expect(find.byKey(const Key('settingsButton')), findsOneWidget);
      expect(find.text('LEVEL ${store.level}'), findsOneWidget);
      await tearDownApp(tester);
    });

    testWidgets('settings: toggles, speed selector and back', (tester) async {
      final store = await launchApp(tester);
      await tapKey(tester, 'settingsButton');
      expect(find.byKey(const Key('soundToggle')), findsOneWidget);

      expect(store.sound, isTrue);
      await tapKey(tester, 'soundToggle', settle: const Duration(milliseconds: 200));
      expect(store.sound, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('sound'), isFalse);

      await tapKey(tester, 'musicToggle', settle: const Duration(milliseconds: 200));
      expect(store.music, isFalse);
      await tapKey(tester, 'hapticsToggle', settle: const Duration(milliseconds: 200));
      expect(store.haptics, isFalse);
      await tapKey(tester, 'fpsToggle', settle: const Duration(milliseconds: 200));
      expect(store.showFps, isTrue);

      // Toggle sound back on.
      await tapKey(tester, 'soundToggle', settle: const Duration(milliseconds: 200));
      expect(store.sound, isTrue);

      await tester.ensureVisible(find.byKey(const Key('speedSelector')));
      await pumpFor(tester, const Duration(milliseconds: 200));
      await tester.tap(find.text('Turbo'));
      await pumpFor(tester, const Duration(milliseconds: 200));
      expect(store.speed, SpeedSetting.fast);
      await tester.tap(find.text('Chill'));
      await pumpFor(tester, const Duration(milliseconds: 200));
      expect(store.speed, SpeedSetting.slow);

      // The back button may have been scrolled out of the lazy ListView's cache.
      await tester.scrollUntilVisible(find.byKey(const Key('backButton')), -200,
          scrollable: find.byType(Scrollable).first);
      await pumpFor(tester, const Duration(milliseconds: 100));
      await tapKey(tester, 'backButton');
      expect(find.byKey(const Key('soundToggle')), findsNothing);
      expect(find.byKey(const Key('playButton')), findsOneWidget);
      await tearDownApp(tester);
    });

    testWidgets('settings: reset progress after confirmation', (tester) async {
      final store = await launchApp(tester, prefs: {'coins': 400, 'level': 4});
      expect(store.level, 4);
      await tapKey(tester, 'settingsButton');
      await tester.scrollUntilVisible(find.byKey(const Key('resetProgress')), 200,
          scrollable: find.byType(Scrollable).first);
      await pumpFor(tester, const Duration(milliseconds: 200));
      await tapKey(tester, 'resetProgress');
      expect(find.byKey(const Key('confirmReset')), findsOneWidget);
      await tapKey(tester, 'confirmReset');
      expect(store.level, 1);
      expect(store.coins, 0);
      await tearDownApp(tester);
    });

    testWidgets('skins: locked skins show a SnackBar', (tester) async {
      final store = await launchApp(tester);
      expect(store.coins, 0);
      await tapKey(tester, 'skinsButton');
      expect(find.byKey(const Key('skin_bubbles')), findsOneWidget);

      await tester.tap(find.byKey(const Key('skin_bubbles')));
      await pumpFor(tester, const Duration(milliseconds: 300));
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('You need 120 more coins.'), findsOneWidget);
      expect(store.selectedSkin, 'sunny');

      await tester.ensureVisible(find.byKey(const Key('skin_grape')));
      await pumpFor(tester, const Duration(milliseconds: 100));
      await tester.tap(find.byKey(const Key('skin_grape')));
      await pumpFor(tester, const Duration(milliseconds: 600));
      expect(find.text('Reach level 3 to unlock Grape.'), findsOneWidget);

      await tapKey(tester, 'backButton');
      expect(find.byKey(const Key('playButton')), findsOneWidget);
      await tearDownApp(tester);
    });

    testWidgets('skins: affordable skin can be bought', (tester) async {
      final store = await launchApp(tester, prefs: {'coins': 500});
      await tapKey(tester, 'skinsButton');
      await tester.tap(find.byKey(const Key('skin_bubbles')));
      await pumpFor(tester, const Duration(milliseconds: 400));
      expect(find.byKey(const Key('confirmBuy')), findsOneWidget);
      await tapKey(tester, 'confirmBuy');
      expect(store.coins, 380);
      expect(store.selectedSkin, 'bubbles');
      expect(store.ownedSkins, contains('bubbles'));
      await tearDownApp(tester);
    });

    testWidgets('how-to dialog steps through the tutorial and closes', (tester) async {
      await launchApp(tester);
      await tapKey(tester, 'howToButton');
      expect(find.byKey(const Key('tutorialNext')), findsOneWidget);
      expect(find.text('Steer'), findsOneWidget);
      for (var i = 0; i < 3; i++) {
        await tapKey(tester, 'tutorialNext');
      }
      expect(find.text('Stay safe'), findsOneWidget);
      expect(find.text("LET'S GO!"), findsOneWidget);
      await tapKey(tester, 'tutorialNext');
      expect(find.byKey(const Key('tutorialNext')), findsNothing);
      expect(find.byKey(const Key('playButton')), findsOneWidget);
      await tearDownApp(tester);
    });
  });

  group('progression screens', () {
    testWidgets('awards screen lists achievements with completed state', (tester) async {
      await launchApp(tester, prefs: {'achievements': <String>['first_game'], 'gamesPlayed': 1});
      await tapKey(tester, 'awardsButton', settle: const Duration(milliseconds: 700));
      expect(find.text('AWARDS'), findsOneWidget);
      expect(find.byKey(const Key('achievement_first_game')), findsOneWidget);
      expect(find.text('DONE'), findsOneWidget);
      await tapKey(tester, 'backButton');
      expect(find.byKey(const Key('playButton')), findsOneWidget);
      await tearDownApp(tester);
    });

    testWidgets('menu shows the rank bar from stored XP', (tester) async {
      await launchApp(tester, prefs: {'xp': 130});
      expect(find.byKey(const Key('rankBadge')), findsOneWidget);
      expect(find.text('2'), findsWidgets);
      expect(find.text('10 / 200 XP'), findsOneWidget);
      await tearDownApp(tester);
    });

    testWidgets('equipping a skin changes the in-game character', (tester) async {
      final store = await launchApp(tester, prefs: {'ownedSkins': <String>['sunny', 'pebble']});
      await tapKey(tester, 'skinsButton', settle: const Duration(milliseconds: 700));
      // The grid builds lazily, so scroll the card into existence first.
      await tester.scrollUntilVisible(find.byKey(const Key('skin_pebble')), 250,
          scrollable: find.byType(Scrollable).first);
      await pumpFor(tester, const Duration(milliseconds: 100));
      await tester.tap(find.byKey(const Key('skin_pebble')));
      await pumpFor(tester, const Duration(milliseconds: 300));
      expect(store.selectedSkin, 'pebble');
      expect(find.byKey(const Key('previewStatus')), findsOneWidget);
      await tapKey(tester, 'backButton');
      final game = await startMatch(tester);
      expect(game.sim.human.skin.id, 'pebble');
      expect(game.sim.human.skin.shape, BodyShape.round);
      expect(game.sim.players.skip(1).any((p) => p.skin.id == 'pebble'), isFalse,
          reason: 'bots never wear the player skin');
      await tearDownApp(tester);
    });
  });

  group('game screen', () {
    testWidgets('play opens the game; countdown starts the match', (tester) async {
      final store = await launchApp(tester);
      final game = await startMatch(tester);
      expect(game.phase, MatchPhase.playing);
      expect(game.config.level, store.level);
      expect(find.byKey(const Key('gameSurface')), findsOneWidget);
      expect(find.byKey(const Key('percentLabel')), findsOneWidget);
      final t0 = game.sim.time;
      await pumpUntil(tester, () => false, timeout: const Duration(milliseconds: 500), onFrame: keepSafe);
      expect(game.sim.time, greaterThan(t0), reason: 'simulation advances while playing');
      await tearDownApp(tester);
    });

    testWidgets('first match shows the tutorial before the countdown', (tester) async {
      final store = await launchApp(tester, prefs: {'tutorialSeen': false});
      await tapKey(tester, 'playButton', settle: const Duration(milliseconds: 500));
      expect(find.byKey(const Key('tutorialNext')), findsOneWidget);
      for (var i = 0; i < 4; i++) {
        await tapKey(tester, 'tutorialNext', settle: const Duration(milliseconds: 300));
      }
      expect(store.tutorialSeen, isTrue);
      expect(find.byKey(const Key('tutorialNext')), findsNothing);
      final playing = await pumpUntil(
        tester,
        () => InkTideGame.current?.phase == MatchPhase.playing,
        timeout: const Duration(seconds: 4),
        onFrame: keepSafe,
      );
      expect(playing, isTrue);
      await tearDownApp(tester);
    });

    testWidgets('pause and resume', (tester) async {
      await launchApp(tester);
      final game = await startMatch(tester);
      expect(game.phase, MatchPhase.playing, reason: 'human should still be alive');
      await tapKey(tester, 'pauseButton');
      expect(find.byKey(const Key('resumeButton')), findsOneWidget);
      expect(find.byKey(const Key('restartButton')), findsOneWidget);
      expect(find.byKey(const Key('quitButton')), findsOneWidget);
      expect(game.paused, isTrue);
      final t = game.sim.time;
      await pumpFor(tester, const Duration(milliseconds: 500));
      expect(game.sim.time, t, reason: 'no simulation while paused');

      await tapKey(tester, 'resumeButton');
      expect(find.byKey(const Key('resumeButton')), findsNothing);
      expect(game.paused, isFalse);
      await pumpUntil(tester, () => false, timeout: const Duration(milliseconds: 300), onFrame: keepSafe);
      expect(game.sim.time, greaterThan(t));
      await tearDownApp(tester);
    });

    testWidgets('restart from pause creates a new game', (tester) async {
      await launchApp(tester);
      final first = await startMatch(tester);
      await tapKey(tester, 'pauseButton');
      await tapKey(tester, 'restartButton', settle: const Duration(milliseconds: 600));
      final replaced = await pumpUntil(
        tester,
        () => InkTideGame.current != null && !identical(InkTideGame.current, first),
        timeout: const Duration(seconds: 3),
      );
      expect(replaced, isTrue);
      expect(find.byKey(const Key('pauseButton')), findsOneWidget);
      expect(find.byKey(const Key('resumeButton')), findsNothing);
      expect(InkTideGame.current!.phase, MatchPhase.countdown);
      await tearDownApp(tester);
    });

    testWidgets('quit from pause returns to the menu', (tester) async {
      await launchApp(tester);
      await startMatch(tester);
      await tapKey(tester, 'pauseButton');
      await tapKey(tester, 'quitButton', settle: const Duration(milliseconds: 600));
      expect(find.byKey(const Key('pauseButton')), findsNothing);
      expect(find.byKey(const Key('playButton')), findsOneWidget);
      await tearDownApp(tester);
    });

    testWidgets('dying shows results; retry starts a new game', (tester) async {
      final store = await launchApp(tester);
      final game = await startMatch(tester);
      final shown = await pumpUntil(
        tester,
        () => find.byKey(const Key('resultsPanel')).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 40),
        onFrame: () {
          final g = InkTideGame.current;
          if (g == null || g.phase != MatchPhase.playing) return;
          final h = g.sim.human;
          // Walls and our own trail no longer kill, so head out and let a
          // rival cut the trail.
          if (h.trailCells.length > 6) {
            g.sim.debugKill(h, 2, DeathCause.trailCut);
          } else {
            g.steer(nearestBorderHeading(g.sim));
          }
        },
      );
      expect(shown, isTrue, reason: 'results panel should appear after dying');
      expect(game.sim.humanDead, isTrue);
      expect(game.phase, MatchPhase.over);
      expect(store.gamesPlayed, 1);
      expect(store.wins, 0);
      expect(find.text('SPLAT!'), findsOneWidget);
      expect(find.byKey(const Key('retryButton')), findsOneWidget);
      expect(find.byKey(const Key('nextLevelButton')), findsNothing);

      await pumpFor(tester, const Duration(milliseconds: 400));
      await tester.ensureVisible(find.byKey(const Key('retryButton')));
      await pumpFor(tester, const Duration(milliseconds: 100));
      await tapKey(tester, 'retryButton', settle: const Duration(milliseconds: 600));
      final replaced = await pumpUntil(
        tester,
        () => InkTideGame.current != null && !identical(InkTideGame.current, game),
        timeout: const Duration(seconds: 3),
      );
      expect(replaced, isTrue);
      expect(find.byKey(const Key('resultsPanel')), findsNothing);
      expect(find.byKey(const Key('pauseButton')), findsOneWidget);
      await tearDownApp(tester);
    });
  });
}
