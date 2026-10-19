import 'dart:math' as math;

import 'ai.dart';
import 'arena.dart';
import 'levels.dart';
import 'skins.dart';

enum DeathCause { border, trailCut, headOn, territoryLost }

sealed class SimEvent {
  const SimEvent();
}

class CaptureEvent extends SimEvent {
  const CaptureEvent(this.playerId, this.cells, this.x, this.y);
  final int playerId;
  final int cells;
  final double x, y;
}

class DeathEvent extends SimEvent {
  const DeathEvent(this.victimId, this.killerId, this.cause, this.x, this.y);
  final int victimId;

  /// 0 when nobody gets credit (e.g. hitting the border).
  final int killerId;
  final DeathCause cause;
  final double x, y;
}

/// The human used the Ink Splash power and painted [cells] around itself.
class PowerEvent extends SimEvent {
  const PowerEvent(this.playerId, this.cells, this.x, this.y);
  final int playerId;
  final int cells;
  final double x, y;
}

class SpawnEvent extends SimEvent {
  const SpawnEvent(this.playerId);
  final int playerId;
}

class SimPlayer {
  SimPlayer({
    required this.id,
    required this.name,
    required this.skin,
    required this.isHuman,
    required this.speed,
    required this.turnRate,
    this.brain,
  });

  final int id;
  final String name;
  final Skin skin;
  final bool isHuman;
  double speed;
  final double turnRate;
  final BotBrain? brain;

  bool alive = false;
  double x = 0, y = 0;
  double heading = 0;
  double desiredHeading = 0;
  int cx = 0, cy = 0;
  int kills = 0;
  double respawnIn = 0;

  /// Seconds since the last capture (drives squash animation).
  double sinceCapture = 99;

  /// Cell indices of the current trail, in order.
  final List<int> trailCells = [];

  /// Polyline (x0, y0, x1, y1, ...) in cell units, for smooth rendering.
  final List<double> trailPoints = [];

  /// Bumped whenever the trail polyline is thrown away and restarted, so the
  /// network layer can tell "more points" from "a brand new trail".
  int trailGen = 0;

  void resetTrail() {
    trailPoints.clear();
    trailGen++;
  }

  /// True while pressed against the arena edge and sliding along it.
  bool onWall = false;

  /// Online rooms: slot is empty (nobody here, never respawns).
  bool vacant = false;

  /// Client mirror of a server-driven player: it has a trail polyline but no
  /// trail cells.
  bool remote = false;

  bool get hasTrail => trailCells.isNotEmpty || (remote && trailPoints.length >= 4);
}

/// Deterministic, Flutter-free match simulation. Units are cells.
class Simulation {
  Simulation({
    required this.config,
    int seed = 1,
    Skin? humanSkin,
    String humanName = 'You',
    this.speed = SpeedSetting.normal,
  })  : rng = math.Random(seed),
        arena = Arena(config.arenaSize, config.arenaSize),
        persistent = false {
    arena.reset();
    final base = speedCellsPerSecond(speed);
    final hs = humanSkin ?? kSkins.first;
    players.add(SimPlayer(
      id: 1,
      name: humanName,
      skin: hs,
      isHuman: true,
      speed: base,
      turnRate: 9.0,
    ));
    final botSkins = kSkins.where((s) => s.id != hs.id).toList()..shuffle(math.Random(seed ^ 0x5eed));
    final names = List<String>.of(kBotNames)..shuffle(rng);
    for (var i = 0; i < config.bots; i++) {
      final skill = (config.botSkill + (rng.nextDouble() - 0.5) * 0.2)
          .clamp(0.05, 1.0)
          .toDouble();
      players.add(SimPlayer(
        id: i + 2,
        name: names[i % names.length],
        skin: botSkins[i % botSkins.length],
        isHuman: false,
        speed: base * (0.9 + 0.13 * skill),
        turnRate: 6.5,
        brain: BotBrain(skill, math.Random(rng.nextInt(1 << 30))),
      ));
    }
    for (final p in players) {
      _spawn(p);
    }
  }

  /// An empty online arena: players join with [addPlayer], come back after
  /// every death and there is no winning, so the match never ends. Also used
  /// by clients as a read-only mirror of the server's arena.
  Simulation.room({required int size, int seed = 1, this.speed = SpeedSetting.normal})
      : config = LevelConfig(level: 1, arenaSize: size, bots: 0, targetPercent: 100, botSkill: 0.7),
        rng = math.Random(seed),
        arena = Arena(size, size),
        persistent = true {
    arena.reset();
  }

