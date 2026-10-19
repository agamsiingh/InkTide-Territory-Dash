import 'dart:async';
import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../../app.dart';
import '../../game/inktide_game.dart';
import '../../game/sim/levels.dart';
import '../../game/sim/skins.dart';
import '../../game/world.dart';
import '../../services/feedback.dart';
import '../../services/online_session.dart';
import '../../services/progress_store.dart';
import '../blob_painter.dart';
import '../flags.dart';
import '../palette.dart';
import '../widgets.dart';
import 'bonus_screens.dart';
import 'capsule_screen.dart';
import 'hud.dart';
import 'menu_screen.dart';
import 'tutorial.dart';

enum _Overlay { none, tutorial, powersIntro, countdown, paused, bonusIntro, bonusContinue, bonusSummary, results, disconnected }

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.level, this.seed, this.country, this.online});
  final int level;
  final int? seed;

  /// A joined online match (the server runs it); null for solo play.
  final OnlineSession? online;

  /// Campaign country index; defaults to the selected country.
  final int? country;

  @override
  State<GameScreen> createState() => GameScreenState();
}

class GameScreenState extends State<GameScreen> with WidgetsBindingObserver {
  InkTideGame? game;
  _Overlay _overlay = _Overlay.none;
  int _count = 3;
  Timer? _countTimer;
  MatchResult? _result;
  MatchRewards? _rewards;
  int _coinsBefore = 0;
  double _bestBefore = 0;

  /// Bonus payout after the multiplier: (multiplier, coins, gems).
  (int, int, int)? _bonusPaid;

  // Online play.
  OnlineSession? get _online => widget.online;
  Timer? _awayTimer;
  bool _leftOnline = false;

