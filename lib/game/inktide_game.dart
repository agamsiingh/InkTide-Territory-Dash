import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../services/feedback.dart';
import '../services/online_session.dart';
import '../services/progress_store.dart';
import 'arena_view.dart';
import 'bonus.dart';
import 'sim/levels.dart';
import 'sim/simulation.dart';
import 'sim/skins.dart';

class LeaderEntry {
  const LeaderEntry(this.name, this.percent, this.color, this.isHuman, this.rank);
  final String name;
  final double percent;
  final int color;
  final bool isHuman;
  final int rank;
}

/// Snapshot pushed to the Flutter HUD a few times per second.
class HudData {
  const HudData({
    this.percent = 0,
    this.target = 0,
    this.kills = 0,
    this.rank = 1,
    this.fps = 0,
    this.leaders = const [],
    this.trailWarning = false,
    this.power = 0,
    this.powersEnabled = false,
    this.alive = true,
    this.online = false,
    this.roomCode = '',
    this.players = 0,
    this.pingMs = 0,
    this.roundLeft = 0,
  });
  final double percent;
  final double target;
  final int kills;
  final int rank;
  final double fps;
  final List<LeaderEntry> leaders;
  final bool trailWarning;

  /// Ink Splash charge 0..1 (ready at 1).
  final double power;
  final bool powersEnabled;

  /// Is the local player in play (false while waiting to respawn online)?
  final bool alive;

  // Online rooms.
  final bool online;
  final String roomCode;
  final int players;
  final int pingMs;

  /// Seconds left in the online round (0 = unknown / not online).
  final int roundLeft;
}

/// bonusIntro: "100% BONUS GAME!" celebration; bonus: collecting loot;
/// bonusPaused: time ran out, waiting for Continue / No thanks.
enum MatchPhase { countdown, playing, ending, bonusIntro, bonus, bonusPaused, over }

/// Flame game: owns the simulation, camera and effects. Flutter widgets drive
/// input, HUD and menus around it.
class InkTideGame extends FlameGame {
  InkTideGame({
    required this.config,
    required this.store,
    required this.fx,
    this.seed,
    this.onMatchEnd,
    this.country = -1,
    this.onBonusIntro,
    this.onBonusTimeUp,
    this.bonusEnabled = true,
    this.online,
  });

  /// Live connection when this is an online match; the simulation is then the
  /// server's arena mirrored locally and nothing is stepped here.
  final OnlineSession? online;

  /// Called when a won match turns into the bonus round (show the intro,
  /// then call [beginBonus]).
  final VoidCallback? onBonusIntro;

  /// Called when bonus time runs out and a continue is still available
  /// (call [extendBonus] or [endBonus]).
  final VoidCallback? onBonusTimeUp;
  final bool bonusEnabled;

  BonusRound? bonus;

  /// Bumped whenever bonus loot or time changes (drives the bonus HUD).
  final ValueNotifier<int> bonusTick = ValueNotifier(0);
  int _coinCombo = 0;
  double _comboTimer = 0;

  final LevelConfig config;
  final ProgressStore store;
  final GameFeedback fx;
  final int? seed;

  /// Campaign country the match fills (-1 = none).
  final int country;
  final void Function(MatchResult result)? onMatchEnd;

  /// World pixels per cell.
  static const double cell = 32;

  late Simulation sim;
  late ArenaView view;
  MatchPhase phase = MatchPhase.countdown;
  final ValueNotifier<HudData> hud = ValueNotifier(const HudData());

  /// Increments ~4x/s so the minimap repaints cheaply.
  final ValueNotifier<int> minimapTick = ValueNotifier(0);

  double _hudTimer = 0;
  double _endTimer = 0;
  double _fps = 60;
  double _shake = 0;
  int _streak = 0;
  double _streakTimer = 0;
  final math.Random _fxRng = math.Random(7);

  // Cinematic state: eased zoom, punch-zoom, hit-stop, win flash, look-ahead.
  double _baseZoom = 1, _zoomMul = 1, _zoomTarget = 1;
  double _punch = 0, _punchAmp = 0;
  double _slowTimer = 0, _flash = 0, _tickTimer = 0;
  final Vector2 _camPos = Vector2.zero(), _look = Vector2.zero(), _camOut = Vector2.zero();

  /// For integration tests.
  static InkTideGame? current;

  @override
  Color backgroundColor() => const Color(0xFF3FC6EE); // open water around the island