  final LevelConfig config;
  final math.Random rng;
  final Arena arena;
  final List<SimPlayer> players = [];
  final List<SimEvent> events = [];

  /// Online room mode (see [Simulation.room]).
  final bool persistent;
  final SpeedSetting speed;

  /// Index into [players] of the local player (clients of an online room).
  int humanIndex = 0;

  double time = 0;
  bool humanDead = false;
  bool won = false;

  /// Human territory % at the moment of death (territory is then released).
  double humanFinalPercent = 0;

  /// Score shown on the results screen.
  double get humanScorePercent =>
      humanDead ? humanFinalPercent : percentOf(human);

  /// Ink Splash power (human only): charges while alive, then a double tap
  /// paints a disc of territory around the player.
  bool powersEnabled = false;
  double humanPower = 0;
  static const double powerChargeSeconds = 15;
  static const double splashRadius = 2.8;
  bool get powerReady => powersEnabled && humanPower >= 1;

  SimPlayer get human => players[humanIndex];
  bool get isOver => !persistent && (humanDead || won);

  SimPlayer? byId(int id) =>
      (id >= 1 && id <= players.length) ? players[id - 1] : null;

  double percentOf(SimPlayer p) => arena.percentOf(p.id);

  /// Players sorted by territory, largest first.
  List<SimPlayer> leaderboard() {
    final list = players.where((p) => !p.vacant && (p.alive || p.isHuman)).toList();
    list.sort((a, b) => arena.counts[b.id].compareTo(arena.counts[a.id]));
    return list;
  }

  List<SimEvent> drainEvents() {
    final out = List<SimEvent>.of(events);
    events.clear();
    return out;
  }

  /// Steers the human toward [angle] (radians).
  void steerHuman(double angle) => human.desiredHeading = angle;

  /// Steers [p] toward [angle]; ignores non-finite angles.
  void steerPlayer(SimPlayer p, double angle) {
    if (angle.isFinite) p.desiredHeading = normalizeAngle(angle);
  }

  // ---- online rooms ---------------------------------------------------------

  /// Places a new player in the first free slot (a vacated one, else a new
  /// one) and spawns it. Returns null when the arena is full.
  SimPlayer? addPlayer({
    required String name,
    required Skin skin,
    required bool human,
    double skill = 0.7,
    int? seed,
  }) {
    var idx = players.indexWhere((p) => p.vacant);
    if (idx < 0) {
      if (players.length >= Arena.maxPlayers) return null;
      idx = players.length;
      players.add(_vacantSlot(idx + 1));
    }
    final base = speedCellsPerSecond(speed);
    final p = SimPlayer(
      id: idx + 1,
      name: name,
      skin: skin,
      isHuman: human,
      speed: human ? base : base * (0.9 + 0.13 * skill),
      turnRate: human ? 9.0 : 6.5,
      brain: human ? null : BotBrain(skill, math.Random(seed ?? rng.nextInt(1 << 30))),
    );
    players[idx] = p;
    _spawn(p);
    return p;
  }

  /// Fills slot [id] without spawning anyone (a client mirroring the server).
  SimPlayer ensureSlot(int id, {required String name, required Skin skin, required bool human}) {
    while (players.length < id) {
      players.add(_vacantSlot(players.length + 1));
    }
    final old = players[id - 1];
    if (!old.vacant && old.name == name && old.skin.id == skin.id && old.isHuman == human) return old;
    final p = SimPlayer(id: id, name: name, skin: skin, isHuman: human, speed: 6.3, turnRate: 9, brain: null)
      ..remote = true;
    players[id - 1] = p;
    return p;
  }

  SimPlayer _vacantSlot(int id) => SimPlayer(
        id: id,
        name: '',
        skin: kSkins.first,
        isHuman: false,
        speed: 0,
        turnRate: 0,
      )..vacant = true;

  /// Takes [p] out of the arena: its land and trail disappear and the slot is
  /// free for the next player.
  void removePlayer(SimPlayer p) {
    arena.clearTrail(p.id, p.trailCells);
    p.trailCells.clear();
    p.resetTrail();
    arena.releaseAll(p.id);
    p
      ..alive = false
      ..vacant = true;
  }