  // Joystick.
  final ValueNotifier<(Offset, Offset)?> _stick = ValueNotifier(null);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (game != null) return;
    final s = Services.of(context);
    final online = widget.online;
    if (online != null) {
      online.addListener(_onOnlineChanged);
      game = InkTideGame(
        config: LevelConfig(
            level: 1,
            arenaSize: online.mirror!.arena.width,
            bots: 0,
            targetPercent: 25,
            botSkill: 0.7),
        store: s.store,
        fx: s.fx,
        online: online,
        bonusEnabled: false,
      );
      // No tutorial or countdown online: the arena is already live.
      _overlay = _Overlay.none;
      return;
    }
    game = InkTideGame(
      config: LevelConfig.forLevel(widget.level),
      store: s.store,
      fx: s.fx,
      seed: widget.seed,
      country: widget.country ?? s.store.selectedCountry,
      onMatchEnd: _onMatchEnd,
      onBonusIntro: () => setState(() => _overlay = _Overlay.bonusIntro),
      onBonusTimeUp: () => setState(() => _overlay = _Overlay.bonusContinue),
    );
    if (s.store.tutorialSeen) {
      _afterTutorial();
    } else {
      _overlay = _Overlay.tutorial;
    }
  }

  /// Powers explainer once (when they unlock), then the countdown.
  void _afterTutorial() {
    final store = Services.of(context).store;
    if (store.powersUnlocked && !store.powersIntroSeen) {
      _overlay = _Overlay.powersIntro;
    } else {
      _startCountdown();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _countTimer?.cancel();
    _awayTimer?.cancel();
    _online?.removeListener(_onOnlineChanged);
    // Backing out of the screen must also leave the room.
    if (_online != null && _online!.state != OnlineState.closed) _online!.leave();
    _stick.dispose();
    super.dispose();
  }

  void _onOnlineChanged() {
    final o = _online;
    if (o == null || !mounted || _leftOnline) return;
    if (o.state == OnlineState.closed && o.lostReason != null && _overlay != _Overlay.disconnected) {
      setState(() => _overlay = _Overlay.disconnected);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final fx = Services.of(context).fx;
    if (_online != null) {
      // The world keeps going on the server, so there is nothing to pause.
      // Away for more than 20 s: leave quietly instead of leaving a ghost
      // cube driving into walls.
      if (state == AppLifecycleState.resumed) {
        fx.resumeMusic();
        _awayTimer?.cancel();
      } else {
        fx.pauseMusic();
        _awayTimer ??= Timer(const Duration(seconds: 20), () {
          _awayTimer = null;
          if (!_leftOnline) unawaited(_online?.leave());
          if (mounted && !_leftOnline) setState(() => _overlay = _Overlay.disconnected);
        });
      }
      if (state == AppLifecycleState.resumed) _awayTimer = null;
      return;
    }
    if (state == AppLifecycleState.resumed) {
      fx.resumeMusic();
      if (_overlay == _Overlay.countdown && !(_countTimer?.isActive ?? false)) {
        setState(_startCountdown);
      }
    } else {
      fx.pauseMusic();
      if (game?.phase == MatchPhase.bonus && _overlay == _Overlay.none) {
        // Bonus time must not run out while the app is in the background.
        game!.pauseEngine();
        setState(() => _overlay = _Overlay.paused);
        return;
      }
      if (_overlay == _Overlay.countdown && game?.phase == MatchPhase.countdown) {
        _countTimer?.cancel();
      } else if (game?.phase == MatchPhase.playing &&
          (_overlay == _Overlay.none || _overlay == _Overlay.countdown)) {
        pause();
      }
    }
  }

  void _startCountdown() {
    _overlay = _Overlay.countdown;
    _count = 3;
    final fx = Services.of(context).fx;
    fx.play(Sfx.countdown);
    _countTimer?.cancel();
    _countTimer = Timer.periodic(const Duration(milliseconds: 650), (t) {
      if (!mounted) return t.cancel();
      setState(() => _count--);
      if (_count > 0) {
        // Rising pitch builds tension toward GO.
        fx.play(Sfx.countdown, rate: 1 + (3 - _count) * 0.09);
      } else if (_count == 0) {
        fx.play(Sfx.go);
        game?.startPlaying();
      } else {
        t.cancel();
        setState(() {
          if (_overlay == _Overlay.countdown) _overlay = _Overlay.none;
        });
      }
    });
  }

  void pause() {
    if (game == null || game!.phase != MatchPhase.playing) return;
    if (_online != null) {
      // Online the match cannot be frozen: this just opens the Leave menu.
      Services.of(context).fx.tap();
      setState(() => _overlay = _Overlay.paused);
      return;
    }
    game!.pauseEngine();
    Services.of(context).fx.tap();
    setState(() => _overlay = _Overlay.paused);
  }

  /// Leaves the online room, pays out what the player earned and shows the results.
  Future<void> _leaveOnline() async {
    final o = _online;
    if (o == null || _leftOnline) return;
    _leftOnline = true;
    final s = Services.of(context);
    s.fx.tap();
    final result = MatchResult(
      level: s.store.level,
      won: false,
      percent: o.bestPercent,
      kills: o.kills,
      seconds: o.seconds,
    );
    await o.leave();
    _coinsBefore = s.store.coins;
    _bestBefore = s.store.bestPercent;
    final rewards = await s.store.recordMatch(result);
    // Winning a round online is worth a bonus on top.
    if (o.roundWins > 0) await s.store.update((st) => st.coins += 100 * o.roundWins);
    unawaited(s.reminders.requestPermissionOnce());
    if (!mounted) return;
    setState(() {
      _result = result;
      _rewards = rewards;
      _overlay = _Overlay.results;
    });
    _showCapsules();
  }

  void resume() {
    if (_online != null) {
      Services.of(context).fx.tap();
      setState(() => _overlay = _Overlay.none);
      return;
    }
    game?.resumeEngine();
    if (game?.phase == MatchPhase.bonus) {
      setState(() => _overlay = _Overlay.none);
      return;
    }
    Services.of(context).fx.tap();
    setState(() => _overlay = _Overlay.none);
  }

  Future<void> _onMatchEnd(MatchResult r) async {
    final s = Services.of(context);
    _coinsBefore = s.store.coins;
    _bestBefore = s.store.bestPercent;
    final rewards = await s.store.recordMatch(r);
    // First finished match: a friendly moment to ask about reminders.
    unawaited(s.reminders.requestPermissionOnce());
    if (!r.won) s.fx.play(Sfx.lose);
    if (!mounted) return;
    final loot = rewards.bonusCoins > 0 || rewards.bonusGems > 0;
    setState(() {
      _result = r;
      _rewards = rewards;
      _overlay = loot ? _Overlay.bonusSummary : _Overlay.results;
    });
    if (!loot) _showCapsules();
  }

  /// Opens a capsule for each skin this match unlocked.
  void _showCapsules() {
    final skins = _rewards?.unlockedSkins ?? const [];
    if (skins.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) CapsuleScreen.show(context, skins);
    });
  }

  void _restart({int? level}) {
    Services.of(context).fx.tap();
    final country = level == null ? game?.country : null;
    Navigator.of(context).pushReplacement(fadeRoute(GameScreen(level: level ?? widget.level, country: country)));
  }

  void _home() {
    Services.of(context).fx.tap();
    if (_online != null) {
      Navigator.of(context).popUntil((r) => r.isFirst);
      return;
    }
    Navigator.of(context).pop();
  }

  void _onPanStart(DragStartDetails d) => _stick.value = (d.localPosition, d.localPosition);

  void _onPanUpdate(DragUpdateDetails d) {
    final cur = _stick.value;
    final origin = cur?.$1 ?? d.localPosition;
    var delta = d.localPosition - origin;
    // Let the base follow the finger so direction changes stay responsive.
    const maxR = 56.0;
    var o = origin;
    if (delta.distance > maxR) {
      o = d.localPosition - delta / delta.distance * maxR;
      delta = d.localPosition - o;
    }
    _stick.value = (o, d.localPosition);
    if (delta.distance > 6) game?.steer(math.atan2(delta.dy, delta.dx));
  }

  void _onPanEnd([DragEndDetails? _]) => _stick.value = null;

  @override
  Widget build(BuildContext context) {
    final g = game!;
    final store = Services.of(context).store;
    return PopScope(
      canPop: _overlay != _Overlay.none,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) pause();
      },
      child: Scaffold(
        backgroundColor: const Color(Palette.sky),
        body: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              key: const Key('gameSurface'),
              behavior: HitTestBehavior.opaque,
              onPanStart: _onPanStart,
              onPanUpdate: _onPanUpdate,
              onPanEnd: _onPanEnd,
              onPanCancel: _onPanEnd,
              onDoubleTap: () => g.usePower(),
              child: GameWidget(game: g),
            ),
            IgnorePointer(
              child: RepaintBoundary(
                child: ValueListenableBuilder<(Offset, Offset)?>(
                  valueListenable: _stick,
                  builder: (context, v, child) => CustomPaint(painter: _StickPainter(v), size: Size.infinite),
                ),
              ),
            ),
            SafeArea(
              child: switch (g.phase) {
                MatchPhase.bonusIntro || MatchPhase.bonus || MatchPhase.bonusPaused => Align(
                    alignment: Alignment.topCenter,
                    child: BonusHud(game: g),
                  ),
                _ => Hud(
                    game: g,
                    showFps: store.showFps,
                    onPause: pause,
                  ),
              },
            ),
            if (_online != null && _overlay == _Overlay.none) _RespawnBanner(game: g),
            if (_online != null) _RoundBanner(session: _online!),
            if (_overlay != _Overlay.none) _buildOverlay(context, g),
          ],
        ),
      ),
    );
  }

  Widget _buildOverlay(BuildContext context, InkTideGame g) {
    switch (_overlay) {
      case _Overlay.none:
        return const SizedBox.shrink();
      case _Overlay.tutorial:
        return _Dim(
          child: TutorialCard(onDone: () {
            Services.of(context).store.update((s) => s.tutorialSeen = true);
            setState(_afterTutorial);
          }),
        );
      case _Overlay.powersIntro:
        return PowersIntroCard(
          // The game may not have loaded yet, so use the stored skin.
          skin: skinById(Services.of(context).store.selectedSkin),
          onDone: () {
            Services.of(context).fx.tap();
            Services.of(context).store.update((s) => s.powersIntroSeen = true);
            setState(_startCountdown);
          },
        );
      case _Overlay.bonusIntro:
        return BonusIntro(onDone: () {
          g.beginBonus();
          setState(() => _overlay = _Overlay.none);
        });
      case _Overlay.bonusContinue:
        return ColoredBox(
          color: fade(Palette.ink, 0.45),
          child: Center(
            child: SingleChildScrollView(
              child: ContinueBonusCard(
                onContinue: () {
                  Services.of(context).fx.play(Sfx.claim);
                  g.extendBonus();
                  setState(() => _overlay = _Overlay.none);
                },
                onDecline: () {
                  Services.of(context).fx.tap();
                  setState(() => _overlay = _Overlay.none);
                  g.endBonus();
                },
              ),
            ),
          ),
        );
      case _Overlay.bonusSummary:
        return RewardSummary(
          coins: _rewards!.bonusCoins,
          gems: _rewards!.bonusGems,
          onClaimed: (m, c, gm) {
            setState(() {
              _bonusPaid = (m, c, gm);
              _overlay = _Overlay.results;
            });
            _showCapsules();
          },
        );
      case _Overlay.countdown:
        return IgnorePointer(child: Center(child: _CountdownBeat(key: ValueKey(_count), count: _count)));
      case _Overlay.disconnected:
        return _Dim(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: GamePanel(
              key: const Key('disconnectedPanel'),
              title: 'DISCONNECTED',
              headerColor: Palette.pink,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(_online?.lostReason?.message ?? 'You left the match.', textAlign: TextAlign.center, style: bodyStyle(17)),
                const SizedBox(height: 16),
                ChunkyButton(
                    key: const Key('disconnectedBack'),
                    label: 'BACK',
                    icon: Icons.arrow_back_rounded,
                    width: double.infinity,
                    onTap: () {
                      Services.of(context).fx.tap();
                      Navigator.of(context).pop();
                    }),
              ]),
            ),
          ),
        );
      case _Overlay.paused:
        if (_online != null) {
          return _Dim(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: GamePanel(
                key: const Key('onlineMenu'),
                title: 'ONLINE',
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('Room ${_online!.code}  •  ${_online!.humanCount} real players',
                      style: bodyStyle(17)),
                  const SizedBox(height: 4),
                  Text('The match keeps going while this is open.',
                      textAlign: TextAlign.center, style: bodyStyle(13, color: const Color(0xFF6A7393))),
                  const SizedBox(height: 16),
                  ChunkyButton(
                      key: const Key('resumeButton'),
                      label: 'BACK TO FIGHT',
                      icon: Icons.play_arrow_rounded,
                      width: double.infinity,
                      fontSize: 22,
                      onTap: resume),
                  const SizedBox(height: 12),
                  ChunkyButton(
                      key: const Key('leaveOnlineButton'),
                      label: 'LEAVE',
                      icon: Icons.logout_rounded,
                      color: Palette.pink,
                      dark: 0xFFC92A7A,
                      width: double.infinity,
                      height: 54,
                      fontSize: 20,
                      onTap: _leaveOnline),
                ]),
              ),
            ),
          );
        }
        return _Dim(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: GamePanel(
              title: 'PAUSED',
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('Level ${g.config.level}  •  Goal ${g.config.targetPercent.toStringAsFixed(0)}%',
                    style: bodyStyle(17)),
                const SizedBox(height: 16),
                ChunkyButton(
                    key: const Key('resumeButton'),
                    label: 'RESUME',
                    icon: Icons.play_arrow_rounded,
                    width: double.infinity,
                    onTap: resume),
                const SizedBox(height: 12),
                ChunkyButton(
                    key: const Key('restartButton'),
                    label: 'RESTART',
                    icon: Icons.refresh_rounded,
                    color: Palette.cyan,
                    dark: 0xFF1474C9,
                    width: double.infinity,
                    height: 54,
                    fontSize: 20,
                    onTap: () => _restart()),
                const SizedBox(height: 12),
                ChunkyButton(
                    key: const Key('quitButton'),
                    label: 'MENU',
                    icon: Icons.home_rounded,
                    color: Palette.pink,
                    dark: 0xFFC92A7A,
                    width: double.infinity,
                    height: 54,
                    fontSize: 20,
                    onTap: _home),
              ]),
            ),
          ),
        );
      case _Overlay.results:
        final store = Services.of(context).store;
        return _Dim(
          child: _ResultsPanel(
            result: _result!,
            skin: g.sim.human.skin,
            rewards: _rewards!,
            coinsBefore: _coinsBefore,
            bestBefore: _bestBefore,
            bonusPaid: _bonusPaid,
            online: _online != null,
            onNext: () => _restart(level: store.level),
            onRetry: _online != null
                ? () {
                    Services.of(context).fx.tap();
                    Navigator.of(context).pop();
                  }
                : () => _restart(),
            onHome: _home,
          ),
        );
    }
  }
}