  @override
  Future<void> onLoad() async {
    current = this;
    sim = online?.mirror ??
        (Simulation(
          config: config,
          seed: seed ?? DateTime.now().millisecondsSinceEpoch & 0x7fffffff,
          humanSkin: skinById(store.selectedSkin),
          speed: store.speed,
        )..powersEnabled = store.powersUnlocked);
    if (online != null) phase = MatchPhase.playing;
    view = ArenaView(this);
    world.add(view);
    camera.viewfinder.anchor = Anchor.center;
    _camPos.setFrom(_humanPos());
    camera.viewfinder.position = _camPos;
    camera.viewport.add(_FlashOverlay(this));
    _updateZoom();
    // HUD is pushed on the first update(); notifying here would mark the
    // sibling Hud dirty while GameWidget is still building.
    _hudTimer = 0;
  }

  Vector2 _humanPos() => Vector2(sim.human.x * cell, sim.human.y * cell);

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (isLoaded) _updateZoom();
  }

  void _updateZoom() {
    final shortSide = math.min(size.x, size.y);
    if (shortSide <= 0) return;
    // Show roughly 14 cells across the short side.
    _baseZoom = shortSide / (14 * cell);
    camera.viewfinder.zoom = _baseZoom * _zoomMul;
  }

  double get _punchMul {
    if (_punch <= 0) return 1;
    final t = 1 - _punch;
    final e = t < 0.2 ? math.sin(t / 0.2 * math.pi / 2) : math.pow(1 - (t - 0.2) / 0.8, 2).toDouble();
    return 1 + _punchAmp * e;
  }

  void startPlaying() {
    if (phase == MatchPhase.countdown) phase = MatchPhase.playing;
  }

  /// Steering input from the joystick (radians, screen space = world space).
  void steer(double angle) {
    sim.steerHuman(angle);
    online?.sendSteer(angle);
  }

  /// Double tap: fires the Ink Splash if charged.
  bool usePower() {
    if (online != null || phase != MatchPhase.playing) return false;
    final ok = sim.activatePower();
    if (ok) _handleEvents();
    return ok;
  }

  /// Turns the won match into the bonus round: rivals leave the island and
  /// coin stacks + gems appear on the player's territory.
  void _prepareBonus() {
    for (final p in sim.players) {
      sim.arena.clearTrail(p.id, p.trailCells);
      p
        ..trailCells.clear()
        ..trailPoints.clear();
      if (!p.isHuman && p.alive) {
        view.onSpawn(p); // puff as they leave
        p
          ..alive = false
          ..respawnIn = double.infinity;
      }
    }
    bonus = BonusRound(sim: sim, seed: sim.rng.nextInt(1 << 30));
    phase = MatchPhase.bonusIntro;
    _zoomTarget = 1.0;
    bonusTick.value++;
    if (onBonusIntro == null) {
      beginBonus();
    } else {
      onBonusIntro!();
    }
  }

  void beginBonus() {
    if (phase == MatchPhase.bonusIntro) phase = MatchPhase.bonus;
  }

  /// "+6s" continue (once). Returns false when it was already used.
  bool extendBonus() {
    final b = bonus;
    if (b == null || phase != MatchPhase.bonusPaused || !b.extend()) return false;
    phase = MatchPhase.bonus;
    bonusTick.value++;
    return true;
  }

  void endBonus() {
    if (phase != MatchPhase.bonus && phase != MatchPhase.bonusPaused && phase != MatchPhase.bonusIntro) return;
    phase = MatchPhase.over;
    bonusTick.value++;
    _finish();
  }

  void _updateBonus(double dt) {
    final b = bonus!;
    final taken = b.update(dt);
    if (_comboTimer > 0) {
      _comboTimer -= dt;
      if (_comboTimer <= 0) _coinCombo = 0;
    }
    for (final p in taken) {
      view.onPickup(p);
      if (p.kind == PickupKind.gem) {
        fx.play(Sfx.gem);
        view.floatText('+${p.value}', p.x, p.y - 1, 0xFFE58CFF);
      } else {
        _coinCombo++;
        _comboTimer = 0.6;
        fx.play(Sfx.coin, rate: 1 + math.min(_coinCombo, 12) * 0.04, volumeScale: 0.7);
        view.floatText('+${p.value}', p.x, p.y - 1, 0xFFFFE066);
      }
      fx.hapticLight();
    }
    if (taken.isNotEmpty || (b.timeLeft * 10).floor() != ((b.timeLeft + dt) * 10).floor()) bonusTick.value++;
    if (b.allCollected) {
      view.floatText('ALL COLLECTED!', sim.human.x, sim.human.y - 2.2, 0xFFFFFFFF, big: true);
      fx.play(Sfx.claim);
      endBonus();
    } else if (b.expired) {
      if (b.canExtend && onBonusTimeUp != null) {
        phase = MatchPhase.bonusPaused;
        bonusTick.value++;
        onBonusTimeUp!();
      } else {
        endBonus();
      }
    }
  }

  @override
  void update(double dt) {
    if (_slowTimer > 0) _slowTimer -= dt;
    final slow = _slowTimer > 0 ? 0.3 : 1.0;
    view.timeScale = slow;
    super.update(dt);
    if (dt > 0) _fps = _fps * 0.95 + (1 / dt) * 0.05;
    final step = math.min(dt, 1 / 30);
    if (online != null) {
      // The server runs the match: just smooth what it sent and show effects.
      online!.update(dt);
      _handleEvents();
      _trailTick(dt);
    } else if (phase == MatchPhase.playing) {
      sim.step(step * slow);
      _handleEvents();
      _trailTick(dt);
      if (sim.isOver) {
        phase = MatchPhase.ending;
        _endTimer = sim.won ? 0.9 : 1.4;
        if (sim.won) {
          fx.play(Sfx.win);
          fx.hapticHeavy();
          fx.duckMusic();
          _flash = 1;
          _zoomTarget = 1.3;
          view.celebrate(sim.human);
        } else {
          _zoomTarget = 1.15;
        }
      }
    } else if (phase == MatchPhase.ending) {
      _handleEvents();
      _endTimer -= dt;
      if (_endTimer <= 0) {
        if (sim.won && bonusEnabled) {
          _prepareBonus();
        } else {
          phase = MatchPhase.over;
          _finish();
        }
      }
    } else if (phase == MatchPhase.bonus) {
      // Real time (not the capped sim step) so the countdown matches the clock.
      _updateBonus(math.min(dt, 0.1));
    }
    if (_streakTimer > 0) {
      _streakTimer -= dt;
      if (_streakTimer <= 0) _streak = 0;
    }

    // Online the server never waits for a slow phone, so the camera must keep
    // up in real time (the solo cap of 1/30 s would let it fall behind).
    if (online != null && online!.hasSnapshot && !_camSnapped) {
      // First position from the server: jump there instead of easing in from the corner.
      _camSnapped = true;
      _camPos.setFrom(_humanPos());
    }
    _updateCamera(dt, online != null ? math.min(dt, 0.25) : step);

    _hudTimer -= dt;
    if (_hudTimer <= 0) {
      _hudTimer = 0.2;
      _pushHud();
      minimapTick.value++;
    }
  }

  bool _hadTrail = false;
  bool _wasOnWall = false;
  bool _camSnapped = false;

  void _trailTick(double dt) {
    final h = sim.human;
    // Soft thud the moment the player starts sliding along the arena edge.
    final wall = h.alive && h.onWall;
    if (wall && !_wasOnWall) {
      fx.play(Sfx.bump);
      fx.hapticLight();
    }
    _wasOnWall = wall;
    final has = h.alive && h.hasTrail;
    // Leaving home: whoosh once, then periodic ticks while the trail grows.
    if (has && !_hadTrail) fx.play(Sfx.trailStart);
    _hadTrail = has;
    if (!has) {
      _tickTimer = 0;
      return;
    }
    _tickTimer -= dt;
    if (_tickTimer > 0) return;
    _tickTimer = 0.35;
    fx.play(Sfx.trailTick, rate: 1 + math.min(h.trailCells.length / 70, 0.6));
  }

  /// Eased follow with heading look-ahead, shake, eased zoom and punch-zoom.
  void _updateCamera(double dt, double step) {
    final h = sim.human;
    final lk = 1 - math.pow(0.05, step).toDouble();
    final ahead = (phase == MatchPhase.playing || phase == MatchPhase.bonus) && h.alive ? cell * 1.1 : 0.0;
    _look.x += (math.cos(h.heading) * ahead - _look.x) * lk;
    _look.y += (math.sin(h.heading) * ahead - _look.y) * lk;
    final k = 1 - math.pow(0.0008, step).toDouble();
    _camPos.x += (h.x * cell + _look.x - _camPos.x) * k;
    _camPos.y += (h.y * cell + _look.y - _camPos.y) * k;
    _camOut.setFrom(_camPos);
    if (_shake > 0) {
      _shake = math.max(0, _shake - dt * 2.5);
      final m = _shake * 14;
      _camOut.x += (_fxRng.nextDouble() - 0.5) * m;
      _camOut.y += (_fxRng.nextDouble() - 0.5) * m;
    }
    camera.viewfinder.position = _camOut;
    if (_punch > 0) _punch = math.max(0, _punch - dt / 0.5);
    if (_flash > 0) _flash = math.max(0, _flash - dt * 1.8);
    _zoomMul += (_zoomTarget - _zoomMul) * (1 - math.pow(0.12, dt).toDouble());
    if (_baseZoom > 0) camera.viewfinder.zoom = _baseZoom * _zoomMul * _punchMul;
  }

  void _handleEvents() {
    final h = sim.human;
    for (final e in sim.drainEvents()) {
      if (e is CaptureEvent) {
          final p = sim.byId(e.playerId)!;
          view.onCapture(p, e.cells);
          if (p.isHuman) {
            final pct = e.cells * 100 / sim.arena.cellCount;
            fx.play(Sfx.capture,
                rate: (1.12 - pct * 0.035).clamp(0.8, 1.12).toDouble(),
                volumeScale: (0.75 + pct * 0.05).clamp(0.75, 1.0).toDouble());
            fx.hapticLight();
            view.floatText('+${pct.toStringAsFixed(1)}%', p.x, p.y - 1.2, p.skin.color);
            if (pct >= 4) {
              _punch = 1;
              _punchAmp = pct >= 8 ? 0.12 : 0.07;
              _shake = math.max(_shake, 0.3);
              fx.hapticHeavy();
              view.floatText(pct >= 8 ? 'INKREDIBLE!' : 'AWESOME!', p.x, p.y - 2.4, 0xFFFFFFFF, big: true);
            }
          }
      } else if (e is DeathEvent) {
          final v = sim.byId(e.victimId)!;
          view.onDeath(v, e.x, e.y);
          final bump = e.cause == DeathCause.border || e.cause == DeathCause.headOn;
          if (bump && (v.isHuman || e.killerId == h.id)) fx.play(Sfx.bump);
          if (v.isHuman) {
            fx.play(Sfx.death);
            fx.hapticHeavy();
            fx.duckMusic();
            _shake = 1;
            _slowTimer = 0.25;
          } else if (e.killerId == h.id) {
            _streak++;
            _streakTimer = 6;
            _slowTimer = 0.12;
            fx.play(Sfx.kill, rate: math.min(1 + (_streak - 1) * 0.12, 1.6));
            fx.hapticLight();
            final label = switch (_streak) {
              1 => 'SPLAT!',
              2 => 'DOUBLE SPLAT!',
              3 => 'UNSTOPPABLE!',
              _ => 'INK LEGEND!',
            };
            view.floatText(label, h.x, h.y - 2.0, 0xFFFFFFFF, big: true);
          }
      } else if (e is PowerEvent) {
          view.onPowerSplash(h, e.cells);
          fx.play(Sfx.power);
          fx.hapticHeavy();
          _shake = math.max(_shake, 0.45);
          _punch = 1;
          _punchAmp = 0.08;
          final pct = e.cells * 100 / sim.arena.cellCount;
          view.floatText('INK SPLASH! +${pct.toStringAsFixed(1)}%', h.x, h.y - 2.2, 0xFFFFFFFF, big: true);
      } else if (e is SpawnEvent) {
          final p = sim.byId(e.playerId)!;
          view.onSpawn(p);
      }
    }
  }

  void _pushHud() {
    final board = sim.leaderboard();
    final leaders = <LeaderEntry>[];
    var humanRank = board.indexOf(sim.human) + 1;
    for (var i = 0; i < board.length && i < 5; i++) {
      final p = board[i];
      leaders.add(LeaderEntry(p.name, sim.percentOf(p), p.skin.color, p.isHuman, i + 1));
    }
    if (humanRank > 5) {
      leaders.add(LeaderEntry(sim.human.name, sim.percentOf(sim.human),
          sim.human.skin.color, true, humanRank));
    }
    if (humanRank <= 0) humanRank = board.length;
    hud.value = HudData(
      percent: sim.humanScorePercent,
      target: config.targetPercent,
      kills: sim.human.kills,
      rank: humanRank,
      fps: _fps,
      leaders: leaders,
      trailWarning: online == null && sim.human.trailCells.length > 40,
      power: sim.humanPower,
      powersEnabled: sim.powersEnabled,
      alive: sim.human.alive,
      online: online != null,
      roomCode: online?.code ?? '',
      players: online?.playerCount ?? 0,
      pingMs: online?.pingMs ?? 0,
      roundLeft: online?.roundLeft ?? 0,
    );
  }

  void _finish() {
    fx.restoreMusic();
    onMatchEnd?.call(MatchResult(
      level: config.level,
      won: sim.won,
      percent: sim.humanScorePercent,
      kills: sim.human.kills,
      seconds: sim.time,
      country: country,
      bonusCoins: bonus?.coins ?? 0,
      bonusGems: bonus?.gems ?? 0,
    ));
  }

  @override
  void onRemove() {
    if (current == this) current = null;
    fx.restoreMusic();
    super.onRemove();
  }
}

/// Screen-space white flash (win), drawn above the world.
class _FlashOverlay extends Component {
  _FlashOverlay(this.game);
  final InkTideGame game;
  final Paint _paint = Paint();

  @override
  void render(Canvas canvas) {
    final a = game._flash;
    if (a <= 0) return;
    _paint.color = Color.fromARGB((a * a * 210).round(), 255, 255, 255);
    canvas.drawRect(Rect.fromLTWH(0, 0, game.size.x, game.size.y), _paint);
  }
}
