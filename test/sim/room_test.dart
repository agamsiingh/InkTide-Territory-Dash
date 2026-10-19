import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:inktide/game/sim/arena.dart';
import 'package:inktide/game/sim/skins.dart';
import 'package:inktide/game/sim/simulation.dart' hide Simulation;
import 'package:inktide/game/sim/simulation.dart' as sim_lib show Simulation;

typedef Sim = sim_lib.Simulation;

Sim newRoom({int seed = 1}) => Sim.room(size: 60, seed: seed);

String? check(Sim sim) {
  final a = sim.arena;
  final counts = List.filled(Arena.maxPlayers + 1, 0);
  for (final o in a.owner) {
    counts[o]++;
  }
  for (var i = 0; i < counts.length; i++) {
    if (counts[i] != a.counts[i]) return 'counts[$i]=${a.counts[i]} but grid has ${counts[i]}';
  }
  for (final p in sim.players) {
    if (p.vacant && (a.counts[p.id] != 0 || p.alive || p.trailCells.isNotEmpty)) {
      return 'vacant slot ${p.id} still holds state';
    }
    if (!p.alive && p.trailCells.isNotEmpty) return '${p.name}: dead with a trail';
    if (p.alive) {
      if (p.x < 0 || p.y < 0 || p.x >= a.width || p.y >= a.height) return '${p.name} out of bounds';
      for (final c in p.trailCells) {
        if (a.owner[c] == p.id) return '${p.name}: trail inside own land';
        if (a.trail[c] != p.id) return '${p.name}: trail mark missing';
      }
    }
  }
  return null;
}