/// Countdown number: slams in from large with a shock ring.
class _CountdownBeat extends StatelessWidget {
  const _CountdownBeat({super.key, required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final go = count <= 0;
    final text = Text(
      go ? 'GO!' : '$count',
      style: kTitle.copyWith(
        fontSize: go ? 112 : 96,
        color: Color(go ? Palette.gold : Palette.white),
        shadows: const [Shadow(color: Color(Palette.ink), offset: Offset(0, 6))],
      ),
    );
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: motion(context, const Duration(milliseconds: 460)),
      builder: (_, t, child) {
        final e = Curves.easeOutBack.transform(t);
        return CustomPaint(
          painter: _RingPainter(t, go ? Palette.gold : Palette.white),
          child: Opacity(
            opacity: math.min(1.0, t * 4),
            child: Transform.rotate(
              angle: (1 - e) * (go ? 0.2 : -0.3),
              child: Transform.scale(scale: 2.6 - 1.6 * e, child: child),
            ),
          ),
        );
      },
      child: text,
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.t, this.color);
  final double t;
  final int color;
  static final Paint _p = Paint()..style = PaintingStyle.stroke;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || t >= 1) return;
    final k = 1 - t;
    _p
      ..strokeWidth = 4 + 14 * k
      ..color = fade(color, 0.7 * k);
    canvas.drawCircle(size.center(Offset.zero), 40 + 150 * Curves.easeOutCubic.transform(t), _p);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.t != t || old.color != color;
}