  /// Starts a fresh round: the arena is wiped, every player's kills reset and
  /// everyone is spawned again on new ground. Online rooms only.
  void resetRound() {
    assert(persistent);
    arena.reset();
    final seated = [for (final p in players) if (!p.vacant) p];
    for (final p in seated) {
      p.trailCells.clear();
      p.resetTrail();
      p
        ..alive = false
        ..kills = 0
        ..respawnIn = 0;
    }
    events.clear();
    // Random order so nobody always gets the best spot.
    seated.shuffle(rng);
    for (final p in seated) {
      _spawn(p);
    }
  }

  /// Number of players currently in the arena, [humans] or bots.
  int countPlayers({required bool humans}) =>
      players.where((p) => !p.vacant && p.isHuman == humans).length;

  void step(double dt) {
    if (isOver) return;
    time += dt;
    for (final p in players) {
      p.sinceCapture += dt;
      if (!p.alive && !p.vacant && (!p.isHuman || persistent)) {
        p.respawnIn -= dt;
        if (p.respawnIn <= 0) _spawn(p);
      }
    }
    for (final p in players) {
      if (p.alive) p.brain?.update(this, p, dt);
    }
    if (!persistent && powersEnabled && human.alive) {
      humanPower = math.min(1.0, humanPower + dt / powerChargeSeconds);
    }
    var maxSpeed = 0.0;
    for (final p in players) {
      maxSpeed = math.max(maxSpeed, p.speed);
    }
    final steps = math.max(1, (maxSpeed * dt / 0.45).ceil());
    final sub = dt / steps;
    for (var s = 0; s < steps && !isOver; s++) {
      for (final p in players) {
        if (p.alive) _move(p, sub);
      }
      _headCollisions();
    }
    if (persistent) return;
    final h = human;
    if (h.alive && !humanDead && percentOf(h) >= config.targetPercent) {
      won = true;
    }
  }

  // ---------------------------------------------------------------------

  static double normalizeAngle(double a) {
    while (a > math.pi) {
      a -= 2 * math.pi;
    }
    while (a < -math.pi) {
      a += 2 * math.pi;
    }
    return a;
  }

  /// Direction to slide along a wall: keep the sideways part of the heading,
  /// or head for the middle when hitting the wall almost head-on.
  static double _slideSign(double v, double step, double pos, int size) {
    if (v.abs() > step * 0.05) return v.sign;
    return pos < size / 2 ? 1 : -1;
  }

  /// Turns and moves [p] with wall sliding but no cell logic (bonus round).
  void glide(SimPlayer p, double dt) => _advance(p, dt);

  void _move(SimPlayer p, double dt) {
    final ox = p.x, oy = p.y;
    _advance(p, dt);
    final nx = p.x, ny = p.y;
    if (p.hasTrail) {
      final n = p.trailPoints.length;
      if (n < 2) {
        // Trail cells without a polyline (e.g. restored state): restart it here.
        p.trailPoints.addAll([ox, oy, nx, ny]);
      } else {
        final lx = p.trailPoints[n - 2], ly = p.trailPoints[n - 1];
        final dx = nx - lx, dy = ny - ly;
        if (dx * dx + dy * dy > 0.09) p.trailPoints.addAll([nx, ny]);
      }
    }
    final ncx = nx.floor(), ncy = ny.floor();
    if (ncx == p.cx && ncy == p.cy) return;
    if (ncx != p.cx && ncy != p.cy) {
      // Diagonal step: visit the intermediate cell so trails stay connected.
      _enter(p, ncx, p.cy, ox, oy);
      // Only stop if the mover died; ending the match (e.g. by cutting the
      // human's trail) must still leave this player's cell up to date.
      if (!p.alive) return;
    }
    p.cx = ncx;
    p.cy = ncy;
    _enter(p, ncx, ncy, ox, oy);
  }

  void _advance(SimPlayer p, double dt) {
    final diff = normalizeAngle(p.desiredHeading - p.heading);
    final maxTurn = p.turnRate * dt;
    p.heading = normalizeAngle(p.heading + diff.clamp(-maxTurn, maxTurn));
    final step = p.speed * dt;
    var dx = math.cos(p.heading) * step;
    var dy = math.sin(p.heading) * step;
    // The arena edge is solid: instead of dying, slide sideways along it
    // (like Paper.io). Moving straight into it slides toward the centre.
    final maxX = arena.width - 1e-3, maxY = arena.height - 1e-3;
    final outX = p.x + dx < 0 || p.x + dx > maxX;
    final outY = p.y + dy < 0 || p.y + dy > maxY;
    p.onWall = outX || outY;
    if (outX && outY) {
      // Pushing into a corner: escape along the axis we push into least.
      if (dx.abs() < dy.abs()) {
        dx = (p.x < arena.width / 2 ? 1 : -1) * step;
        dy = 0;
      } else {
        dy = (p.y < arena.height / 2 ? 1 : -1) * step;
        dx = 0;
      }
    } else if (outX) {
      // Keep dx so the clamp below presses the player flush to the wall.
      dy = _slideSign(dy, step, p.y, arena.height) * step;
    } else if (outY) {
      dx = _slideSign(dx, step, p.x, arena.width) * step;
    }
    p.x = (p.x + dx).clamp(0.0, maxX).toDouble();
    p.y = (p.y + dy).clamp(0.0, maxY).toDouble();
  }