void main() {
  group('room: joining and leaving', () {
    test('players take slots 1..n, spawn alive with land, and byId works', () {
      final sim = newRoom();
      final a = sim.addPlayer(name: 'Ann', skin: kSkins.first, human: true)!;
      final b = sim.addPlayer(name: 'Bo', skin: skinById('teddy'), human: true)!;
      final bot = sim.addPlayer(name: 'Nugget', skin: skinById('froggy'), human: false)!;
      expect([a.id, b.id, bot.id], [1, 2, 3]);
      for (final p in [a, b, bot]) {
        expect(p.alive, isTrue);
        expect(sim.arena.counts[p.id], greaterThan(10));
        expect(sim.byId(p.id), same(p));
      }
      expect(sim.countPlayers(humans: true), 2);
      expect(sim.countPlayers(humans: false), 1);
      expect(bot.brain, isNotNull);
      expect(a.brain, isNull);
      expect(check(sim), isNull);
    });

    test('leaving frees land and the slot, which the next player reuses', () {
      final sim = newRoom();
      final a = sim.addPlayer(name: 'Ann', skin: kSkins.first, human: true)!;
      final b = sim.addPlayer(name: 'Bo', skin: kSkins.first, human: true)!;
      sim.removePlayer(a);
      expect(sim.arena.counts[1], 0);
      expect(a.vacant, isTrue);
      expect(sim.leaderboard().map((p) => p.id), [2], reason: 'vacant slots are not listed');
      final c = sim.addPlayer(name: 'Cy', skin: kSkins.first, human: true)!;
      expect(c.id, 1, reason: 'first free slot');
      expect(sim.players.length, 2);
      expect(b.alive, isTrue);
      expect(check(sim), isNull);
    });

    test('the arena holds at most 16 players', () {
      final sim = Sim.room(size: 90);
      for (var i = 0; i < Arena.maxPlayers; i++) {
        expect(sim.addPlayer(name: 'P$i', skin: kSkins.first, human: false), isNotNull, reason: 'slot $i');
      }
      expect(sim.addPlayer(name: 'Extra', skin: kSkins.first, human: true), isNull);
    });
  });

  group('room: play', () {
    test('a splatted human comes back by itself and the match never ends', () {
      final sim = newRoom();
      final a = sim.addPlayer(name: 'Ann', skin: kSkins.first, human: true)!;
      sim.addPlayer(name: 'Bo', skin: kSkins.first, human: true);
      sim.debugKill(a, 0, DeathCause.border);
      expect(a.alive, isFalse);
      expect(sim.isOver, isFalse);
      expect(sim.humanDead, isFalse);
      expect(sim.arena.counts[a.id], 0);
      var t = 0.0;
      while (!a.alive && t < 6) {
        sim.step(1 / 30);
        t += 1 / 30;
      }
      expect(a.alive, isTrue, reason: 'respawns after 2-4 s');
      expect(t, inInclusiveRange(1.9, 4.2));
      expect(sim.arena.counts[a.id], greaterThan(10));
      expect(sim.isOver, isFalse);
    });

    test('there is no win in a room however much land you own', () {
      final sim = newRoom();
      final a = sim.addPlayer(name: 'Ann', skin: kSkins.first, human: true)!;
      for (var i = 0; i < sim.arena.owner.length ~/ 2; i++) {
        sim.arena.setOwner(i, a.id);
      }
      sim.step(1 / 30);
      expect(sim.won, isFalse);
      expect(sim.isOver, isFalse);
    });

    test('each human steers independently', () {
      final sim = newRoom(seed: 4);
      final a = sim.addPlayer(name: 'Ann', skin: kSkins.first, human: true)!;
      final b = sim.addPlayer(name: 'Bo', skin: kSkins.first, human: true)!;
      sim.debugPlace(a, 15.5, 30.5, 0);
      sim.debugPlace(b, 45.5, 30.5, math.pi);
      sim.steerPlayer(a, -math.pi / 2);
      sim.steerPlayer(b, math.pi / 2);
      for (var i = 0; i < 45; i++) {
        sim.step(1 / 30);
      }
      expect(a.y, lessThan(28), reason: 'Ann went up');
      expect(b.y, greaterThan(32), reason: 'Bo went down');
      // Non-finite input is ignored, never poisons the heading.
      final before = a.desiredHeading;
      sim.steerPlayer(a, double.nan);
      sim.steerPlayer(a, double.infinity);
      expect(a.desiredHeading, before);
    });

    test('one human cutting another human trail kills them and takes their land', () {
      final sim = newRoom(seed: 9);
      final a = sim.addPlayer(name: 'Ann', skin: kSkins.first, human: true)!;
      final b = sim.addPlayer(name: 'Bo', skin: kSkins.first, human: true)!;
      sim.arena.reset();
      for (final p in sim.players) {
        p.trailCells.clear();
        p.trailPoints.clear();
      }
      sim.arena.claimDisc(10.5, 10.5, 2.6, a.id);
      sim.arena.claimDisc(45.5, 45.5, 2.6, b.id);
      for (var x = 12; x <= 40; x++) {
        final i = sim.arena.index(x, 30);
        sim.arena.trail[i] = b.id;
        b.trailCells.add(i);
      }
      b.trailPoints.addAll([12.5, 30.5, 40.5, 30.5]);
      sim.debugPlace(b, 40.5, 30.5, 0);
      sim.debugPlace(a, 25.5, 27.5, math.pi / 2);
      sim.steerPlayer(a, math.pi / 2);
      sim.steerPlayer(b, 0);
      final bLand = sim.arena.counts[b.id], aLand = sim.arena.counts[a.id];
      sim.drainEvents();
      for (var i = 0; i < 60 && b.alive; i++) {
        sim.step(1 / 30);
      }
      expect(b.alive, isFalse);
      expect(a.kills, 1);
      expect(sim.arena.counts[a.id], aLand + bLand);
      expect(sim.arena.counts[b.id], 0);
      expect(sim.isOver, isFalse);
    });

    test('a human can respawn even when one player owns almost the whole arena', () {
      final sim = newRoom(seed: 3);
      final a = sim.addPlayer(name: 'Ann', skin: kSkins.first, human: true)!;
      final boss = sim.addPlayer(name: 'Boss', skin: kSkins.first, human: false)!;
      for (var i = 0; i < sim.arena.owner.length; i++) {
        if (sim.arena.owner[i] != a.id) sim.arena.setOwner(i, boss.id);
      }
      sim.debugKill(a, 0, DeathCause.border);
      expect(sim.arena.counts[0], lessThan(30), reason: 'only the few cells she just freed: too small to spawn on');
      final bossBefore = sim.arena.counts[boss.id];
      var t = 0.0;
      while (!a.alive && t < 8) {
        sim.step(1 / 30);
        t += 1 / 30;
      }
      expect(a.alive, isTrue, reason: 'respawned by carving out a patch');
      expect(sim.arena.counts[a.id], greaterThan(10));
      expect(sim.arena.counts[boss.id], lessThan(bossBefore), reason: 'the boss lost that patch');
      expect(check(sim), isNull);
    });

    test('resetRound wipes the arena, zeroes kills and respawns everybody on fresh ground', () {
      final sim = newRoom(seed: 8);
      final a = sim.addPlayer(name: 'Ann', skin: kSkins.first, human: true)!;
      final b = sim.addPlayer(name: 'Bo', skin: kSkins.first, human: true)!;
      final bot = sim.addPlayer(name: 'Nugget', skin: kSkins.first, human: false)!;
      for (var i = 0; i < 900; i++) {
        sim.arena.setOwner(i, a.id);
      }
      a.kills = 4;
      b.kills = 2;
      sim.debugKill(b, 0, DeathCause.border);
      sim.drainEvents();
      sim.resetRound();
      for (final p in [a, b, bot]) {
        expect(p.alive, isTrue);
        expect(p.kills, 0);
        expect(p.trailCells, isEmpty);
        expect(sim.arena.counts[p.id], inInclusiveRange(15, 30), reason: 'just the starting patch');
      }
      expect(sim.arena.counts[0], sim.arena.cellCount - sim.arena.counts[1] - sim.arena.counts[2] - sim.arena.counts[3]);
      expect(sim.drainEvents().whereType<SpawnEvent>().length, 3);
      expect(check(sim), isNull);
    });

    test('random play with humans and bots keeps every invariant (fuzz)', () {
      for (var seed = 1; seed <= 25; seed++) {
        final sim = Sim.room(size: 64, seed: seed);
        final rng = math.Random(seed * 17);
        final humans = <SimPlayer>[];
        for (var i = 0; i < 3; i++) {
          humans.add(sim.addPlayer(name: 'H$i', skin: kSkins.first, human: true)!);
        }
        for (var i = 0; i < 4; i++) {
          sim.addPlayer(name: 'B$i', skin: kSkins.first, human: false, skill: 0.4 + i * 0.15);
        }
        var t = 0.0;
        while (t < 40) {
          if (rng.nextDouble() < 0.06) {
            sim.steerPlayer(humans[rng.nextInt(3)], rng.nextDouble() * 2 * math.pi);
          }
          // Players come and go while the match runs.
          if (rng.nextDouble() < 0.004) {
            final h = humans[rng.nextInt(3)];
            if (!h.vacant) {
              sim.removePlayer(h);
            }
            final slot = sim.players.indexWhere((p) => p.vacant);
            if (slot >= 0) {
              final n = sim.addPlayer(name: 'N$t', skin: kSkins.first, human: true)!;
              humans[humans.indexWhere((x) => x.vacant)] = n;
            }
          }
          sim.step(1 / 30);
          final e = check(sim);
          expect(e, isNull, reason: 'seed $seed t=${t.toStringAsFixed(1)}: $e');
          t += 1 / 30;
        }
        expect(sim.isOver, isFalse);
      }
    });
  });

  group('arena helpers for the network', () {
    test('changeLog lists every changed cell once per change and can be drained', () {
      final a = Arena(10, 10)..reset();
      a.changeLog = [];
      a.setOwner(3, 1);
      a.setOwner(3, 1); // no change: not logged
      a.setOwner(7, 2);
      a.setOwner(3, 2);
      expect(a.changeLog, [3, 7, 3]);
      expect(a.counts[2], 2);
    });

    test('loadOwners replaces the grid, recounts and ignores bad owner bytes', () {
      final a = Arena(4, 4)..reset();
      final data = List<int>.filled(16, 0);
      data[0] = 1;
      data[1] = 1;
      data[2] = 3;
      data[3] = 250; // invalid
      final v = a.version;
      a.loadOwners(data);
      expect(a.counts[1], 2);
      expect(a.counts[3], 1);
      expect(a.counts[0], 13);
      expect(a.owner[3], 0);
      expect(a.version, greaterThan(v));
      // Short data is padded with unclaimed cells.
      a.loadOwners([2, 2]);
      expect(a.counts[2], 2);
      expect(a.counts[0], 14);
    });
  });
}