/// End-of-match card: staggered reveal, count-up stats and a confetti pop on wins.
class _ResultsPanel extends StatefulWidget {
  const _ResultsPanel({
    required this.result,
    required this.skin,
    required this.rewards,
    required this.coinsBefore,
    required this.bestBefore,
    this.bonusPaid,
    this.online = false,
    required this.onNext,
    required this.onRetry,
    required this.onHome,
  });
  final MatchResult result;
  final Skin skin;
  final MatchRewards rewards;
  final int coinsBefore;
  final double bestBefore;
  final (int, int, int)? bonusPaid;
  final bool online;
  final VoidCallback onNext;
  final VoidCallback onRetry;
  final VoidCallback onHome;

  @override
  State<_ResultsPanel> createState() => _ResultsPanelState();
}

class _ResultsPanelState extends State<_ResultsPanel> with TickerProviderStateMixin {
  // Buttons finish entering by ~400 ms so they are tappable right away.
  late final AnimationController _intro =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
  late final AnimationController _confetti =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
  late final TickerClock _clock = TickerClock(this);
  bool _started = false;
  final List<Timer> _sfx = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _scheduleSounds();
    if (reduceMotion(context)) {
      _intro.value = 1;
      return;
    }
    _intro.forward();
    _clock.start();
    if (widget.result.won || widget.rewards.countryCompleted) _confetti.forward();
  }

  /// Coin ticks while the total counts up, then rank-up, awards and unlocks.
  void _scheduleSounds() {
    final fx = Services.of(context).fx;
    final rw = widget.rewards;
    void at(int ms, VoidCallback f) => _sfx.add(Timer(Duration(milliseconds: ms), f));
    if (rw.totalCoins > 0) {
      for (var i = 0; i < 5; i++) {
        at(320 + i * 130, () => fx.play(Sfx.coin, rate: 1 + i * 0.06, volumeScale: 0.8));
      }
    }
    var t = 1050;
    if (rw.countryCompleted) {
      at(t, () {
        fx.play(Sfx.countryComplete);
        fx.hapticHeavy();
      });
      t += 1300;
    }
    if (rw.rankedUp) {
      at(t, () {
        fx.play(Sfx.levelUp);
        fx.hapticLight();
      });
      t += 650;
    }
    if (rw.achievements.isNotEmpty) {
      at(t, () => fx.play(Sfx.achievement));
      t += 650;
    }
    if (rw.unlockedSkins.isNotEmpty) at(t, () => fx.play(Sfx.unlock));
  }

  @override
  void dispose() {
    for (final t in _sfx) {
      t.cancel();
    }
    _intro.dispose();
    _confetti.dispose();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    final rw = widget.rewards;
    final store = Services.of(context).store;
    final count = motion(context, const Duration(milliseconds: 900));
    Widget enter(double start, double end, Widget child,
            {Offset offset = const Offset(0, 18), double scale = 1, Curve curve = Curves.easeOutCubic}) =>
        StaggerIn(
            animation: _intro, start: start, end: end, offset: offset, scale: scale, curve: curve, child: child);
    final panel = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: GamePanel(
        key: const Key('resultsPanel'),
        title: widget.online ? 'GOOD FIGHT!' : (r.won ? 'VICTORY!' : 'SPLAT!'),
        headerColor: widget.online ? Palette.cyan : (r.won ? Palette.green : Palette.pink),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          enter(
            0,
            0.6,
            offset: r.won ? Offset.zero : const Offset(-36, 0),
            scale: r.won ? 0.2 : 1,
            curve: Curves.elasticOut,
            BlobAvatar(
              skin: widget.skin,
              size: 90,
              mood: r.won ? Mood.excited : Mood.dizzy,
              time: _clock.time,
              seed: 3,
            ),
          ),
          enter(
            0.1,
            0.5,
            Text(
              widget.online
                  ? 'Best: ${r.percent.toStringAsFixed(1)}% of the arena'
                  : (r.won ? 'Level ${r.level} cleared!' : 'Better luck next splash!'),
              style: bodyStyle(18),
            ),
          ),
          const SizedBox(height: 10),
          enter(
            0.18,
            0.58,
            Row(children: [
              _ResultStat('Territory', r.percent, (v) => '${v.toStringAsFixed(1)}%', count),
              _ResultStat('Splats', r.kills.toDouble(), (v) => '${v.round()}', count),
              _ResultStat('Time', r.seconds.floorToDouble(), (v) => '${v.floor()}s', count),
            ]),
          ),
          const SizedBox(height: 10),
          enter(
            0.26,
            0.62,
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: rw.totalCoins.toDouble()),
              duration: count,
              curve: Curves.easeOutCubic,
              builder: (context, v, child) => StatPill(
                  key: const Key('resultCoins'),
                  icon: Icons.monetization_on_rounded,
                  value: '+${v.round()}  (${widget.coinsBefore + v.round()})'),
            ),
          ),
          const SizedBox(height: 10),
          enter(
            0.3,
            0.66,
            Column(children: [
              Text('+${rw.xp} XP', key: const Key('resultXp'), style: kTitle.copyWith(fontSize: 18, color: const Color(0xFFF29A1F), shadows: [])),
              const SizedBox(height: 4),
              DecoratedBox(
                decoration: BoxDecoration(color: const Color(Palette.skyDeep), borderRadius: BorderRadius.circular(14)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: RankBar(rank: store.rank, xp: store.rankXp, needed: store.rankXpNeeded, width: 240),
                ),
              ),
            ]),
          ),
          if (rw.country >= 0) ...[
            const SizedBox(height: 10),
            enter(
              0.34,
              0.7,
              _CountryProgress(rewards: rw, duration: count),
            ),
          ],
          if (widget.bonusPaid != null) ...[
            const SizedBox(height: 6),
            enter(
              0.36,
              0.7,
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.star_rounded, color: Color(0xFFF29A1F), size: 22),
                Flexible(
                  child: Text(
                      ' Bonus: +${widget.bonusPaid!.$2} coins'
                      '${widget.bonusPaid!.$3 > 0 ? '  +${widget.bonusPaid!.$3} gems' : ''}'
                      '${widget.bonusPaid!.$1 > 1 ? '  (x${widget.bonusPaid!.$1})' : ''}',
                      key: const Key('resultBonus'),
                      style: kTitle.copyWith(fontSize: 16, color: const Color(0xFFE08A00), shadows: [])),
                ),
              ]),
            ),
          ],
          if (rw.eventTokens > 0) ...[
            const SizedBox(height: 6),
            enter(
              0.38,
              0.72,
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.water_drop_rounded, color: Color(0xFF9B5CFF), size: 20),
                Text(' +${rw.eventTokens} ink drops',
                    key: const Key('resultTokens'),
                    style: kTitle.copyWith(fontSize: 16, color: const Color(0xFF7A46E8), shadows: [])),
              ]),
            ),
          ],
          if (rw.rankedUp) ...[
            const SizedBox(height: 6),
            enter(
              0.5,
              1,
              offset: Offset.zero,
              scale: 0.3,
              curve: Curves.elasticOut,
              Text('RANK UP! Rank ${rw.rankAfter}  +${rw.rankCoins}',
                  key: const Key('rankUpBanner'),
                  style: kTitle.copyWith(fontSize: 20, color: const Color(0xFFF29A1F), shadows: [])),
            ),
          ],
          if (r.percent > widget.bestBefore) ...[
            const SizedBox(height: 6),
            enter(
              0.45,
              1,
              offset: Offset.zero,
              scale: 0.3,
              curve: Curves.elasticOut,
              Text('NEW BEST!', style: kTitle.copyWith(fontSize: 20, color: const Color(Palette.yellow))),
            ),
          ],
          for (final a in rw.achievements) ...[
            const SizedBox(height: 6),
            enter(
              0.55,
              1,
              offset: Offset.zero,
              scale: 0.5,
              curve: Curves.easeOutBack,
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.emoji_events_rounded, color: Color(0xFFF29A1F), size: 22),
                const SizedBox(width: 4),
                Flexible(
                  child: Text('${a.title}  +${a.reward}',
                      style: kTitle.copyWith(fontSize: 17, color: const Color(Palette.ink), shadows: [])),
                ),
              ]),
            ),
          ],
          for (final s in rw.unlockedSkins) ...[
            const SizedBox(height: 6),
            enter(
              0.6,
              1,
              offset: Offset.zero,
              scale: 0.5,
              curve: Curves.easeOutBack,
              Text('Unlocked skin: ${s.name}!',
                  style: kTitle.copyWith(fontSize: 18, color: const Color(Palette.purple), shadows: [])),
            ),
          ],
          const SizedBox(height: 16),
          enter(
            0.22,
            0.52,
            offset: const Offset(0, 30),
            r.won && !widget.online
                ? ChunkyButton(
                    key: const Key('nextLevelButton'),
                    label: 'NEXT LEVEL',
                    icon: Icons.arrow_forward_rounded,
                    width: double.infinity,
                    onTap: widget.onNext,
                  )
                : ChunkyButton(
                    key: const Key('retryButton'),
                    label: widget.online ? 'PLAY AGAIN' : 'TRY AGAIN',
                    icon: Icons.refresh_rounded,
                    width: double.infinity,
                    onTap: widget.onRetry,
                  ),
          ),
          const SizedBox(height: 12),
          enter(
            0.28,
            0.58,
            offset: const Offset(0, 30),
            ChunkyButton(
              key: const Key('homeButton'),
              label: 'MENU',
              icon: Icons.home_rounded,
              color: Palette.cyan,
              dark: 0xFF1474C9,
              width: double.infinity,
              height: 54,
              fontSize: 20,
              onTap: widget.onHome,
            ),
          ),
        ]),
      ),
    );
    if (!r.won && !rw.countryCompleted) return panel;
    return Stack(clipBehavior: Clip.none, children: [
      panel,
      Positioned.fill(
        child: IgnorePointer(
          child: RepaintBoundary(child: CustomPaint(painter: _ConfettiPainter(_confetti, widget.skin.color))),
        ),
      ),
    ]);
  }
}

