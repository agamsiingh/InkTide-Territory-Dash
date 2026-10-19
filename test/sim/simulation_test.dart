import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:inktide/game/sim/levels.dart';
import 'package:inktide/game/sim/simulation.dart';

const double kDt = 1 / 60;

/// Small bot-free (by default) arena for scripted scenarios.
LevelConfig testConfig({int bots = 0, double target = 99, int size = 40, double skill = 0.5}) =>
    LevelConfig(level: 1, arenaSize: size, bots: bots, targetPercent: target, botSkill: skill);

Simulation newSim({int bots = 0, double target = 99, int seed = 7, SpeedSetting speed = SpeedSetting.normal}) =>
    Simulation(config: testConfig(bots: bots, target: target), seed: seed, speed: speed);

/// Wipes the arena and gives the human a fresh r=2.6 disc at ([cx], [cy]),
/// standing in its centre facing right. Other players keep their state but
/// lose their territory and trails.
void setHome(Simulation sim, {double cx = 20.5, double cy = 20.5}) {
  sim.arena.reset();
  for (final p in sim.players) {
    p.trailCells.clear();
    p.trailPoints.clear();
  }
  sim.arena.claimDisc(cx, cy, 2.6, sim.human.id);
  sim.debugPlace(sim.human, cx, cy, 0);
  sim.drainEvents();
}

/// Steps in 1/60 s increments until [cond] holds, the match ends or
/// [maxSeconds] pass. Returns the final value of [cond].
bool runUntil(Simulation sim, bool Function() cond, {double maxSeconds = 5}) {
  var t = 0.0;
  while (t < maxSeconds && !sim.isOver && !cond()) {
    sim.step(kDt);
    t += kDt;
  }
  return cond();
}

/// Runs the match while pinning the human inside its spawn territory so the
/// bots can play undisturbed (human never leaves its own cell, so it has no
/// trail and wins every head-on collision).
List<SimEvent> runParked(Simulation sim, double seconds) {
  final hx = sim.human.x, hy = sim.human.y;
  final events = <SimEvent>[];
  var t = 0.0;
  while (t < seconds && !sim.isOver) {
    sim.debugPlace(sim.human, hx, hy, 0);
    sim.step(kDt);
    events.addAll(sim.drainEvents());
    t += kDt;
  }
  return events;
}

int trailMarksOf(Simulation sim, int id) => sim.arena.trail.where((t) => t == id).length;

