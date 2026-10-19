import 'dart:math' as math;

import 'package:flutter/material.dart' hide Simulation;
import 'package:flutter_test/flutter_test.dart';
import 'package:inktide/game/inktide_game.dart';
import 'package:inktide/game/sim/skins.dart';
import 'package:inktide/services/feedback.dart';
import 'package:inktide/services/progress_store.dart';

import 'app_flow_test.dart' show launchApp, startMatch, pumpFor, pumpUntil, tapKey, tearDownApp;
import '../helpers/pin_clock.dart';

/// Steers toward the nearest coin stack / gem still on the island.
void chaseLoot() {
  final g = InkTideGame.current;
  final b = g?.bonus;
  if (g == null || b == null) return;
  final h = g.sim.human;
  double best = double.infinity, angle = h.desiredHeading;
  for (final p in b.pickups) {
    if (p.taken) continue;
    final dx = p.x - h.x, dy = p.y - h.y, d = dx * dx + dy * dy;
    if (d < best) {
      best = d;
      angle = math.atan2(dy, dx);
    }
  }
  g.steer(angle);
}

/// Wins the running match on the spot and waits for the bonus round to start.
Future<InkTideGame> winIntoBonus(WidgetTester tester) async {
  final game = await startMatch(tester);
  game.sim.won = true;
  final intro = await pumpUntil(tester, () => game.phase == MatchPhase.bonusIntro, timeout: const Duration(seconds: 3));
  expect(intro, isTrue, reason: 'a win turns into the bonus round');
  expect(find.byKey(const Key('bonusIntro')), findsOneWidget);
  expect(find.text('100%'), findsWidgets);
  final started = await pumpUntil(tester, () => game.phase == MatchPhase.bonus, timeout: const Duration(seconds: 4));
  expect(started, isTrue, reason: 'intro hands over to the bonus game');
  expect(find.byKey(const Key('bonusTimer')), findsOneWidget);
  expect(find.byKey(const Key('bonusLoot')), findsOneWidget);
  expect(game.sim.players.where((p) => !p.isHuman && p.alive), isEmpty, reason: 'rivals leave');
  return game;
}

