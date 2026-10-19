import 'dart:math' as math;

import 'simulation.dart';

/// Opponent controller: plans rectangular excursions out of its territory,
/// heads home when threatened or when its trail gets long, hunts nearby enemy
/// trails and avoids the border and its own trail.
class BotBrain {
  BotBrain(this.skill, this.rng);

  final double skill;
  final math.Random rng;

  final List<double> _wp = []; // x0,y0,x1,y1...
  double _think = 0;
  double _wpTimer = 0;
  bool returning = false;
  bool hunting = false;

  int get maxTrail => (14 + skill * 40).round();

  void reset() {
    _wp.clear();
    _think = rng.nextDouble() * 0.2;
    _wpTimer = 0;
    returning = false;
    hunting = false;
  }

  void update(Simulation sim, SimPlayer p, double dt) {
    _think -= dt;
    _wpTimer += dt;
    if (_think > 0) return;
    _think = 0.07 + (1 - skill) * 0.12;
    final arena = sim.arena;

    if (!p.hasTrail) {
      returning = false;
      if (_wp.isEmpty || _wpTimer > 6) _planExcursion(sim, p);
    } else {
      final home = _nearestOwned(sim, p);
      final distHome = home == null
          ? 99.0
          : math.sqrt(_d2(p.x, p.y, home.$1, home.$2));
      final threat = _threatDistance(sim, p);
      final margin = 1.5 + skill * 4;
      final danger = threat < distHome + margin;
      // Mid-attack, a bold bot keeps going instead of retreating at the
      // first sign of danger.
      final scared = danger && !(hunting && rng.nextDouble() < 0.4 + skill * 0.5);
      if (!returning &&
          (scared || p.trailCells.length > maxTrail || _wpTimer > 9)) {
        returning = true;
        hunting = false;
      }
      if (returning && home != null) {
        _wp
          ..clear()
          ..addAll([home.$1, home.$2]);
      }
    }

    // Attack enemy trails (the player's above all) when one is in reach.
    if (skill > 0.25 && !returning && p.trailCells.length < 16 + skill * 26) {
      final target = _huntTarget(sim, p);
      if (target != null) {
        hunting = true;
        _wp
          ..clear()
          ..addAll([target.$1, target.$2]);
      } else if (hunting) {
        hunting = false;
        _wp.clear();
        if (p.hasTrail) returning = true;
      }
    }

    if (_wp.isNotEmpty) {
      final dx = _wp[0] - p.x, dy = _wp[1] - p.y;
      if (dx * dx + dy * dy < 0.8) {
        _wp.removeRange(0, 2);
        _wpTimer = 0;
        if (_wp.isEmpty && p.hasTrail) returning = true;
      }
    }
    double desired = p.desiredHeading;
    if (_wp.isNotEmpty) {
      desired = math.atan2(_wp[1] - p.y, _wp[0] - p.x);
    }
    p.desiredHeading = _safeHeading(sim, p, desired, arena.width, arena.height);
  }

  static double _d2(double ax, double ay, double bx, double by) =>
      (ax - bx) * (ax - bx) + (ay - by) * (ay - by);

  void _planExcursion(Simulation sim, SimPlayer p) {
    final arena = sim.arena;
    _wp.clear();
    _wpTimer = 0;
    // Prefer heading toward open space: sample a few angles.
    var bestA = rng.nextDouble() * math.pi * 2, bestScore = -1e9;
    for (var k = 0; k < 6; k++) {
      final a = rng.nextDouble() * math.pi * 2;
      final px = p.x + math.cos(a) * 8, py = p.y + math.sin(a) * 8;
      var score = rng.nextDouble() * 3;
      if (px < 3 || py < 3 || px > arena.width - 3 || py > arena.height - 3) {
        score -= 10;
      } else {
        final o = arena.owner[arena.index(px.floor(), py.floor())];
        if (o == 0) score += 3;
        if (o != 0 && o != p.id) score += 1.5 * skill; // steal territory
        if (o == p.id) score -= 2;
      }
      if (score > bestScore) {
        bestScore = score;
        bestA = a;
      }
    }
    // Walk to the territory edge along bestA.
    var ex = p.x, ey = p.y;
    for (var i = 0; i < 40; i++) {
      final cx = ex.floor(), cy = ey.floor();
      if (!arena.inBounds(cx, cy) ||
          arena.owner[arena.index(cx, cy)] != p.id) {
        break;
      }
      ex += math.cos(bestA);
      ey += math.sin(bestA);
    }
    final leg = 3 + rng.nextDouble() * (3 + skill * 9);
    final width = 2 + rng.nextDouble() * (2 + skill * 6);
    final turn = rng.nextBool() ? 1.0 : -1.0;
    final a2 = bestA + turn * math.pi / 2;
    final x1 = ex + math.cos(bestA) * leg, y1 = ey + math.sin(bestA) * leg;
    final x2 = x1 + math.cos(a2) * width, y2 = y1 + math.sin(a2) * width;
    final x3 = x2 - math.cos(bestA) * leg * 0.7,
        y3 = y2 - math.sin(bestA) * leg * 0.7;
    double cl(double v, int max) => v.clamp(2.0, max - 2.0).toDouble();
    _wp.addAll([
      cl(ex, arena.width), cl(ey, arena.height),
      cl(x1, arena.width), cl(y1, arena.height),
      cl(x2, arena.width), cl(y2, arena.height),
      cl(x3, arena.width), cl(y3, arena.height),
    ]);
  }

