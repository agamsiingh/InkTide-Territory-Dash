import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:inktide/game/sim/levels.dart';
import 'package:inktide/game/sim/simulation.dart';

/// 40x40 arena with one bot. [attacker] owns the block x 2..10, y 10..30 and
/// has a U-shaped trail (row 15 and row 25 from x 11..25, joined at x 25)
/// whose last cell is (11, 25). [victim] owns only a disc at (18.5, 20.5),
/// which lies inside the U. Moving [attacker] one cell left closes the loop.
(Simulation, SimPlayer attacker, SimPlayer victim) enclosureSetup({required bool humanAttacks}) {
  final sim = Simulation(
    config: const LevelConfig(level: 1, arenaSize: 40, bots: 1, targetPercent: 99, botSkill: 0.5),
    seed: 3,
  );
  final a = sim.arena..reset();
  for (final p in sim.players) {
    p.trailCells.clear();
    p.trailPoints.clear();
  }
  final attacker = humanAttacks ? sim.human : sim.players[1];
  final victim = humanAttacks ? sim.players[1] : sim.human;
  for (var y = 10; y <= 30; y++) {
    for (var x = 2; x <= 10; x++) {
      a.setOwner(a.index(x, y), attacker.id);
    }
  }
  a.claimDisc(18.5, 20.5, 2.6, victim.id);
  void mark(int x, int y) {
    final i = a.index(x, y);
    a.trail[i] = attacker.id;
    attacker.trailCells.add(i);
  }

  for (var x = 11; x <= 25; x++) {
    mark(x, 15);
  }
  for (var y = 16; y <= 25; y++) {
    mark(25, y);
  }
  for (var x = 24; x >= 11; x--) {
    mark(x, 25);
  }
  attacker.trailPoints.addAll([11.0, 15.5, 25.5, 15.5, 25.5, 25.5, 11.05, 25.5]);
  // Just right of the territory edge, heading left into it.
  sim.debugPlace(attacker, 11.05, 25.5, math.pi);
  sim.debugPlace(victim, 18.5, 20.5, 0);
  sim.drainEvents();
  return (sim, attacker, victim);
}

void main() {
  group('enclosing a rival', () {
    test('human capturing all of a bot territory eliminates the bot', () {
      final (sim, h, bot) = enclosureSetup(humanAttacks: true);
      for (var i = 0; i < 10 && bot.alive; i++) {
        sim.step(1 / 60);
      }
      final events = sim.drainEvents();
      final capture = events.whereType<CaptureEvent>().single;
      expect(capture.playerId, h.id);
      final death = events.whereType<DeathEvent>().single;
      expect(death.victimId, bot.id);
      expect(death.killerId, h.id);
      expect(death.cause, DeathCause.territoryLost);
      expect(bot.alive, isFalse);
      expect(h.kills, 1);
      expect(sim.arena.counts[bot.id], 0);
      expect(sim.arena.owner[sim.arena.index(18, 20)], h.id, reason: 'enclosed bot disc now belongs to the human');
      expect(sim.isOver, isFalse);
    });

    test('bot capturing all of the human territory ends the match', () {
      final (sim, bot, h) = enclosureSetup(humanAttacks: false);
      final percentBefore = sim.percentOf(h);
      expect(percentBefore, greaterThan(0));
      for (var i = 0; i < 10 && !sim.isOver; i++) {
        sim.step(1 / 60);
      }
      final death = sim.drainEvents().whereType<DeathEvent>().single;
      expect(death.victimId, h.id);
      expect(death.killerId, bot.id);
      expect(death.cause, DeathCause.territoryLost);
      expect(sim.humanDead, isTrue);
      expect(sim.isOver, isTrue);
      expect(sim.won, isFalse);
      expect(sim.humanScorePercent, 0, reason: 'nothing was left when the human was eliminated');
      expect(bot.kills, 1);
    });

    test('a partial enclosure only takes the enclosed cells and keeps the rival alive', () {
      final (sim, h, bot) = enclosureSetup(humanAttacks: true);
      // Give the bot extra territory outside the U.
      sim.arena.claimDisc(33.5, 33.5, 2.6, bot.id);
      final outside = sim.arena.counts[bot.id] - 21;
      for (var i = 0; i < 10 && sim.events.whereType<CaptureEvent>().isEmpty; i++) {
        sim.step(1 / 60);
      }
      expect(bot.alive, isTrue);
      expect(sim.arena.counts[bot.id], outside);
      expect(sim.drainEvents().whereType<DeathEvent>(), isEmpty);
    });
  });
}
