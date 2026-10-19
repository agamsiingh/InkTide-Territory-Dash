import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../game/inktide_game.dart';
import '../palette.dart';
import '../widgets.dart';

/// In-match overlay. Rebuilds only when [InkTideGame.hud] changes (~5 Hz).
class Hud extends StatelessWidget {
  const Hud({super.key, required this.game, required this.onPause, this.showFps = false});
  final InkTideGame game;
  final VoidCallback onPause;
  final bool showFps;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<HudData>(
      valueListenable: game.hud,
      builder: (context, h, _) {
        return Stack(children: [
          Positioned(
            left: 12,
            right: 12,
            top: 8,
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              RoundIconButton(
                key: const Key('pauseButton'),
                icon: Icons.pause_rounded,
                tooltip: 'Pause',
                onTap: onPause,
              ),
              const SizedBox(width: 10),
              Expanded(child: RepaintBoundary(child: _ProgressBar(percent: h.percent, target: h.target, best: game.store.bestPercent))),
            ]),
          ),
          Positioned(
            left: 12,
            top: 70,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              StatPill(icon: Icons.sentiment_very_dissatisfied_rounded, value: '${h.kills}', iconColor: Palette.pink),
              const SizedBox(height: 6),
              StatPill(icon: Icons.emoji_events_rounded, value: '#${h.rank}'),
              if (showFps) ...[
                const SizedBox(height: 6),
                Text('${h.fps.toStringAsFixed(0)} FPS',
                    key: const Key('fpsLabel'), style: kTitle.copyWith(fontSize: 14)),
              ],
            ]),
          ),
          Positioned(right: 10, top: 70, child: _Leaderboard(entries: h.leaders)),
          if (h.online)
            // Sits between the kill/rank pills and the leaderboard.
            Positioned(
              left: 112,
              top: 72,
              child: _OnlineChip(code: h.roomCode, players: h.players, ping: h.pingMs, roundLeft: h.roundLeft),
            ),
          Positioned(
            left: 12,
            bottom: 12,
            child: _Minimap(game: game),
          ),
          Positioned.fill(child: _TrailWarning(active: h.trailWarning)),
        ]);
      },
    );
  }
}

/// Pulsing "Head home!" banner plus a soft red edge vignette while the trail
/// is long. Fades out when inactive; no tickers run while hidden.
class _TrailWarning extends StatefulWidget {
  const _TrailWarning({required this.active});
  final bool active;

  @override
  State<_TrailWarning> createState() => _TrailWarningState();
}

class _TrailWarningState extends State<_TrailWarning> with TickerProviderStateMixin {
  late final AnimationController _show =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 180))
        ..addStatusListener((s) {
          if (s == AnimationStatus.dismissed) {
            _pulse.stop();
            if (mounted) setState(() {});
          }
        });
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  late final Animation<double> _scale =
      Tween(begin: 1.0, end: 1.14).chain(CurveTween(curve: Curves.easeInOut)).animate(_pulse);
  late final Animation<double> _edge =
      Tween(begin: 0.55, end: 1.0).chain(CurveTween(curve: Curves.easeInOut)).animate(_pulse);

  static const _vignette = DecoratedBox(
    decoration: BoxDecoration(
      gradient: RadialGradient(
        radius: 1.05,
        colors: [Color(0x00FF3B5C), Color(0x00FF3B5C), Color(0x55FF3B5C)],
        stops: [0, 0.62, 1],
      ),
    ),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _TrailWarning old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) _sync();
  }

  void _sync() {
    if (widget.active) {
      _show.forward();
      if (!reduceMotion(context) && !_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else if (!_show.isDismissed) {
      _show.reverse();
    }
  }

  @override
  void dispose() {
    _show.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active && _show.isDismissed) return const SizedBox.shrink();
    return IgnorePointer(
      child: FadeTransition(
        opacity: _show,
        child: Stack(fit: StackFit.expand, children: [
          FadeTransition(opacity: _edge, child: _vignette),
          Positioned(
            bottom: 24,
            left: 0,
            right: 0,
            child: Center(
              child: ScaleTransition(
                scale: _scale,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.home_rounded, color: Color(Palette.gold), size: 26),
                  const SizedBox(width: 6),
                  Text('Head home!', style: kTitle.copyWith(fontSize: 22, color: const Color(Palette.gold))),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _ProgressBar extends StatefulWidget {
  const _ProgressBar({required this.percent, required this.target, this.best = 0});
  final double percent;
  final double target;

  /// Best-ever territory %, shown as a marker when it falls inside the goal.
  final double best;

  @override
  State<_ProgressBar> createState() => _ProgressBarState();
}

class _ProgressBarState extends State<_ProgressBar> with SingleTickerProviderStateMixin {
  // Brief bump + flash when a capture adds a chunk of territory.
  late final AnimationController _pop =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 420));

  static const _fill = [Color(0xFFFFE680), Color(Palette.yellow), Color(0xFFFF9F1C)];
  static const _fillDone = [Color(0xFFB8F27A), Color(Palette.green), Color(Palette.greenDark)];

  @override
  void didUpdateWidget(covariant _ProgressBar old) {
    super.didUpdateWidget(old);
    if (widget.percent - old.percent >= 0.8 && !reduceMotion(context)) _pop.forward(from: 0);
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final percent = widget.percent, target = widget.target;
    final t = target <= 0 ? 0.0 : (percent / target).clamp(0.0, 1.0);
    final bar = Container(
      height: 40,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xCC16204A),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white, width: 2.5),
      ),
      child: Stack(children: [
        LayoutBuilder(
          builder: (context, c) => TweenAnimationBuilder<double>(
            tween: Tween(end: t),
            duration: motion(context, const Duration(milliseconds: 450)),
            curve: Curves.easeOutCubic,
            builder: (_, v, __) => Container(
              width: c.maxWidth * v,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: LinearGradient(colors: v >= 1 ? _fillDone : _fill),
              ),
              foregroundDecoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x66FFFFFF), Color(0x00FFFFFF)],
                  stops: [0, 0.55],
                ),
              ),
            ),
          ),
        ),
        if (widget.best > 0.5 && widget.best < target)
          LayoutBuilder(
            builder: (context, c) => Stack(clipBehavior: Clip.none, children: [
              Positioned(
                key: const Key('bestMarker'),
                left: c.maxWidth * (widget.best / target) - 1.5,
                top: 0,
                bottom: 0,
                child: Container(width: 3, color: const Color(0xCCFFFFFF)),
              ),
            ]),
          ),
        Center(
          child: Text(
            '${percent.toStringAsFixed(1)}% / ${target.toStringAsFixed(0)}%',
            key: const Key('percentLabel'),
            style: kTitle.copyWith(fontSize: 17),
          ),
        ),
      ]),
    );
    return AnimatedBuilder(
      animation: _pop,
      child: bar,
      builder: (_, child) {
        final k = _pop.isAnimating ? math.sin(_pop.value * math.pi) : 0.0;
        return Transform.scale(scale: 1 + 0.06 * k, child: child);
      },
    );
  }
}