class _ResultStat extends StatelessWidget {
  const _ResultStat(this.label, this.value, this.format, this.duration);
  final String label;
  final double value;
  final String Function(double) format;
  final Duration duration;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: value),
            duration: duration,
            curve: Curves.easeOutCubic,
            builder: (_, v, __) => Text(format(v),
                style: kTitle.copyWith(fontSize: 24, color: const Color(Palette.ink), shadows: [])),
          ),
          Text(label, style: bodyStyle(13, color: const Color(0xFF6A7393))),
        ]),
      );
}

/// One-shot confetti burst from the avatar; fixed piece count, no allocations per frame.
class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.anim, this.skinColor) : super(repaint: anim);
  final Animation<double> anim;
  final int skinColor;

  static const _n = 40;
  static final List<double> _pieces = () {
    final rnd = math.Random(11);
    return [
      for (var i = 0; i < _n; i++) ...[
        -math.pi / 2 + (rnd.nextDouble() - 0.5) * math.pi * 1.5, // angle
        260 + rnd.nextDouble() * 320, // speed px/s
        (rnd.nextDouble() - 0.5) * 16, // spin rad/s
        5 + rnd.nextDouble() * 6, // size
      ],
    ];
  }();
  static const _colors = [Palette.yellow, Palette.pink, Palette.cyan, Palette.green, Palette.purple, Palette.gold];
  static final Paint _p = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    final t = anim.value;
    if (t <= 0 || t >= 1) return;
    final sec = t * 1.6;
    final drag = (1 - math.exp(-2.2 * sec)) / 2.2;
    final alpha = 1 - t * t;
    final ox = size.width / 2, oy = 110.0;
    for (var i = 0; i < _n; i++) {
      final a = _pieces[i * 4], v = _pieces[i * 4 + 1], spin = _pieces[i * 4 + 2], s = _pieces[i * 4 + 3];
      final x = ox + math.cos(a) * v * drag;
      final y = oy + math.sin(a) * v * drag + 420 * sec * sec * 0.5;
      _p.color = fade(i % 5 == 0 ? skinColor : _colors[i % _colors.length], alpha);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(spin * sec + i);
      canvas.drawRect(Rect.fromLTWH(-s / 2, -s * 0.3, s, s * 0.6), _p);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) => old.anim != anim || old.skinColor != skinColor;
}