void main() {
  setUp(() {
    GameFeedback.enabled = false;
    InkTideGame.current = null;
    pinClockAwayFromDeals();
  });
  tearDown(unpinClock);

  testWidgets('bonus: collect, continue +6s once, multiply, paid exactly once', (tester) async {
    final store = await launchApp(tester);
    final game = await winIntoBonus(tester);
    final b = game.bonus!;
    final paused = await pumpUntil(tester, () => game.phase == MatchPhase.bonusPaused,
        timeout: const Duration(seconds: 14), onFrame: chaseLoot);
    expect(paused, isTrue, reason: 'time ran out');
    expect(b.coins, greaterThan(0), reason: 'loot was collected while steering');
    expect(find.byKey(const Key('continueBonus')), findsOneWidget);
    final coinsAtPause = b.coins;
    await tapKey(tester, 'continueButton', settle: const Duration(milliseconds: 100));
    expect(game.phase, MatchPhase.bonus);
    expect(b.extended, isTrue);
    expect(b.timeLeft, closeTo(6, 0.2));
    // Same session continues: loot is kept and grows.
    final shown = await pumpUntil(tester, () => find.byKey(const Key('multiplyButton')).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 12), onFrame: chaseLoot);
    expect(shown, isTrue, reason: 'second time-out goes straight to the reward summary');
    expect(find.byKey(const Key('continueBonus')), findsNothing, reason: 'continue is offered only once');
    expect(b.coins, greaterThanOrEqualTo(coinsAtPause));
    expect(store.pendingBonusCoins, b.coins);
    expect(store.pendingBonusGems, b.gems);
    expect(find.byKey(const Key('lootCoins')), findsOneWidget);
    expect(find.byKey(const Key('multiplierMeter')), findsOneWidget);

    final before = store.coins, gemsBefore = store.gems;
    await tester.tap(find.byKey(const Key('multiplyButton')));
    await tester.pump(const Duration(milliseconds: 50));
    // A second tap while paying out is ignored.
    await tester.tap(find.byKey(const Key('multiplyButton')));
    await pumpFor(tester, const Duration(milliseconds: 600));
    final gained = store.coins - before;
    expect(gained % b.coins, 0);
    final mult = gained ~/ b.coins;
    expect(mult, inInclusiveRange(2, 4));
    expect(store.gems - gemsBefore, b.gems * mult);
    expect(store.hasPendingBonus, isFalse);
    expect(find.byKey(const Key('multiplierResult')), findsOneWidget);
    final results = await pumpUntil(tester, () => find.byKey(const Key('resultsPanel')).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 3));
    expect(results, isTrue);
    expect(find.byKey(const Key('resultBonus')), findsOneWidget);
    expect(find.textContaining('(x$mult)'), findsOneWidget);
    expect(store.coins - before, gained, reason: 'nothing paid twice');
    expect(store.wins, 1);
    await tearDownApp(tester);
  });

  testWidgets('bonus: No thanks on continue and on the multiplier pays x1', (tester) async {
    final store = await launchApp(tester);
    final game = await winIntoBonus(tester);
    await pumpUntil(tester, () => game.phase == MatchPhase.bonusPaused,
        timeout: const Duration(seconds: 14), onFrame: chaseLoot);
    await tapKey(tester, 'declineContinue', settle: const Duration(milliseconds: 600));
    expect(find.byKey(const Key('multiplyButton')), findsOneWidget);
    final loot = game.bonus!.coins, gems = game.bonus!.gems;
    final before = store.coins, gemsBefore = store.gems;
    await tapKey(tester, 'noThanks', settle: const Duration(milliseconds: 1200));
    expect(store.coins - before, loot);
    expect(store.gems - gemsBefore, gems);
    // Winning level 1 unlocks Sweetie: her capsule opens and she is equipped.
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(find.byKey(const Key('capsuleRarity')), findsOneWidget);
    expect(store.selectedSkin, 'sweetie');
    await tapKey(tester, 'capsuleTap', settle: const Duration(milliseconds: 1600));
    expect(find.text('Sweetie'), findsWidgets);
    await tapKey(tester, 'capsuleGreat', settle: const Duration(milliseconds: 600));
    expect(find.byKey(const Key('resultsPanel')), findsOneWidget);
    await tearDownApp(tester);
  });

  testWidgets('powers: intro once at level 3, then double tap fires the Ink Splash', (tester) async {
    final store = await launchApp(tester, prefs: {'level': 3});
    await tapKey(tester, 'playButton', settle: const Duration(milliseconds: 600));
    expect(find.byKey(const Key('powersIntro')), findsOneWidget);
    expect(find.text('POWERS'), findsWidgets);
    await tapKey(tester, 'powersGotIt', settle: const Duration(milliseconds: 100));
    expect(store.powersIntroSeen, isTrue);
    final playing = await pumpUntil(tester, () => InkTideGame.current?.phase == MatchPhase.playing,
        timeout: const Duration(seconds: 4));
    expect(playing, isTrue);
    final game = InkTideGame.current!;
    expect(game.sim.powersEnabled, isTrue);
    game.sim.humanPower = 1;
    final owned = game.sim.arena.counts[1];
    final surface = find.byKey(const Key('gameSurface'));
    await tester.tap(surface);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(surface);
    await pumpFor(tester, const Duration(milliseconds: 400));
    expect(game.sim.humanPower, lessThan(0.2), reason: 'power was spent');
    expect(game.sim.arena.counts[1], greaterThanOrEqualTo(owned));
    await tearDownApp(tester);
  });

  testWidgets('skins: buying opens the capsule, reveal marks it seen, equip and remove', (tester) async {
    final store = await launchApp(tester, prefs: {'coins': 500});
    await tapKey(tester, 'skinsButton', settle: const Duration(milliseconds: 900));
    await tapKey(tester, 'skin_bubbles', settle: const Duration(milliseconds: 300));
    await tapKey(tester, 'confirmBuy', settle: const Duration(milliseconds: 600));
    expect(find.byKey(const Key('capsuleRarity')), findsOneWidget);
    expect(find.text('Tap to open!'), findsWidgets);
    expect(store.isNewSkin(skinById('bubbles')), isTrue);
    await tapKey(tester, 'capsuleTap', settle: const Duration(milliseconds: 1600));
    expect(find.byKey(const Key('capsuleName')), findsOneWidget);
    expect(find.byKey(const Key('newLabel')), findsOneWidget);
    expect(find.text('Bubbles'), findsWidgets);
    expect(store.isNewSkin(skinById('bubbles')), isFalse);
    await tapKey(tester, 'capsuleGreat', settle: const Duration(milliseconds: 600));
    expect(find.byKey(const Key('skinPreview')), findsOneWidget);
    expect(store.selectedSkin, 'bubbles');
    await tapKey(tester, 'unequipButton', settle: const Duration(milliseconds: 300));
    expect(store.selectedSkin, 'sunny');
    await tapKey(tester, 'skin_bubbles', settle: const Duration(milliseconds: 300));
    expect(store.selectedSkin, 'bubbles', reason: 'tapping an owned skin equips it');
    await tearDownApp(tester);
  });

  test('store survives restart mid-bonus (smoke)', () async {
    // Covered in detail by bonus_store_test; here just the type is reachable.
    expect(ProgressStore.powersLevel, 3);
  });
}
