import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:inktide/game/sim/levels.dart';
import 'package:inktide/game/sim/simulation.dart';

/// Returns a description of the first broken invariant, or null.
String? checkInvariants(Simulation sim) {
  final a = sim.arena;
  final counts = List<int>.filled(a.counts.length, 0);
  for (final o in a.owner) {
    counts[o]++;
  }
  for (var i = 0; i < counts.length; i++) {
    if (counts[i] != a.counts[i]) return 'counts[$i]=${a.counts[i]} but $i owns ${counts[i]} cells';
  }
  var pct = 0.0;
  for (final p in sim.players) {
    pct += sim.percentOf(p);
  }
  if (pct > 100.0001) return 'percentages sum to $pct';

  for (final p in sim.players) {
    final marks = <int>{};
    for (var i = 0; i < a.trail.length; i++) {
      if (a.trail[i] == p.id) marks.add(i);
    }
    final cells = p.trailCells.toSet();
    if (cells.length != p.trailCells.length) return '${p.name}: duplicate trail cells';
    if (!p.alive) {
      if (marks.isNotEmpty) return '${p.name}: dead but still has ${marks.length} trail marks';
      if (p.trailCells.isNotEmpty) return '${p.name}: dead but trailCells not empty';
      if (a.counts[p.id] != 0) return '${p.name}: dead but owns ${a.counts[p.id]} cells';
      continue;
    }
    if (!marks.containsAll(cells) || !cells.containsAll(marks)) {
      return '${p.name}: trail marks ${marks.length} != trailCells ${cells.length}';
    }
    for (final c in p.trailCells) {
      if (a.owner[c] == p.id) return '${p.name}: trail cell $c is inside own territory';
    }
    // Re-entering a grace cell is not re-appended, so check the marked set
    // (what the flood fill sees) rather than consecutive list entries.
    if (cells.isNotEmpty) {
      final seen = {p.trailCells.first};
      final queue = [p.trailCells.first];
      while (queue.isNotEmpty) {
        final c = queue.removeLast();
        for (final n in [c - 1, c + 1, c - a.width, c + a.width]) {
          if (n < 0 || n >= a.trail.length) continue;
          if ((n % a.width - c % a.width).abs() > 1) continue;
          if (cells.contains(n) && seen.add(n)) queue.add(n);
        }
      }
      if (seen.length != cells.length) return '${p.name}: trail not 4-connected (${seen.length}/${cells.length})';
    }
    if (p.hasTrail && p.trailPoints.length < 4) return '${p.name}: trail without polyline';
    if (p.x < 0 || p.y < 0 || p.x >= a.width || p.y >= a.height) return '${p.name}: out of bounds';
    if (p.cx != p.x.floor() || p.cy != p.y.floor()) return '${p.name}: cell (${p.cx},${p.cy}) != floor(pos)';
    if (a.counts[p.id] == 0) return '${p.name}: alive with no territory';
  }
  if (sim.human.alive == sim.humanDead) return 'human alive=${sim.human.alive} humanDead=${sim.humanDead}';
  if (sim.humanScorePercent < 0 || sim.humanScorePercent > 100) return 'score ${sim.humanScorePercent}';
  return null;
}

void main() {
  group('randomized invariants', () {
    for (var seed = 1; seed <= 60; seed++) {
      test('seed $seed', () {
        final level = 1 + seed % 8;
        final sim = Simulation(config: LevelConfig.forLevel(level), seed: seed);
        final rng = math.Random(seed * 31);
        var t = 0.0, nextTurn = 0.0;
        expect(checkInvariants(sim), isNull);
        while (t < 90 && !sim.isOver) {
          if (t >= nextTurn) {
            sim.steerHuman(sim.human.heading + (rng.nextDouble() - 0.5) * 3.5);
            nextTurn = t + 0.15 + rng.nextDouble() * 0.6;
          }
          // Mix frame lengths like a real device (including long frames).
          final dt = rng.nextDouble() < 0.05 ? 1 / 30 : 1 / 60;
          sim.step(dt);
          t += dt;
          final err = checkInvariants(sim);
          if (err != null) fail('t=${t.toStringAsFixed(2)} level $level: $err');
        }
      });
    }
  });

  test('bots-only long match stays consistent and keeps respawning', () {
    final sim = Simulation(config: LevelConfig.forLevel(9), seed: 99);
    final hx = sim.human.x, hy = sim.human.y;
    var deaths = 0, spawns = 0;
    for (var i = 0; i < 60 * 120 && !sim.isOver; i++) {
      sim.debugPlace(sim.human, hx, hy, 0);
      sim.step(1 / 60);
      for (final e in sim.drainEvents()) {
        if (e is DeathEvent) deaths++;
        if (e is SpawnEvent) spawns++;
      }
      final err = checkInvariants(sim);
      if (err != null) fail('frame $i: $err');
    }
    expect(deaths, greaterThan(0), reason: 'bots should fight over two minutes');
    expect(spawns, greaterThan(0), reason: 'dead bots should respawn');
  });
}