class _Dim extends StatelessWidget {
  const _Dim({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: motion(context, const Duration(milliseconds: 260)),
      builder: (_, t, c) => ColoredBox(
        color: fade(Palette.ink, 0.55 * t),
        child: Transform.scale(
            scale: 0.88 + 0.12 * Curves.easeOutBack.transform(t), child: Opacity(opacity: t, child: c)),
      ),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: child,
        ),
      ),
    );
  }
}

class _StickPainter extends CustomPainter {
  _StickPainter(this.v);
  final (Offset, Offset)? v;
  static final Paint _base = Paint()..color = fade(Palette.white, 0.25);
  static final Paint _rim = Paint()
    ..color = fade(Palette.white, 0.6)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3;
  static final Paint _knob = Paint()..color = fade(Palette.white, 0.85);

  @override
  void paint(Canvas canvas, Size size) {
    final s = v;
    if (s == null) return;
    canvas.drawCircle(s.$1, 56, _base);
    canvas.drawCircle(s.$1, 56, _rim);
    canvas.drawCircle(s.$2, 26, _knob);
  }

  @override
  bool shouldRepaint(covariant _StickPainter old) => old.v != v;
}

/// Country fill before -> after, plus the completion banner and reward.
class _CountryProgress extends StatelessWidget {
  const _CountryProgress({required this.rewards, required this.duration});
  final MatchRewards rewards;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final rw = rewards;
    final def = kCountries[rw.country];
    return Container(
      key: const Key('resultCountry'),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(color: const Color(0xFFEAF6FF), borderRadius: BorderRadius.circular(16)),
      child: Column(children: [
        Row(children: [
          FlagIcon(iso: def.iso, width: 34),
          const SizedBox(width: 8),
          Expanded(
            child: Text(def.name, style: kTitle.copyWith(fontSize: 18, color: const Color(Palette.ink), shadows: [])),
          ),
          Text('+${(rw.countryAfter - rw.countryBefore).toStringAsFixed(0)}%',
              style: kTitle.copyWith(fontSize: 18, color: const Color(0xFF1F9440), shadows: [])),
        ]),
        const SizedBox(height: 6),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: rw.countryBefore, end: rw.countryAfter),
          duration: duration * 1.3,
          curve: Curves.easeOutCubic,
          builder: (_, v, __) => Row(children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: v / 100,
                  minHeight: 12,
                  backgroundColor: const Color(0xFFD3DDE7),
                  color: const Color(0xFF33C759),
                ),
              ),
            ),
            SizedBox(
              width: 48,
              child: Text('${v.toStringAsFixed(0)}%',
                  textAlign: TextAlign.right, style: bodyStyle(14, color: const Color(Palette.ink))),
            ),
          ]),
        ),
        if (rw.countryCompleted) ...[
          const SizedBox(height: 6),
          Text('${def.name.toUpperCase()} COMPLETE!',
              key: const Key('countryComplete'),
              textAlign: TextAlign.center,
              style: kTitle.copyWith(fontSize: 20, color: const Color(0xFF1F9440), shadows: [])),
          Text('+${rw.countryCoins} coins  +${rw.countryGems} gems'
              '${rw.country + 1 < kCountries.length ? '  •  ${kCountries[rw.country + 1].name} unlocked!' : ''}',
              textAlign: TextAlign.center,
              style: bodyStyle(13, color: const Color(Palette.ink))),
        ],
      ]),
    );
  }
}