  void _enter(SimPlayer p, int cx, int cy, double ox, double oy) {
    final idx = arena.index(cx, cy);
    final t = arena.trail[idx];
    // Your own trail is harmless: crossing it neither hurts nor claims
    // anything. Land is only taken by getting back to your own territory.
    if (t != 0 && t != p.id) {
      final victim = byId(t);
      if (victim != null && victim.alive) {
        _kill(victim, p.id, DeathCause.trailCut);
      } else {
        arena.trail[idx] = 0;
      }
    }
    if (arena.owner[idx] == p.id) {
      if (p.hasTrail) _capture(p);
      return;
    }
    if (arena.trail[idx] == p.id) return;
    if (!p.hasTrail) {
      p.resetTrail();
      p.trailPoints.addAll([ox, oy, p.x, p.y]);
    }
    arena.trail[idx] = p.id;
    p.trailCells.add(idx);
  }

  void _capture(SimPlayer p) {
    final gained = arena.capture(p.id, p.trailCells);
    p.trailCells.clear();
    p.resetTrail();
    p.sinceCapture = 0;
    events.add(CaptureEvent(p.id, gained, p.x, p.y));
    for (final q in players) {
      if (q != p && q.alive && arena.counts[q.id] == 0) {
        _kill(q, p.id, DeathCause.territoryLost);
      }
    }
  }

  /// Ink Splash: paints a disc around the human. Trail cells (anyone's) are
  /// left alone so trails stay consistent; rivals reduced to nothing are
  /// eliminated like after a capture. Returns false when not charged.
  bool activatePower() {
    final h = human;
    if (!powerReady || isOver || !h.alive) return false;
    humanPower = 0;
    const r = splashRadius;
    var gained = 0;
    for (var y = (h.y - r).floor(); y <= (h.y + r).ceil(); y++) {
      for (var x = (h.x - r).floor(); x <= (h.x + r).ceil(); x++) {
        if (!arena.inBounds(x, y)) continue;
        final dx = x + 0.5 - h.x, dy = y + 0.5 - h.y;
        if (dx * dx + dy * dy > r * r) continue;
        final idx = arena.index(x, y);
        if (arena.trail[idx] != 0 || arena.owner[idx] == h.id) continue;
        arena.setOwner(idx, h.id);
        gained++;
      }
    }
    h.sinceCapture = 0;
    events.add(PowerEvent(h.id, gained, h.x, h.y));
    for (final q in players) {
      if (q != h && q.alive && arena.counts[q.id] == 0) {
        _kill(q, h.id, DeathCause.territoryLost);
      }
    }
    return true;
  }

  void _kill(SimPlayer p, int killerId, DeathCause cause) {
    if (!p.alive) return;
    p.alive = false;
    arena.clearTrail(p.id, p.trailCells);
    p.trailCells.clear();
    p.resetTrail();
    if (p.isHuman && !persistent) humanFinalPercent = arena.percentOf(p.id);
    final killer = killerId != 0 && killerId != p.id ? byId(killerId) : null;
    if (killer != null && killer.alive) {
      // The victim's land goes to whoever took them out.
      final moved = arena.transferAll(p.id, killer.id);
      if (moved > 0) events.add(CaptureEvent(killer.id, moved, killer.x, killer.y));
      // A trail that now runs through inherited land is closed: capture it.
      if (killer.hasTrail && killer.trailCells.any((c) => arena.owner[c] == killer.id)) {
        _capture(killer);
      }
    } else {
      arena.releaseAll(p.id);
    }
    killer?.kills++;
    events.add(DeathEvent(p.id, killerId, cause, p.x, p.y));
    if (p.isHuman && !persistent) {
      humanDead = true;
    } else {
      p.respawnIn = 2.0 + rng.nextDouble() * 2.0;
    }
  }