void main() {
  group('construction', () {
    test('players spawn alive with territory and no trails', () {
      final sim = Simulation(config: LevelConfig.forLevel(1), seed: 3);
      expect(sim.players.length, 1 + LevelConfig.forLevel(1).bots);
      expect(sim.human.isHuman, isTrue);
      expect(sim.human.id, 1);
      for (final p in sim.players) {
        expect(p.alive, isTrue);
        expect(p.hasTrail, isFalse);
        expect(sim.arena.counts[p.id], greaterThan(0));
        expect(sim.byId(p.id), same(p));
      }
      expect(sim.byId(0), isNull);
      expect(sim.byId(sim.players.length + 1), isNull);
      final spawns = sim.drainEvents().whereType<SpawnEvent>().length;
      expect(spawns, sim.players.length);
      expect(sim.drainEvents(), isEmpty, reason: 'drain clears the queue');
    });

    test('bot-free config has only the human', () {
      final sim = newSim();
      expect(sim.players.length, 1);
      expect(sim.isOver, isFalse);
    });
  });

  group('movement', () {
    test('human moves along its heading at its speed', () {
      final sim = newSim();
      setHome(sim);
      sim.steerHuman(0);
      final x0 = sim.human.x, y0 = sim.human.y;
      for (var i = 0; i < 30; i++) {
        sim.step(kDt);
      }
      expect(sim.human.x - x0, closeTo(6.3 * 0.5, 0.05));
      expect(sim.human.y, closeTo(y0, 1e-9));
      expect(sim.time, closeTo(0.5, 1e-9));
    });

    test('steering turns the human (limited turn rate) and moves it down', () {
      final sim = newSim();
      setHome(sim);
      sim.steerHuman(math.pi / 2);
      sim.step(kDt);
      // Max turn per 1/60 s at 9 rad/s is 0.15 rad.
      expect(sim.human.heading, closeTo(0.15, 1e-9));
      for (var i = 0; i < 30; i++) {
        sim.step(kDt);
      }
      expect(sim.human.heading, closeTo(math.pi / 2, 1e-9));
      expect(sim.human.y, greaterThan(20.5 + 1.5));
    });

    test('speed setting changes human speed', () {
      final slow = newSim(speed: SpeedSetting.slow);
      final fast = newSim(speed: SpeedSetting.fast);
      expect(slow.human.speed, 5.0);
      expect(fast.human.speed, 7.6);
      setHome(fast);
      fast.steerHuman(0);
      for (var i = 0; i < 30; i++) {
        fast.step(kDt);
      }
      expect(fast.human.x - 20.5, closeTo(7.6 * 0.5, 0.05));
    });

    test('step is ignored once the match is over', () {
      final sim = newSim();
      setHome(sim);
      sim.won = true;
      expect(sim.isOver, isTrue);
      final t = sim.time, x = sim.human.x;
      sim.step(kDt);
      expect(sim.time, t);
      expect(sim.human.x, x);
    });
  });

  group('trails', () {
    test('no trail inside own territory', () {
      final sim = newSim();
      setHome(sim);
      sim.steerHuman(0);
      // Stay within the disc (cells x 18..22 on row 20).
      runUntil(sim, () => sim.human.x >= 22.5);
      expect(sim.human.trailCells, isEmpty);
      expect(trailMarksOf(sim, 1), 0);
    });

    test('leaving territory lays a trail marked with the human id', () {
      final sim = newSim();
      setHome(sim);
      sim.steerHuman(0);
      expect(runUntil(sim, () => sim.human.x >= 28), isTrue);
      final h = sim.human;
      expect(h.trailCells.length, greaterThanOrEqualTo(5));
      expect(h.hasTrail, isTrue);
      expect(h.trailPoints.length, greaterThanOrEqualTo(4));
      for (final idx in h.trailCells) {
        expect(sim.arena.trail[idx], h.id);
        expect(sim.arena.owner[idx], isNot(h.id));
      }
      expect(h.trailCells.toSet().length, h.trailCells.length, reason: 'no duplicate cells');
      expect(h.trailCells.first, sim.arena.index(23, 20));
      expect(trailMarksOf(sim, 1), h.trailCells.length);
    });
  });

  group('capture', () {
    /// Drives a rectangle out of the spawn disc and back in.
    List<SimEvent> driveRectangle(Simulation sim) {
      final h = sim.human;
      sim.steerHuman(0);
      expect(runUntil(sim, () => h.x >= 27), isTrue, reason: 'leg 1');
      sim.steerHuman(math.pi / 2);
      expect(runUntil(sim, () => h.y >= 26), isTrue, reason: 'leg 2');
      sim.steerHuman(math.pi);
      expect(runUntil(sim, () => h.x <= 20.5), isTrue, reason: 'leg 3');
      sim.steerHuman(-math.pi / 2);
      runUntil(sim, () => sim.events.any((e) => e is CaptureEvent), maxSeconds: 3);
      return sim.drainEvents();
    }

    test('closing a loop into own territory captures the enclosed area', () {
      final sim = newSim();
      setHome(sim);
      final h = sim.human;
      final before = sim.percentOf(h);
      final cellsBefore = sim.arena.counts[1];
      expect(cellsBefore, 21);

      final events = driveRectangle(sim);
      final captures = events.whereType<CaptureEvent>().toList();
      expect(captures, hasLength(1));
      expect(captures.single.playerId, 1);
      expect(captures.single.cells, sim.arena.counts[1] - cellsBefore);
      expect(captures.single.cells, greaterThan(25));
      expect(sim.percentOf(h), greaterThan(before + 1.0));
      expect(h.alive, isTrue);
      expect(h.trailCells, isEmpty);
      expect(h.trailPoints, isEmpty);
      expect(trailMarksOf(sim, 1), 0);
      // A cell well inside the rectangle is now owned.
      expect(sim.arena.owner[sim.arena.index(24, 24)], 1);
      expect(sim.human.sinceCapture, lessThan(0.5));
    });

    test('reaching the target percent wins the match', () {
      final sim = newSim(target: 2.0);
      setHome(sim);
      expect(sim.percentOf(sim.human), lessThan(2.0));
      sim.step(kDt);
      expect(sim.won, isFalse);
      driveRectangle(sim);
      expect(sim.percentOf(sim.human), greaterThanOrEqualTo(2.0));
      expect(sim.won, isTrue);
      expect(sim.isOver, isTrue);
      expect(sim.humanDead, isFalse);
      expect(sim.humanScorePercent, sim.percentOf(sim.human));
    });
  });

  group('deaths', () {
    test('driving into the border slides along it instead of dying', () {
      final sim = newSim();
      setHome(sim);
      // Heading left and slightly down into the left wall.
      sim.debugPlace(sim.human, 1.5, 20.5, math.pi - 0.4);
      sim.human.desiredHeading = sim.human.heading;
      sim.run(1);
      expect(sim.humanDead, isFalse);
      expect(sim.human.alive, isTrue);
      expect(sim.human.onWall, isTrue);
      expect(sim.human.x, inInclusiveRange(0, 0.01), reason: 'pressed against the wall');
      expect(sim.human.y, greaterThan(20.5 + 1), reason: 'slid sideways (down)');
      final deaths = sim.drainEvents().whereType<DeathEvent>().where((d) => d.victimId == 1);
      expect(deaths, isEmpty);
    });

    test('hitting a wall head-on slides toward the middle; corners release', () {
      final sim = newSim();
      setHome(sim);
      final w = sim.arena.width.toDouble(), h = sim.arena.height.toDouble();
      // Straight up into the top wall, left of centre: slides right.
      sim.debugPlace(sim.human, 6.5, 0.5, -math.pi / 2);
      sim.human.desiredHeading = -math.pi / 2;
      sim.run(0.5);
      expect(sim.human.alive, isTrue);
      expect(sim.human.x, greaterThan(6.5));
      expect(sim.human.y, inInclusiveRange(0, 0.01));
      // Diagonally into the bottom-right corner: never leaves the arena.
      sim.debugPlace(sim.human, w - 3, h - 3, math.pi / 4);
      sim.human.desiredHeading = math.pi / 4;
      for (var i = 0; i < 60; i++) {
        sim.step(1 / 30);
        expect(sim.human.x, inInclusiveRange(0, w));
        expect(sim.human.y, inInclusiveRange(0, h));
      }
      expect(sim.human.alive, isTrue);
      // Steering away leaves the wall.
      sim.human.desiredHeading = -3 * math.pi / 4;
      sim.run(0.5);
      expect(sim.human.onWall, isFalse);
    });

    test('crossing your own trail does nothing: no death, no capture', () {
      final sim = newSim();
      setHome(sim);
      final h = sim.human;
      final landBefore = sim.arena.counts[1];
      sim.steerHuman(0);
      expect(runUntil(sim, () => h.x >= 30), isTrue);
      sim.steerHuman(-math.pi / 2);
      expect(runUntil(sim, () => h.y <= 16), isTrue);
      sim.steerHuman(math.pi);
      expect(runUntil(sim, () => h.x <= 26), isTrue);
      final trailLenBefore = h.trailCells.length;
      sim.steerHuman(math.pi / 2);
      // Drive down through the first leg of its own trail and out the other side.
      expect(runUntil(sim, () => h.y >= 23, maxSeconds: 4), isTrue);
      expect(sim.humanDead, isFalse);
      expect(h.alive, isTrue);
      expect(h.hasTrail, isTrue, reason: 'still out on the excursion, nothing was claimed');
      expect(sim.arena.counts[1], landBefore, reason: 'no land is taken by touching your own line');
      expect(h.trailCells.length, greaterThanOrEqualTo(trailLenBefore));
      final events = sim.drainEvents();
      expect(events.whereType<CaptureEvent>().where((c) => c.playerId == 1), isEmpty);
      expect(events.whereType<DeathEvent>().where((d) => d.victimId == 1), isEmpty);
      // The pocket made by the crossing is NOT land.
      expect(sim.arena.owner[sim.arena.index(28, 18)], 0);
    });

    test('the area is only claimed when you return to your own land, as a closed figure', () {
      final sim = newSim();
      setHome(sim);
      final h = sim.human;
      final landBefore = sim.arena.counts[1];
      sim.steerHuman(0);
      expect(runUntil(sim, () => h.x >= 30), isTrue);
      sim.steerHuman(-math.pi / 2);
      expect(runUntil(sim, () => h.y <= 14), isTrue);
      sim.steerHuman(math.pi);
      expect(runUntil(sim, () => h.x <= 20), isTrue);
      expect(sim.arena.counts[1], landBefore, reason: 'nothing yet while still out');
      sim.steerHuman(math.pi / 2);
      expect(runUntil(sim, () => !h.hasTrail, maxSeconds: 4), isTrue);
      expect(sim.arena.counts[1], greaterThan(landBefore + 20), reason: 'closing the loop at home claims the area');
      expect(sim.arena.owner[sim.arena.index(25, 18)], 1);
      expect(sim.humanDead, isFalse);
    });

    test('touching your own trail again later still does not end the run', () {
      final sim = newSim();
      sim.arena.reset();
      sim.arena.claimDisc(30.5, 30.5, 2.6, 1);
      final h = sim.human;
      sim.debugPlace(h, 10.5, 10.5, 0);
      sim.drainEvents();
      expect(runUntil(sim, () => h.trailCells.length >= 8), isTrue);
      final cells = List<int>.of(h.trailCells);
      final w = sim.arena.width;
      // Turn around and walk straight back along the whole trail.
      sim.debugPlace(h, cells.last % w + 0.5, 10.5, math.pi);
      expect(runUntil(sim, () => h.cx <= cells.first % w - 1, maxSeconds: 3), isTrue);
      expect(sim.humanDead, isFalse);
      expect(h.alive, isTrue);
    });

    test('bots go after the player trail from far away', () {
      final sim = Simulation(
          config: const LevelConfig(level: 5, arenaSize: 50, bots: 1, targetPercent: 99, botSkill: 0.8), seed: 3);
      final bot = sim.players[1];
      final h = sim.human;
      sim.arena.reset();
      sim.arena.claimDisc(10.5, 25.5, 2.6, h.id);
      sim.arena.claimDisc(38.5, 25.5, 2.6, bot.id);
      for (final p in sim.players) {
        p.trailCells.clear();
        p.trailPoints.clear();
      }
      // The player is out on a long excursion 14 cells from the bot.
      for (var x = 13; x <= 24; x++) {
        final i = sim.arena.index(x, 25);
        sim.arena.trail[i] = h.id;
        h.trailCells.add(i);
      }
      h.trailPoints.addAll([13.5, 25.5, 24.5, 25.5]);
      sim.debugPlace(h, 24.5, 25.5, 0);
      sim.debugPlace(bot, 38.5, 25.5, math.pi);
      var cut = false;
      for (var t = 0.0; t < 6 && !cut; t += 1 / 60) {
        // Keep the player parked at the end of its trail.
        sim.debugPlace(h, 24.5, 25.5, 0);
        sim.step(1 / 60);
        cut = sim.humanDead;
      }
      expect(cut, isTrue, reason: 'the bot hunted down and cut the trail');
      final d = sim.drainEvents().whereType<DeathEvent>().firstWhere((e) => e.victimId == h.id);
      expect(d.killerId, bot.id);
    });

    test('killing a rival hands their territory to the killer', () {
      final sim = newSim(bots: 1);
      final bot = sim.players[1];
      final h = sim.human;
      sim.arena.reset();
      sim.arena.claimDisc(8.5, 8.5, 2.6, h.id);
      sim.arena.claimDisc(32.5, 32.5, 2.6, bot.id);
      for (final p in sim.players) {
        p.trailCells.clear();
        p.trailPoints.clear();
      }
      for (var x = 10; x <= 30; x++) {
        final i = sim.arena.index(x, 20);
        sim.arena.trail[i] = bot.id;
        bot.trailCells.add(i);
      }
      sim.debugPlace(bot, 30.5, 20.5, 0);
      sim.debugPlace(h, 15.5, 17.5, math.pi / 2);
      final botLand = sim.arena.counts[bot.id], mine = sim.arena.counts[h.id];
      sim.drainEvents();
      expect(runUntil(sim, () => !bot.alive, maxSeconds: 1), isTrue);
      expect(sim.arena.counts[bot.id], 0);
      expect(sim.arena.counts[h.id], mine + botLand, reason: 'their island is now ours');
      final cap = sim.drainEvents().whereType<CaptureEvent>().where((c) => c.playerId == h.id);
      expect(cap.map((c) => c.cells), contains(botLand));
      expect(sim.arena.owner[sim.arena.index(32, 32)], h.id);
    });

    test('crossing a bot trail kills the bot and credits the human', () {
      final sim = newSim(bots: 1);
      final bot = sim.players[1];
      final h = sim.human;
      sim.arena.reset();
      sim.arena.claimDisc(8.5, 8.5, 2.6, h.id);
      sim.arena.claimDisc(32.5, 32.5, 2.6, bot.id);
      for (final p in sim.players) {
        p.trailCells.clear();
        p.trailPoints.clear();
      }
      // The bot is on an excursion: trail along row 20, head at its end.
      for (var x = 10; x <= 30; x++) {
        final i = sim.arena.index(x, 20);
        sim.arena.trail[i] = bot.id;
        bot.trailCells.add(i);
      }
      sim.debugPlace(bot, 30.5, 20.5, 0);
      sim.debugPlace(h, 15.5, 17.5, math.pi / 2);
      sim.drainEvents();

      expect(runUntil(sim, () => !bot.alive, maxSeconds: 1), isTrue);
      final deaths = sim.drainEvents().whereType<DeathEvent>().toList();
      expect(deaths, hasLength(1));
      expect(deaths.single.victimId, bot.id);
      expect(deaths.single.killerId, h.id);
      expect(deaths.single.cause, DeathCause.trailCut);
      expect(h.kills, 1);
      expect(h.alive, isTrue);
      expect(sim.isOver, isFalse);
      expect(sim.arena.counts[bot.id], 0, reason: 'dead bot territory is released');
      expect(trailMarksOf(sim, bot.id), 0);
      expect(bot.trailCells, isEmpty);
      expect(bot.respawnIn, inInclusiveRange(2.0, 4.0));
    });

    test('dead bot respawns after 2-4 seconds', () {
      final sim = newSim(bots: 1);
      final bot = sim.players[1];
      final h = sim.human;
      setHome(sim, cx: 8.5, cy: 8.5);
      sim.arena.claimDisc(32.5, 32.5, 2.6, bot.id);
      for (var x = 10; x <= 30; x++) {
        final i = sim.arena.index(x, 20);
        sim.arena.trail[i] = bot.id;
        bot.trailCells.add(i);
      }
      sim.debugPlace(bot, 30.5, 20.5, 0);
      sim.debugPlace(h, 15.5, 17.5, math.pi / 2);
      expect(runUntil(sim, () => !bot.alive, maxSeconds: 1), isTrue);
      // Park the human safely at home without a trail.
      sim.arena.clearTrail(h.id, h.trailCells);
      h.trailCells.clear();
      h.trailPoints.clear();
      sim.drainEvents();
      var t = 0.0;
      while (!bot.alive && t < 6) {
        sim.debugPlace(h, 8.5, 8.5, 0);
        sim.step(kDt);
        t += kDt;
      }
      expect(bot.alive, isTrue);
      expect(t, inInclusiveRange(1.9, 4.1));
      expect(sim.drainEvents().whereType<SpawnEvent>().map((e) => e.playerId), contains(bot.id));
      expect(sim.arena.counts[bot.id], greaterThan(0));
      expect(bot.hasTrail, isFalse);
    });

    test('head-on outside both territories kills both', () {
      final sim = newSim(bots: 1);
      final bot = sim.players[1];
      final h = sim.human;
      sim.arena.reset();
      sim.arena.claimDisc(5.5, 5.5, 2.6, h.id);
      sim.arena.claimDisc(34.5, 34.5, 2.6, bot.id);
      sim.debugPlace(h, 19.8, 20.5, 0);
      sim.debugPlace(bot, 20.2, 20.5, math.pi);
      sim.drainEvents();
      sim.step(kDt);
      expect(h.alive, isFalse);
      expect(bot.alive, isFalse);
      expect(sim.humanDead, isTrue);
      final deaths = sim.drainEvents().whereType<DeathEvent>().toList();
      expect(deaths, hasLength(2));
      expect(deaths.every((d) => d.cause == DeathCause.headOn), isTrue);
      expect(deaths.map((d) => d.victimId).toSet(), {h.id, bot.id});
    });

    test('head-on: the player inside its own territory survives', () {
      final sim = newSim(bots: 1);
      final bot = sim.players[1];
      final h = sim.human;
      setHome(sim); // human home disc around (20.5, 20.5)
      sim.arena.claimDisc(34.5, 34.5, 2.6, bot.id);
      sim.debugPlace(h, 20.5, 20.5, 0);
      sim.debugPlace(bot, 20.9, 20.5, math.pi);
      sim.step(kDt);
      expect(h.alive, isTrue);
      expect(bot.alive, isFalse);
      expect(sim.isOver, isFalse);
      expect(h.kills, 1);
      final death = sim.drainEvents().whereType<DeathEvent>().single;
      expect(death.victimId, bot.id);
      expect(death.killerId, h.id);
      expect(death.cause, DeathCause.headOn);
    });

    test('head-on: human outside its territory dies against a bot at home', () {
      final sim = newSim(bots: 1);
      final bot = sim.players[1];
      final h = sim.human;
      sim.arena.reset();
      sim.arena.claimDisc(5.5, 5.5, 2.6, h.id);
      sim.arena.claimDisc(20.5, 20.5, 2.6, bot.id);
      sim.debugPlace(bot, 20.5, 20.5, 0);
      sim.debugPlace(h, 20.9, 20.5, math.pi);
      sim.drainEvents();
      sim.step(kDt);
      expect(h.alive, isFalse);
      expect(bot.alive, isTrue);
      expect(bot.kills, 1);
      expect(sim.drainEvents().whereType<DeathEvent>().single.cause, DeathCause.headOn);
    });
  });

  group('determinism', () {
    test('same seed gives identical matches', () {
      final a = Simulation(config: LevelConfig.forLevel(3), seed: 42);
      final b = Simulation(config: LevelConfig.forLevel(3), seed: 42);
      runParked(a, 20);
      runParked(b, 20);
      expect(a.time, b.time);
      expect(a.arena.owner, equals(b.arena.owner));
      expect(a.arena.trail, equals(b.arena.trail));
      for (var i = 0; i < a.players.length; i++) {
        expect(a.players[i].x, b.players[i].x);
        expect(a.players[i].y, b.players[i].y);
        expect(a.players[i].alive, b.players[i].alive);
        expect(a.players[i].kills, b.players[i].kills);
        expect(a.players[i].name, b.players[i].name);
      }
    });

    test('same seed without intervention gives identical results', () {
      final a = Simulation(config: LevelConfig.forLevel(2), seed: 9);
      final b = Simulation(config: LevelConfig.forLevel(2), seed: 9);
      a.run(20);
      b.run(20);
      expect(a.time, b.time);
      expect(a.humanDead, b.humanDead);
      expect(a.arena.owner, equals(b.arena.owner));
    });
  });

  group('opponent AI', () {
    const fourBots = LevelConfig(level: 2, arenaSize: 64, bots: 4, targetPercent: 99, botSkill: 0.31);

    for (final seed in [1, 2, 3]) {
      test('bots expand their territory (seed $seed)', () {
        final sim = Simulation(config: fourBots, seed: seed);
        final start = {for (final p in sim.players.skip(1)) p.id: sim.percentOf(p)};
        final best = Map<int, double>.of(start);
        final hx = sim.human.x, hy = sim.human.y;
        var botCaptures = 0;
        var t = 0.0;
        while (t < 30 && !sim.isOver) {
          sim.debugPlace(sim.human, hx, hy, 0);
          sim.step(kDt);
          t += kDt;
          for (final e in sim.drainEvents()) {
            if (e is CaptureEvent && e.playerId != 1) botCaptures++;
          }
          for (final p in sim.players.skip(1)) {
            best[p.id] = math.max(best[p.id]!, sim.percentOf(p));
          }
        }
        expect(botCaptures, greaterThan(0));
        final grew = start.keys.where((id) => best[id]! > start[id]! + 0.01).length;
        expect(grew, greaterThanOrEqualTo(1));
      });

      test('bots rarely hit the border (seed $seed)', () {
        final sim = Simulation(config: fourBots, seed: seed);
        final events = runParked(sim, 60);
        final borderDeaths = events
            .whereType<DeathEvent>()
            .where((d) => d.victimId != 1 && d.cause == DeathCause.border)
            .length;
        expect(borderDeaths, lessThanOrEqualTo(3));
        // Sanity: bots stayed in bounds the whole time.
        for (final p in sim.players) {
          if (!p.alive) continue;
          expect(p.x, inInclusiveRange(0, sim.arena.width.toDouble()));
          expect(p.y, inInclusiveRange(0, sim.arena.height.toDouble()));
        }
      });
    }

    test('arena bookkeeping stays consistent during a busy match', () {
      final sim = Simulation(config: LevelConfig.forLevel(6), seed: 11);
      runParked(sim, 30);
      final sum = sim.arena.counts.fold<int>(0, (s, c) => s + c);
      expect(sum, sim.arena.cellCount);
      for (final p in sim.players) {
        if (!p.alive) {
          expect(sim.arena.counts[p.id], 0);
          expect(p.trailCells, isEmpty);
        }
        for (final idx in p.trailCells) {
          expect(sim.arena.trail[idx], p.id);
        }
      }
    });
  });

  group('leaderboard', () {
    test('sorted by territory, descending, human always included', () {
      final sim = Simulation(config: LevelConfig.forLevel(4), seed: 5);
      runParked(sim, 15);
      final board = sim.leaderboard();
      expect(board, contains(sim.human));
      for (var i = 1; i < board.length; i++) {
        expect(sim.arena.counts[board[i - 1].id], greaterThanOrEqualTo(sim.arena.counts[board[i].id]));
      }
      for (final p in board) {
        expect(p.alive || p.isHuman, isTrue);
      }
    });

    test('leader is whoever owns most cells', () {
      final sim = newSim(bots: 2);
      sim.arena.reset();
      sim.arena.claimDisc(8.5, 8.5, 2.6, 1);
      sim.arena.claimDisc(20.5, 20.5, 6, 3);
      sim.arena.claimDisc(30.5, 30.5, 4, 2);
      final board = sim.leaderboard();
      expect(board.map((p) => p.id).toList(), [3, 2, 1]);
    });
  });

  test('normalizeAngle wraps into [-pi, pi]', () {
    expect(Simulation.normalizeAngle(3 * math.pi), closeTo(math.pi, 1e-9));
    expect(Simulation.normalizeAngle(-3 * math.pi / 2), closeTo(math.pi / 2, 1e-9));
    expect(Simulation.normalizeAngle(0.5), 0.5);
  });
}