/// "SPLATTED! Respawning..." shown over the arena while the local player waits
/// to come back in an online match (the world keeps running behind it).
class _RespawnBanner extends StatelessWidget {
  const _RespawnBanner({required this.game});
  final InkTideGame game;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<HudData>(
        valueListenable: game.hud,
        builder: (context, h, _) {
          if (h.alive) return const SizedBox.shrink();
          return IgnorePointer(
            child: Center(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.6, end: 1),
                duration: motion(context, const Duration(milliseconds: 350)),
                curve: Curves.easeOutBack,
                builder: (_, t, child) => Transform.scale(scale: t, child: Opacity(opacity: t.clamp(0.0, 1.0), child: child)),
                child: Container(
                  key: const Key('respawnBanner'),
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xDD16204A),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text('SPLATTED!', style: kTitle.copyWith(fontSize: 32, color: const Color(Palette.pink))),
                    Text('Back in a moment...', style: bodyStyle(16, color: Colors.white)),
                  ]),
                ),
              ),
            ),
          );
        },
      );
}

/// "ROUND OVER! Winner ..." with the top three, shown for a few seconds when the
/// server wipes the arena for the next round.
class _RoundBanner extends StatelessWidget {
  const _RoundBanner({required this.session});
  final OnlineSession session;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<RoundResult?>(
        valueListenable: session.roundResult,
        builder: (context, r, _) {
          if (r == null) return const SizedBox.shrink();
          const medals = ['1st', '2nd', '3rd'];
          return IgnorePointer(
            child: Align(
              alignment: const Alignment(0, 0.05),
              child: TweenAnimationBuilder<double>(
                key: ValueKey('${r.winnerName}${r.percent}'),
                tween: Tween(begin: 0.6, end: 1),
                duration: motion(context, const Duration(milliseconds: 450)),
                curve: Curves.elasticOut,
                builder: (_, t, child) => Transform.scale(scale: t, child: child),
                child: Container(
                  key: const Key('roundBanner'),
                  width: 270,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xEE16204A),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(Palette.gold), width: 4),
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(r.youWon ? 'YOU WON THE ROUND!' : 'ROUND OVER!',
                        textAlign: TextAlign.center,
                        style: kTitle.copyWith(fontSize: 26, color: const Color(Palette.gold))),
                    const SizedBox(height: 4),
                    Text('${r.winnerName} took ${r.percent.toStringAsFixed(0)}% of the map',
                        textAlign: TextAlign.center, style: bodyStyle(15, color: Colors.white)),
                    const SizedBox(height: 8),
                    for (var i = 0; i < r.top.length && i < 3; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 1),
                        child: Row(children: [
                          Text(medals[i], style: kTitle.copyWith(fontSize: 15, shadows: const [])),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(r.top[i].name,
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: bodyStyle(15, color: Colors.white)),
                          ),
                          Text('${r.top[i].percent.toStringAsFixed(0)}%', style: bodyStyle(15, color: Colors.white)),
                        ]),
                      ),
                    const SizedBox(height: 6),
                    Text('New round starting!', style: bodyStyle(13, color: const Color(0xFF9FD0FF))),
                  ]),
                ),
              ),
            ),
          );
        },
      );
}