  void _headCollisions() {
    for (var i = 0; i < players.length; i++) {
      final a = players[i];
      if (!a.alive) continue;
      for (var j = i + 1; j < players.length; j++) {
        final b = players[j];
        if (!b.alive) continue;
        final dx = a.x - b.x, dy = a.y - b.y;
        if (dx * dx + dy * dy > 0.36) continue;
        final aIn = arena.owner[arena.index(a.cx, a.cy)] == a.id;
        final bIn = arena.owner[arena.index(b.cx, b.cy)] == b.id;
        if (aIn && !bIn) {
          _kill(b, a.id, DeathCause.headOn);
        } else if (bIn && !aIn) {
          _kill(a, b.id, DeathCause.headOn);
        } else if (!aIn && !bIn) {
          _kill(a, b.id, DeathCause.headOn);
          _kill(b, a.id, DeathCause.headOn);
        }
        if (!a.alive) break;
      }
    }
  }

  /// Places [p] at a free spot with a small starting territory. Bots retry
  /// later when the arena has no free space.
  void _spawn(SimPlayer p) {
    const r = 2.6;
    final w = arena.width, h = arena.height;
    double bx = w / 2, by = h / 2;
    var best = -1.0;
    var found = false;
    for (var attempt = 0; attempt < 120; attempt++) {
      final x = 6 + rng.nextDouble() * (w - 12);
      final y = 6 + rng.nextDouble() * (h - 12);
      if (!_areaFree(x, y, r + 1.5)) continue;
      var minD = 1e9;
      for (final q in players) {
        if (q == p || !q.alive) continue;
        final dx = q.x - x, dy = q.y - y;
        minD = math.min(minD, dx * dx + dy * dy);
      }
      found = true;
      if (minD > best) {
        best = minD;
        bx = x;
        by = y;
      }
      if (minD > 144) break;
    }
    if (!found && persistent) {
      // A crowded or nearly full arena: pick the spot furthest from everyone
      // and take the land there. Whoever owned it loses that patch.
      for (var attempt = 0; attempt < 60; attempt++) {
        final x = 6 + rng.nextDouble() * (w - 12);
        final y = 6 + rng.nextDouble() * (h - 12);
        var minD = 1e9;
        for (final q in players) {
          if (q == p || !q.alive) continue;
          final dx = q.x - x, dy = q.y - y;
          minD = math.min(minD, dx * dx + dy * dy);
        }
        if (minD > best) {
          best = minD;
          bx = x;
          by = y;
        }
      }
      found = true;
    }
    if (!found && !p.isHuman) {
      p.respawnIn = 1.0;
      return;
    }
    bx = bx.floorToDouble() + 0.5;
    by = by.floorToDouble() + 0.5;
    arena.claimDisc(bx, by, r, p.id);
    if (persistent) {
      // Anyone whose last land was just taken is out.
      for (final q in players) {
        if (q != p && q.alive && arena.counts[q.id] == 0) {
          _kill(q, 0, DeathCause.territoryLost);
        }
      }
    }
    p
      ..x = bx
      ..y = by
      ..cx = bx.floor()
      ..cy = by.floor()
      ..heading = rng.nextDouble() * 2 * math.pi - math.pi
      ..alive = true
      ..sinceCapture = 99
      ..trailCells.clear();
    p.resetTrail();
    p.desiredHeading = p.heading;
    p.brain?.reset();
    events.add(SpawnEvent(p.id));
  }

  bool _areaFree(double cx, double cy, double r) {
    for (var y = (cy - r).floor(); y <= (cy + r).ceil(); y++) {
      for (var x = (cx - r).floor(); x <= (cx + r).ceil(); x++) {
        if (!arena.inBounds(x, y)) return false;
        final i = arena.index(x, y);
        if (arena.owner[i] != 0 || arena.trail[i] != 0) return false;
      }
    }
    return true;
  }

  // ---- test helpers ----------------------------------------------------

  /// Teleports a player (tests / tutorial). Does not trigger cell logic.
  void debugPlace(SimPlayer p, double x, double y, double heading) {
    p
      ..x = x
      ..y = y
      ..cx = x.floor()
      ..cy = y.floor()
      ..heading = heading
      ..desiredHeading = heading;
  }

  /// Kills [p] as if [killerId] had done it (tests only).
  void debugKill(SimPlayer p, int killerId, DeathCause cause) => _kill(p, killerId, cause);

  /// Advances the simulation by [seconds] in fixed 1/60 s steps.
  void run(double seconds) {
    var t = 0.0;
    while (t < seconds && !isOver) {
      step(1 / 60);
      t += 1 / 60;
    }
  }
}
