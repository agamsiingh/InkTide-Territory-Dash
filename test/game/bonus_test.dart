import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:inktide/game/bonus.dart';
import 'package:inktide/game/sim/levels.dart';
import 'package:inktide/game/sim/simulation.dart';

Simulation homeSim({int bots = 0}) {
  final sim = Simulation(
      config: LevelConfig(level: 1, arenaSize: 40, bots: bots, targetPercent: 99, botSkill: 0.5), seed: 5);
  sim.arena.reset();
  sim.arena.claimDisc(20.5, 20.5, 6, sim.human.id);
  sim.debugPlace(sim.human, 20.5, 20.5, 0);
  sim.drainEvents();
  return sim;
}

void main() {
  group('bonus layout', () {
    test('pickups sit in the arena, on the island, mostly coins, none under the player', () {
      final sim = homeSim();
      final b = BonusRound(sim: sim, seed: 1);
      expect(b.pickups.length, greaterThan(20));
      expect(b.pickups.length, lessThanOrEqualTo(BonusRound.maxPickups));
      var gems = 0;
      for (final p in b.pickups) {
        expect(sim.arena.inBounds(p.x.floor(), p.y.floor()), isTrue);
        final d = math.sqrt(math.pow(p.x - 20.5, 2) + math.pow(p.y - 20.5, 2));
        expect(d, greaterThan(1));
        if (p.kind == PickupKind.gem) gems++;
      }
      expect(gems, lessThan(b.pickups.length ~/ 3));
      expect(b.coins, 0);
      expect(b.gems, 0);
    });

    test('a tiny island is padded so there is always loot', () {
      final sim = homeSim();
      sim.arena.reset();
      sim.arena.claimDisc(20.5, 20.5, 1.2, sim.human.id);
      final b = BonusRound(sim: sim, seed: 2);
      expect(b.pickups.length, greaterThanOrEqualTo(20));
    });

    test('same seed gives the same layout', () {
      final a = BonusRound(sim: homeSim(), seed: 9).pickups;
      final b = BonusRound(sim: homeSim(), seed: 9).pickups;
      expect([for (final p in a) '${p.x},${p.y},${p.kind}'], [for (final p in b) '${p.x},${p.y},${p.kind}']);
    });
  });

  group('bonus round', () {
    test('driving over pickups collects each exactly once and totals match', () {
      final sim = homeSim();
      final b = BonusRound(sim: sim, seed: 3);
      sim.human.desiredHeading = 0;
      final seen = <Pickup>{};
      for (var i = 0; i < 60 * 3; i++) {
        final got = b.update(1 / 60);
        for (final p in got) {
          expect(seen.add(p), isTrue, reason: 'collected twice');
        }
      }
      expect(seen, isNotEmpty);
      final coins = seen.where((p) => p.kind == PickupKind.coins).length * BonusRound.coinValue;
      final gems = seen.where((p) => p.kind == PickupKind.gem).length * BonusRound.gemValue;
      expect(b.coins, coins);
      expect(b.gems, gems);
      expect(b.pickups.where((p) => p.taken).length, seen.length);
    });

    test('timer runs out, then one +6s continue, then it is over', () {
      final sim = homeSim();
      final b = BonusRound(sim: sim, seed: 3);
      for (var i = 0; i < 60 * 11; i++) {
        b.update(1 / 60);
      }
      expect(b.expired, isTrue);
      expect(b.timeLeft, 0);
      final x = sim.human.x, y = sim.human.y;
      b.update(1 / 60);
      expect((sim.human.x, sim.human.y), (x, y), reason: 'no movement after time is up');
      expect(b.canExtend, isTrue);
      expect(b.extend(), isTrue);
      expect(b.timeLeft, BonusRound.extension);
      expect(b.expired, isFalse);
      expect(b.extend(), isFalse, reason: 'continue only once');
      for (var i = 0; i < 60 * 7; i++) {
        b.update(1 / 60);
      }
      expect(b.expired, isTrue);
      expect(b.canExtend, isFalse);
    });

    test('collecting everything finishes the round early', () {
      final sim = homeSim();
      final b = BonusRound(sim: sim, seed: 3);
      // Let everything drop in and land first.
      sim.human.speed = 0;
      for (var i = 0; i < 90; i++) {
        b.update(1 / 60);
      }
      for (final p in b.pickups) {
        sim.debugPlace(sim.human, p.x, p.y, 0);
        sim.human.speed = 0;
        b.update(1 / 60);
      }
      expect(b.allCollected, isTrue);
      expect(b.finished, isTrue);
      expect(b.expired, isFalse);
      final total = b.pickups.fold<int>(0, (a, p) => a + (p.kind == PickupKind.coins ? p.value : 0));
      expect(b.coins, total);
    });

    test('loot drops in as a ripple and cannot be grabbed mid-air', () {
      final sim = homeSim();
      final b = BonusRound(sim: sim, seed: 3);
      final near = b.pickups.reduce((a, c) =>
          (a.x - 20.5).abs() + (a.y - 20.5).abs() < (c.x - 20.5).abs() + (c.y - 20.5).abs() ? a : c);
      final far = b.pickups.reduce((a, c) =>
          (a.x - 20.5).abs() + (a.y - 20.5).abs() > (c.x - 20.5).abs() + (c.y - 20.5).abs() ? a : c);
      expect(far.delay, greaterThan(near.delay), reason: 'ripples outward from the player');
      for (final p in b.pickups) {
        expect(p.delay, inInclusiveRange(0, 0.8));
      }
      // Stand right on a pickup before it has landed: nothing is collected.
      sim.human.speed = 0;
      sim.debugPlace(sim.human, far.x, far.y, 0);
      b.update(1 / 60);
      expect(far.taken, isFalse);
      while (!b.landed(far)) {
        b.update(1 / 60);
      }
      b.update(1 / 60);
      expect(far.taken, isTrue, reason: 'collectable once it has landed');
    });

    test('the player slides along walls during the bonus too', () {
      final sim = homeSim();
      final b = BonusRound(sim: sim, seed: 3);
      sim.debugPlace(sim.human, 0.5, 20.5, math.pi - 0.3);
      for (var i = 0; i < 60; i++) {
        b.update(1 / 60);
      }
      expect(sim.human.x, inInclusiveRange(0, 0.01));
      expect(sim.human.y, greaterThan(21));
    });
  });

  group('multiplier meter', () {
    test('zones read x2 x3 x4 x3 x2 across the meter', () {
      expect(multiplierAt(0), 2);
      expect(multiplierAt(0.1), 2);
      expect(multiplierAt(0.3), 3);
      expect(multiplierAt(0.5), 4);
      expect(multiplierAt(0.7), 3);
      expect(multiplierAt(0.95), 2);
      expect(multiplierAt(1), 2);
      expect(multiplierAt(-1), 2);
      expect(multiplierAt(2), 2);
    });

    test('needle sweeps back and forth and stays in range', () {
      expect(meterPosition(0), 0);
      expect(meterPosition(kMeterSweep), closeTo(1, 1e-9));
      expect(meterPosition(kMeterSweep * 1.5), closeTo(0.5, 1e-9));
      expect(meterPosition(kMeterSweep * 2), closeTo(0, 1e-9));
      for (var t = 0.0; t < 10; t += 0.013) {
        final p = meterPosition(t);
        expect(p, inInclusiveRange(0, 1));
      }
      // Middle of the sweep lands on x4.
      expect(multiplierAt(meterPosition(kMeterSweep / 2)), 4);
    });
  });

  group('ink splash power', () {
    test('charges over time, paints a disc, then needs to recharge', () {
      final sim = Simulation(
          config: const LevelConfig(level: 3, arenaSize: 40, bots: 0, targetPercent: 99, botSkill: 0.5), seed: 5);
      sim.powersEnabled = true;
      sim.arena.reset();
      sim.arena.claimDisc(20.5, 20.5, 2.6, 1);
      sim.debugPlace(sim.human, 20.5, 20.5, 0);
      expect(sim.activatePower(), isFalse, reason: 'not charged');
      var t = 0.0;
      while (!sim.powerReady && t < 30) {
        sim.debugPlace(sim.human, 20.5, 20.5, 0);
        sim.step(1 / 60);
        t += 1 / 60;
      }
      expect(t, closeTo(Simulation.powerChargeSeconds, 0.1));
      // Stand at the island edge so part of the disc is new ground.
      sim.debugPlace(sim.human, 22.5, 20.5, 0);
      final before = sim.arena.counts[1];
      sim.drainEvents();
      expect(sim.activatePower(), isTrue);
      final gained = sim.arena.counts[1] - before;
      expect(gained, greaterThan(5));
      final ev = sim.drainEvents().whereType<PowerEvent>().single;
      expect(ev.cells, gained);
      expect(sim.humanPower, 0);
      expect(sim.activatePower(), isFalse);
      // Bookkeeping stays exact.
      var owned = 0;
      for (final o in sim.arena.owner) {
        if (o == 1) owned++;
      }
      expect(owned, sim.arena.counts[1]);
    });

    test('never paints over trails and is off unless powers are enabled', () {
      final sim = Simulation(
          config: const LevelConfig(level: 1, arenaSize: 40, bots: 1, targetPercent: 99, botSkill: 0.5), seed: 5);
      sim.humanPower = 1;
      expect(sim.activatePower(), isFalse, reason: 'powers disabled');
      sim.powersEnabled = true;
      final bot = sim.players[1];
      final h = sim.human;
      final idx = sim.arena.index(h.x.floor() + 1, h.y.floor());
      sim.arena.trail[idx] = bot.id;
      final ownerBefore = sim.arena.owner[idx];
      expect(sim.activatePower(), isTrue);
      expect(sim.arena.owner[idx], ownerBefore);
      expect(sim.arena.trail[idx], bot.id);
    });
  });
}
