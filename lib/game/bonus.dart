import 'dart:math' as math;

import 'sim/simulation.dart';

/// Bonus round after a win: the player glides over its painted island for a
/// few seconds collecting coin stacks and gems. Flutter-free and
/// deterministic for a given seed.
enum PickupKind { coins, gem }

class Pickup {
  Pickup(this.x, this.y, this.kind, [this.delay = 0]);
  final double x, y;
  final PickupKind kind;

  /// Seconds after the round starts before this one drops in (a ripple
  /// outward from the player).
  final double delay;
  bool taken = false;

  /// Seconds since collection (drives the fly-away animation).
  double takenAge = 0;

  int get value => kind == PickupKind.coins ? BonusRound.coinValue : BonusRound.gemValue;
}

class BonusRound {
  BonusRound({required this.sim, int seed = 1}) : _rng = math.Random(seed) {
    pickups.addAll(layout(sim, _rng));
  }

  static const double duration = 10;
  static const double extension = 6;
  static const int coinValue = 5;
  static const int gemValue = 1;
  // Above 1 so a path between two pickup rows (2 cells apart) still collects.
  static const double pickRadius = 1.1;
  static const int maxPickups = 90;

  /// Time a pickup takes to fall in and land; it can't be grabbed mid-air.
  static const double dropTime = 0.45;

  final Simulation sim;
  final math.Random _rng;
  final List<Pickup> pickups = [];

  double timeLeft = duration;

  /// Seconds since the round started (drives the drop-in animation).
  double elapsed = 0;
  int coins = 0;
  int gems = 0;

  /// The one-time "+6s" continue has been used.
  bool extended = false;

  bool get expired => timeLeft <= 0;
  bool get canExtend => !extended;
  bool get allCollected => pickups.every((p) => p.taken);

  bool landed(Pickup p) => elapsed >= p.delay + dropTime;
  bool get finished => expired || allCollected;

  /// Adds the continue time once. Returns false if already used.
  bool extend() {
    if (extended) return false;
    extended = true;
    timeLeft = math.max(0, timeLeft) + extension;
    return true;
  }

  /// Moves the player and collects what it touches; returns new pickups.
  List<Pickup> update(double dt) {
    final out = <Pickup>[];
    for (final p in pickups) {
      if (p.taken) p.takenAge += dt;
    }
    if (finished) return out;
    elapsed += dt;
    timeLeft = math.max(0, timeLeft - dt);
    final h = sim.human;
    sim.glide(h, dt);
    const r2 = pickRadius * pickRadius;
    for (final p in pickups) {
      if (p.taken || !landed(p)) continue;
      final dx = p.x - h.x, dy = p.y - h.y;
      if (dx * dx + dy * dy > r2) continue;
      p.taken = true;
      if (p.kind == PickupKind.coins) {
        coins += coinValue;
      } else {
        gems += gemValue;
      }
      out.add(p);
    }
    return out;
  }

  /// Pickups on a 2-cell lattice over the player's territory. A small island
  /// is padded with the area around the player so there is always enough to
  /// collect. Roughly one in ten pickups is a gem.
  static List<Pickup> layout(Simulation sim, math.Random rng) {
    final a = sim.arena, h = sim.human;
    final spots = <(double, double)>[];
    for (var y = 1; y < a.height; y += 2) {
      for (var x = 1; x < a.width; x += 2) {
        if (a.owner[a.index(x, y)] == h.id) spots.add((x + 0.5, y + 0.5));
      }
    }
    if (spots.length < 40) {
      for (var y = 1; y < a.height; y += 2) {
        for (var x = 1; x < a.width; x += 2) {
          final dx = x + 0.5 - h.x, dy = y + 0.5 - h.y;
          if (dx * dx + dy * dy <= 64 && a.owner[a.index(x, y)] != h.id) spots.add((x + 0.5, y + 0.5));
        }
      }
    }
    // Keep the closest ones so a huge island stays collectable in time.
    spots.sort((p, q) {
      final dp = (p.$1 - h.x) * (p.$1 - h.x) + (p.$2 - h.y) * (p.$2 - h.y);
      final dq = (q.$1 - h.x) * (q.$1 - h.x) + (q.$2 - h.y) * (q.$2 - h.y);
      return dp.compareTo(dq);
    });
    final out = <Pickup>[];
    for (final s in spots) {
      if (out.length >= maxPickups) break;
      final dx = s.$1 - h.x, dy = s.$2 - h.y;
      // Nothing right under the player at the start.
      if (dx * dx + dy * dy < 1.5) continue;
      final delay = math.min(0.8, math.sqrt(dx * dx + dy * dy) * 0.04);
      out.add(Pickup(s.$1, s.$2, rng.nextDouble() < 0.1 ? PickupKind.gem : PickupKind.coins, delay));
    }
    return out;
  }
}

/// Reward multiplier meter: a needle sweeps back and forth over five zones
/// x2 x3 x4 x3 x2; the zone under the needle when the player taps wins.
const List<int> kMultiplierZones = [2, 3, 4, 3, 2];

/// Seconds for the needle to go from one end to the other.
const double kMeterSweep = 0.8;

/// Needle position 0..1 after [seconds] (triangle wave).
double meterPosition(double seconds) {
  final t = (seconds / kMeterSweep) % 2;
  return t <= 1 ? t : 2 - t;
}

/// Multiplier for a needle position 0..1.
int multiplierAt(double position) {
  final i = (position.clamp(0.0, 1.0) * kMultiplierZones.length).floor();
  return kMultiplierZones[math.min(i, kMultiplierZones.length - 1)];
}