  (double, double)? _nearestOwned(Simulation sim, SimPlayer p) {
    final arena = sim.arena;
    final cx = p.cx, cy = p.cy;
    for (var r = 1; r < 50; r++) {
      (double, double)? best;
      var bestD = 1e9;
      for (var dy = -r; dy <= r; dy++) {
        for (var dx = -r; dx <= r; dx++) {
          if (dx.abs() != r && dy.abs() != r) continue;
          final x = cx + dx, y = cy + dy;
          if (!arena.inBounds(x, y)) continue;
          if (arena.owner[arena.index(x, y)] != p.id) continue;
          final d = (dx * dx + dy * dy).toDouble();
          if (d < bestD) {
            bestD = d;
            best = (x + 0.5, y + 0.5);
          }
        }
      }
      if (best != null) return best;
    }
    return null;
  }

  /// Distance from the nearest enemy head to any part of p's trail.
  double _threatDistance(Simulation sim, SimPlayer p) {
    var best = 1e9;
    final w = sim.arena.width;
    final cells = p.trailCells;
    final stride = math.max(1, cells.length ~/ 12);
    for (final q in sim.players) {
      if (q == p || !q.alive) continue;
      var d = _d2(q.x, q.y, p.x, p.y);
      for (var i = 0; i < cells.length; i += stride) {
        final c = cells[i];
        d = math.min(d, _d2(q.x, q.y, c % w + 0.5, c ~/ w + 0.5));
      }
      best = math.min(best, d);
    }
    // Lower-skill bots notice threats later.
    return math.sqrt(best) * (1.4 - skill * 0.4);
  }

  (double, double)? _huntTarget(Simulation sim, SimPlayer p) {
    final w = sim.arena.width;
    (double, double)? best;
    var bestScore = double.infinity;
    for (final q in sim.players) {
      if (q == p || !q.alive || !q.hasTrail) continue;
      // Bots gang up on the player: they spot its trail from much farther
      // away and take bigger risks to cut it.
      final range = q.isHuman ? 6 + skill * 14 : 3 + skill * 7;
      final cells = q.trailCells;
      // The trail lasts until its owner gets home (next to its first cell).
      final f = cells.first;
      final ownerHome = math.sqrt(_d2(q.x, q.y, f % w + 0.5, f ~/ w + 0.5));
      final stride = math.max(1, cells.length ~/ 16);
      for (var i = 0; i < cells.length; i += stride) {
        final c = cells[i];
        final x = c % w + 0.5, y = c ~/ w + 0.5;
        final d = _d2(p.x, p.y, x, y);
        if (d > range * range) continue;
        if (q.isHuman) {
          // Race the player home, and gamble a little on top.
          if (math.sqrt(d) >= ownerHome + 3 + skill * 5) continue;
        } else if (d >= _d2(q.x, q.y, x, y) + 4) {
          // Rivals: only if we get there before the owner does.
          continue;
        }
        final score = q.isHuman ? d * 0.6 : d;
        if (score < bestScore) {
          bestScore = score;
          best = (x, y);
        }
      }
    }
    return best;
  }

  double _safeHeading(
      Simulation sim, SimPlayer p, double desired, int w, int h) {
    const offsets = [0.0, 0.45, -0.45, 0.9, -0.9, 1.35, -1.35, 1.8, -1.8, 2.4, -2.4, 3.1];
    final look = (returning ? 2.4 : 1.4) + skill * 1.8;
    for (final o in offsets) {
      final a = desired + o;
      if (_pathSafe(sim, p, a, look, w, h)) return a;
    }
    return desired;
  }

  bool _pathSafe(
      Simulation sim, SimPlayer p, double a, double look, int w, int h) {
    final c = math.cos(a), s = math.sin(a);
    for (var d = 0.6; d <= look; d += 0.6) {
      final x = p.x + c * d, y = p.y + s * d;
      if (x < 0.7 || y < 0.7 || x > w - 0.7 || y > h - 0.7) return false;
    }
    return true;
  }
}