class _Leaderboard extends StatelessWidget {
  const _Leaderboard({required this.entries});
  final List<LeaderEntry> entries;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final e in entries)
          Container(
            width: 132,
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: e.isHuman ? const Color(0xEEFFFFFF) : const Color(0xAA16204A),
              borderRadius: BorderRadius.circular(14),
              border: Border(left: BorderSide(color: Color(e.color), width: 6)),
            ),
            child: Row(children: [
              Text('${e.rank}',
                  style: kTitle.copyWith(
                      fontSize: 14,
                      color: e.isHuman ? const Color(Palette.ink) : Colors.white,
                      shadows: const [])),
              const SizedBox(width: 6),
              Expanded(
                child: Text(e.name,
                    overflow: TextOverflow.ellipsis,
                    style: bodyStyle(13, color: e.isHuman ? const Color(Palette.ink) : Colors.white)),
              ),
              Text('${e.percent.toStringAsFixed(1)}%',
                  style: bodyStyle(13, color: e.isHuman ? const Color(Palette.ink) : Colors.white)),
            ]),
          ),
      ],
    );
  }
}

class _Minimap extends StatelessWidget {
  const _Minimap({required this.game});
  final InkTideGame game;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 104,
      height: 104,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xCC16204A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white, width: 2.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: RepaintBoundary(
          child: CustomPaint(painter: _MinimapPainter(game)),
        ),
      ),
    );
  }
}

class _MinimapPainter extends CustomPainter {
  _MinimapPainter(this.game) : super(repaint: game.minimapTick);
  final InkTideGame game;
  final Paint _p = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    if (!game.isLoaded) return;
    final sim = game.sim;
    final a = sim.arena;
    final sx = size.width / a.width, sy = size.height / a.height;
    canvas.drawRect(Offset.zero & size, _p..color = const Color(Palette.floor));
    for (final pl in sim.players) {
      if (a.counts[pl.id] == 0) continue;
      _p.color = Color(pl.skin.color);
      for (var y = 0; y < a.height; y++) {
        var x = 0;
        final row = y * a.width;
        while (x < a.width) {
          if (a.owner[row + x] != pl.id) {
            x++;
            continue;
          }
          final x0 = x;
          while (x < a.width && a.owner[row + x] == pl.id) {
            x++;
          }
          canvas.drawRect(Rect.fromLTWH(x0 * sx, y * sy, (x - x0) * sx, sy + 0.5), _p);
        }
      }
    }
    for (final pl in sim.players) {
      if (!pl.alive) continue;
      final o = Offset(pl.x * sx, pl.y * sy);
      if (pl.isHuman) {
        canvas.drawCircle(o, 5, _p..color = Colors.white);
        canvas.drawCircle(o, 3.2, _p..color = Color(pl.skin.dark));
      } else {
        canvas.drawCircle(o, 2.4, _p..color = Color(pl.skin.dark));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MinimapPainter old) => old.game != game;
}


/// "ROOM BCDF · 8 players · 45 ms": tap to copy the code for friends.
class _OnlineChip extends StatelessWidget {
  const _OnlineChip({required this.code, required this.players, required this.ping, required this.roundLeft});
  final String code;
  final int players;
  final int ping;
  final int roundLeft;

  @override
  Widget build(BuildContext context) {
    // The dot shows connection quality (green < 120 ms, amber < 250, red above).
    final dot = ping == 0 || ping < 120
        ? const Color(0xFF5DD62C)
        : (ping < 250 ? const Color(0xFFFFB020) : const Color(0xFFFF4757));
    final time = roundLeft > 0 ? '${roundLeft ~/ 60}:${(roundLeft % 60).toString().padLeft(2, '0')}' : '';
    return GestureDetector(
      key: const Key('onlineChip'),
      onTap: () {
        Clipboard.setData(ClipboardData(text: code));
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('Room code $code copied - send it to a friend!'), duration: const Duration(seconds: 2)));
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xCC16204A),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white54, width: 1.5),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.circle, size: 9, color: dot),
          const SizedBox(width: 5),
          Text('$code  •  $players${time.isNotEmpty ? '  •  $time' : ''}',
              style: kTitle.copyWith(fontSize: 13, shadows: const [])),
        ]),
      ),
    );
  }
}
