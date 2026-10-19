import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app.dart';
import '../../game/bonus.dart';
import '../../game/inktide_game.dart';
import '../../services/feedback.dart';
import '../palette.dart';
import '../widgets.dart';
import 'event_screen.dart' show ConfettiBurstPainter;

/// Thick-outlined game title text (stroke layer under the fill).
class OutlinedText extends StatelessWidget {
  const OutlinedText(this.text,
      {super.key, this.size = 40, this.color = Palette.white, this.outline = 0xFF16204A, this.stroke = 7});
  final String text;
  final double size;
  final int color;
  final int outline;
  final double stroke;

  @override
  Widget build(BuildContext context) {
    final base = kTitle.copyWith(fontSize: size, height: 1.0, shadows: const []);
    return Stack(children: [
      Text(text,
          textAlign: TextAlign.center,
          style: base.copyWith(
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = stroke
                ..strokeJoin = StrokeJoin.round
                ..color = col(outline),
              shadows: [Shadow(color: col(outline), offset: Offset(0, stroke * 0.7))])),
      Text(text, textAlign: TextAlign.center, style: base.copyWith(color: col(color))),
    ]);
  }
}

// ---------------------------------------------------------------------------
// Shared art: coin & gem icons, rays, star with crown, stopwatch.

/// Glossy coin with the two-ring emblem.
class CoinIcon extends StatelessWidget {
  const CoinIcon({super.key, this.size = 28});
  final double size;
  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: const _CoinPainter());
}

class _CoinPainter extends CustomPainter {
  const _CoinPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final c = Offset(r, r);
    canvas.drawCircle(c + Offset(0, r * 0.1), r, Paint()..color = const Color(0xFFC77800));
    canvas.drawCircle(c, r * 0.96, Paint()..color = const Color(0xFFFFC928));
    canvas.drawCircle(c, r * 0.7, Paint()..color = const Color(0xFFFFD84D));
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.14
      ..color = const Color(0xFFD48A00);
    canvas.drawOval(Rect.fromCenter(center: c + Offset(-r * 0.22, 0), width: r * 0.42, height: r * 0.62), ring);
    canvas.drawOval(Rect.fromCenter(center: c + Offset(r * 0.22, 0), width: r * 0.42, height: r * 0.62), ring);
    canvas.drawCircle(c + Offset(-r * 0.45, -r * 0.45), r * 0.13, Paint()..color = const Color(0xCCFFFFFF));
    canvas.drawCircle(
        c,
        r * 0.96,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.1
          ..color = const Color(0xFF16204A));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Faceted pink-purple gem.
class GemIcon extends StatelessWidget {
  const GemIcon({super.key, this.size = 28});
  final double size;
  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: const _GemPainter());
}

class _GemPainter extends CustomPainter {
  const _GemPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final c = Offset(r, r);
    final hex = Path();
    for (var i = 0; i < 6; i++) {
      final a = -math.pi / 2 + i * math.pi / 3;
      final p = c + Offset(math.cos(a) * r * 0.95, math.sin(a) * r * 0.95);
      i == 0 ? hex.moveTo(p.dx, p.dy) : hex.lineTo(p.dx, p.dy);
    }
    hex.close();
    canvas.drawPath(hex, Paint()..color = const Color(0xFF9A2BE0));
    final inner = Path();
    for (var i = 0; i < 6; i++) {
      final a = -math.pi / 2 + i * math.pi / 3;
      final p = c + Offset(math.cos(a) * r * 0.55, math.sin(a) * r * 0.55);
      i == 0 ? inner.moveTo(p.dx, p.dy) : inner.lineTo(p.dx, p.dy);
    }
    inner.close();
    canvas.drawPath(inner, Paint()..color = const Color(0xFFE77BFF));
    canvas.drawPath(
        Path()
          ..moveTo(c.dx - r * 0.5, c.dy - r * 0.3)
          ..lineTo(c.dx, c.dy - r * 0.9)
          ..lineTo(c.dx + r * 0.1, c.dy - r * 0.45)
          ..close(),
        Paint()..color = const Color(0xBBFFFFFF));
    canvas.drawPath(
        hex,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.12
          ..strokeJoin = StrokeJoin.round
          ..color = const Color(0xFF16204A));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Rotating light rays from the centre.
class RaysPainter extends CustomPainter {
  RaysPainter(this.turn, {this.color = 0x55FFFFFF, this.count = 14});
  final double turn;
  final int color;
  final int count;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.longestSide;
    final p = Paint()..color = col(color);
    for (var i = 0; i < count; i++) {
      final a = turn * math.pi * 2 + i * math.pi * 2 / count;
      final w = math.pi / count * 0.55;
      canvas.drawPath(
          Path()
            ..moveTo(c.dx, c.dy)
            ..lineTo(c.dx + math.cos(a - w) * r, c.dy + math.sin(a - w) * r)
            ..lineTo(c.dx + math.cos(a + w) * r, c.dy + math.sin(a + w) * r)
            ..close(),
          p);
    }
  }

  @override
  bool shouldRepaint(covariant RaysPainter old) => old.turn != turn;
}

/// Rainbow-rimmed star with a golden crown: the "100%" badge.
class StarCrownPainter extends CustomPainter {
  const StarCrownPainter();

  static Path _star(Offset c, double r, double inner) {
    final p = Path();
    for (var i = 0; i < 10; i++) {
      final a = -math.pi / 2 + i * math.pi / 5;
      final rr = i.isEven ? r : r * inner;
      final pt = c + Offset(math.cos(a) * rr, math.sin(a) * rr);
      i == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
    }
    return p..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final c = Offset(r, r * 1.05);
    final outer = _star(c, r, 0.58);
    final round = Paint()
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(outer, round..strokeWidth = r * 0.34..color = const Color(0xFF16204A));
    canvas.drawPath(
        outer,
        round
          ..strokeWidth = r * 0.24
          ..shader = const SweepGradient(colors: [
            Color(0xFFFF6FB5),
            Color(0xFFFFD84D),
            Color(0xFF7EF0FF),
            Color(0xFF9B7BFF),
            Color(0xFFFF6FB5),
          ]).createShader(Rect.fromCircle(center: c, radius: r)));
    round.shader = null;
    canvas.drawPath(
        outer,
        Paint()
          ..shader = const LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFF7DD1), Color(0xFF9B3BE8)])
              .createShader(Rect.fromCircle(center: c, radius: r)));
    canvas.drawPath(_star(c, r * 0.55, 0.6), Paint()..color = const Color(0x55FFFFFF));
    // Crown.
    final w = r * 0.8, h = r * 0.5;
    final top = c.dy - h * 0.55;
    final crown = Path()
      ..moveTo(c.dx - w / 2, top + h)
      ..lineTo(c.dx - w / 2, top + h * 0.2)
      ..lineTo(c.dx - w * 0.22, top + h * 0.55)
      ..lineTo(c.dx, top)
      ..lineTo(c.dx + w * 0.22, top + h * 0.55)
      ..lineTo(c.dx + w / 2, top + h * 0.2)
      ..lineTo(c.dx + w / 2, top + h)
      ..close();
    canvas.drawPath(crown, round..strokeWidth = r * 0.1..color = const Color(0xFF16204A));
    canvas.drawPath(crown, Paint()..color = const Color(0xFFFFD21F));
    for (final dx in [-w / 2, 0.0, w / 2]) {
      canvas.drawCircle(Offset(c.dx + dx, dx == 0 ? top : top + h * 0.2), r * 0.07, Paint()..color = const Color(0xFFFFF2A8));
    }
    canvas.drawRect(Rect.fromLTWH(c.dx - w / 2, top + h * 0.78, w, h * 0.22), Paint()..color = const Color(0xFFE8A400));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Coins and gems drifting around the intro.
class _FloatingLootPainter extends CustomPainter {
  _FloatingLootPainter(this.t);
  final double t;
  static final List<List<double>> _items = () {
    final r = math.Random(4);
    return [for (var i = 0; i < 9; i++) [r.nextDouble(), r.nextDouble(), 0.7 + r.nextDouble() * 0.7, r.nextDouble()]];
  }();

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < _items.length; i++) {
      final it = _items[i];
      final x = it[0] * size.width;
      final y = (it[1] * size.height - t * 60 * it[2]) % size.height;
      final s = 26 + 22 * it[2];
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(math.sin(t * 2 + i) * 0.4);
      canvas.translate(-s / 2, -s / 2);
      (i % 3 == 0 ? const _GemPainter() : const _CoinPainter()).paint(canvas, Size.square(s));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _FloatingLootPainter old) => old.t != t;
}

class _StopwatchPainter extends CustomPainter {
  _StopwatchPainter(this.sweep);
  final double sweep;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width * 0.42;
    final c = Offset(size.width / 2, size.height * 0.56);
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.08
      ..color = const Color(0xFF16204A);
    // Crown button and side knobs.
    final knob = RRect.fromRectAndRadius(
        Rect.fromCenter(center: c - Offset(0, r * 1.18), width: r * 0.42, height: r * 0.26), Radius.circular(r * 0.08));
    canvas.drawRRect(knob, Paint()..color = const Color(0xFF7EE8FF));
    canvas.drawRRect(knob, edge);
    for (final s in [-1.0, 1.0]) {
      canvas.save();
      canvas.translate(c.dx + s * r * 0.78, c.dy - r * 0.78);
      canvas.rotate(s * math.pi / 4);
      final k = RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: r * 0.26, height: r * 0.3), Radius.circular(r * 0.06));
      canvas.drawRRect(k, Paint()..color = const Color(0xFF7EE8FF));
      canvas.drawRRect(k, edge);
      canvas.restore();
    }
    canvas.drawCircle(c, r * 1.08, Paint()..color = const Color(0xFF1FB6E8));
    canvas.drawCircle(c, r * 1.08, edge);
    canvas.drawCircle(c, r * 0.84, Paint()..color = const Color(0xFFFFFFFF));
    canvas.drawCircle(c + Offset(-r * 0.6, -r * 0.6), r * 0.12, Paint()..color = const Color(0xCCFFFFFF));
    final tick = Paint()
      ..strokeWidth = r * 0.07
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF1FB6E8);
    for (var i = 0; i < 4; i++) {
      final a = i * math.pi / 2;
      canvas.drawLine(c + Offset(math.cos(a), math.sin(a)) * r * 0.62, c + Offset(math.cos(a), math.sin(a)) * r * 0.76, tick);
    }
    // Pink wedge for the extra time, then the hand.
    canvas.drawArc(Rect.fromCircle(center: c, radius: r * 0.55), -math.pi / 2, sweep * math.pi * 2, true,
        Paint()..color = const Color(0x55FF4F8B));
    final a = -math.pi / 2 + sweep * math.pi * 2;
    canvas.drawLine(c, c + Offset(math.cos(a), math.sin(a)) * r * 0.55,
        Paint()
          ..strokeWidth = r * 0.12
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xFFFF3F7F));
    canvas.drawCircle(c, r * 0.16, Paint()..color = const Color(0xFFFF3F7F));
    canvas.drawCircle(c, r * 0.16, edge..strokeWidth = r * 0.05);
  }

  @override
  bool shouldRepaint(covariant _StopwatchPainter old) => old.sweep != sweep;
}

// ---------------------------------------------------------------------------
// 1. "100% BONUS GAME!" celebration.

class BonusIntro extends StatefulWidget {
  const BonusIntro({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  State<BonusIntro> createState() => _BonusIntroState();
}

class _BonusIntroState extends State<BonusIntro> with TickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));
  late final AnimationController _confetti =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final s = Services.of(context);
    s.fx.play(Sfx.bonus);
    s.fx.hapticHeavy();
    _c.addStatusListener((st) {
      if (st == AnimationStatus.completed) widget.onDone();
    });
    if (reduceMotion(context)) {
      // Static card, shorter hold.
      _c.duration = const Duration(milliseconds: 1400);
    } else {
      _confetti.forward();
    }
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    _confetti.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = reduceMotion(context);
    return AnimatedBuilder(
      key: const Key('bonusIntro'),
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        final pop = still ? 1.0 : Curves.elasticOut.transform((t / 0.45).clamp(0.0, 1.0));
        final textIn = still ? 1.0 : Curves.easeOutBack.transform(((t - 0.12) / 0.3).clamp(0.0, 1.0));
        final out = t > 0.85 ? (1 - (t - 0.85) / 0.15) : 1.0;
        return Opacity(
          opacity: out.clamp(0.0, 1.0),
          child: Stack(fit: StackFit.expand, children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                    radius: 0.9, colors: [Color(0xCC2FB9A0), Color(0xE6124A55), Color(0xF00B2B3A)], stops: [0, 0.55, 1]),
              ),
            ),
            CustomPaint(painter: RaysPainter(still ? 0 : t * 0.15, color: 0x22FFF4B0)),
            CustomPaint(painter: _FloatingLootPainter(still ? 0 : t * 2.6)),
            CustomPaint(painter: ConfettiBurstPainter(_confetti)),
            SafeArea(
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Transform.scale(
                    scale: pop,
                    child: Container(
                      decoration: const BoxDecoration(shape: BoxShape.circle, boxShadow: [
                        BoxShadow(color: Color(0x88FFF4A0), blurRadius: 60, spreadRadius: 20),
                      ]),
                      child: const CustomPaint(size: Size(190, 190), painter: StarCrownPainter()),
                    ),
                  ),
                  Transform.scale(
                    scale: textIn,
                    child: const Column(children: [
                      OutlinedText('100%', size: 44, color: 0xFFFFD84D),
                      SizedBox(height: 6),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: OutlinedText('BONUS\nGAME!', size: 76, color: 0xFFFFD84D, stroke: 10),
                        ),
                      ),
                    ]),
                  ),
                ]),
              ),
            ),
          ]),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// 2. Bonus HUD: loot counter and the big countdown.

class BonusHud extends StatelessWidget {
  const BonusHud({super.key, required this.game});
  final InkTideGame game;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: game.bonusTick,
      builder: (context, _, __) {
        final b = game.bonus;
        if (b == null) return const SizedBox.shrink();
        final secs = b.timeLeft.ceil();
        final low = secs <= 3;
        return IgnorePointer(
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TweenAnimationBuilder<double>(
                key: ValueKey('loot ${b.coins} ${b.gems}'),
                tween: Tween(begin: 1.18, end: 1),
                duration: motion(context, const Duration(milliseconds: 220)),
                curve: Curves.easeOutBack,
                builder: (_, k, child) => Transform.scale(scale: k, child: child),
                child: Container(
                key: const Key('bonusLoot'),
                padding: const EdgeInsets.fromLTRB(10, 6, 16, 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF3FA8F0),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(Palette.ink), width: 3),
                  boxShadow: const [BoxShadow(color: Color(0x5516204A), offset: Offset(0, 4))],
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const CoinIcon(size: 30),
                  const SizedBox(width: 6),
                  OutlinedText('${b.coins}', size: 26, stroke: 5, key: const Key('bonusCoins')),
                  const SizedBox(width: 16),
                  const GemIcon(size: 28),
                  const SizedBox(width: 6),
                  OutlinedText('${b.gems}', size: 26, stroke: 5, key: const Key('bonusGems')),
                ]),
              ),
              ),
              const SizedBox(height: 4),
              TweenAnimationBuilder<double>(
                key: ValueKey(secs),
                tween: Tween(begin: 1.35, end: 1),
                duration: motion(context, const Duration(milliseconds: 260)),
                curve: Curves.easeOutBack,
                builder: (_, s, child) => Transform.scale(scale: s, child: child),
                child: OutlinedText('${secs}s',
                    key: const Key('bonusTimer'),
                    size: 64,
                    stroke: 9,
                    color: low ? 0xFFFF4757 : 0xFFFFFFFF,
                    outline: low ? 0xFF5A0A14 : 0xFF16204A),
              ),
            ]),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// 3. CONTINUE BONUS GAME? popup.

class ContinueBonusCard extends StatefulWidget {
  const ContinueBonusCard({super.key, required this.onContinue, required this.onDecline});
  final VoidCallback onContinue;
  final VoidCallback onDecline;

  @override
  State<ContinueBonusCard> createState() => _ContinueBonusCardState();
}

class _ContinueBonusCardState extends State<ContinueBonusCard> with TickerProviderStateMixin {
  late final AnimationController _in = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(seconds: 12));
  bool _done = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_in.status != AnimationStatus.dismissed) return;
    if (reduceMotion(context)) {
      _in.value = 1;
    } else {
      _in.forward();
      _spin.repeat();
    }
  }

  @override
  void dispose() {
    _in.dispose();
    _spin.dispose();
    super.dispose();
  }

  void _pick(VoidCallback f) {
    if (_done) return;
    _done = true;
    f();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_in, _spin]),
      builder: (context, _) {
        final e = Curves.easeOutBack.transform(_in.value);
        return Opacity(
          opacity: _in.value.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: 0.6 + 0.4 * e,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                key: const Key('continueBonus'),
                width: 300,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: const Color(0xFFFFFFFF), width: 5),
                  boxShadow: const [BoxShadow(color: Color(0x6616204A), blurRadius: 18, offset: Offset(0, 8))],
                  gradient: const RadialGradient(colors: [Color(0xFFFFE35A), Color(0xFFFFA51F), Color(0xFFFF7A10)]),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(25),
                  child: Stack(children: [
                    Positioned.fill(child: CustomPaint(painter: RaysPainter(_spin.value, color: 0x40FFFFFF))),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 22),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const OutlinedText('CONTINUE', size: 34, outline: 0xFF16204A),
                        const FittedBox(child: OutlinedText('BONUS GAME?', size: 40, color: 0xFFFFE14D)),
                        const SizedBox(height: 6),
                        CustomPaint(size: const Size(170, 170), painter: _StopwatchPainter(0.12 + 0.05 * math.sin(_spin.value * 40))),
                        OutlinedText('+${BonusRound.extension.round()}s', size: 58, stroke: 9),
                        const SizedBox(height: 10),
                        ChunkyButton(
                          key: const Key('continueButton'),
                          label: 'Continue',
                          width: 220,
                          height: 58,
                          fontSize: 26,
                          onTap: () => _pick(widget.onContinue),
                        ),
                      ]),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 18),
              GestureDetector(
                key: const Key('declineContinue'),
                behavior: HitTestBehavior.opaque,
                onTap: () => _pick(widget.onDecline),
                child: const Padding(
                  padding: EdgeInsets.all(10),
                  child: OutlinedText('No, thanks', size: 26, stroke: 5),
                ),
              ),
            ]),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// 4 + 5. Reward cards and the x2 x3 x4 x3 x2 multiplier.

class RewardSummary extends StatefulWidget {
  const RewardSummary({super.key, required this.coins, required this.gems, required this.onClaimed});
  final int coins;
  final int gems;

  /// Called once with the chosen multiplier after the payout animation.
  final void Function(int multiplier, int coins, int gems) onClaimed;

  @override
  State<RewardSummary> createState() => _RewardSummaryState();
}

class _RewardSummaryState extends State<RewardSummary> with TickerProviderStateMixin {
  late final AnimationController _cards = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  late final AnimationController _result = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  late final TickerClock _clock = TickerClock(this);
  double _stopped = -1;
  int _mult = 1;
  bool _claiming = false;
  double _lastPos = 0;
  Timer? _done;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_cards.status != AnimationStatus.dismissed) return;
    if (reduceMotion(context)) {
      _cards.value = 1;
    } else {
      _cards.forward();
    }
    _clock.start();
    _clock.time.addListener(_tick);
  }

  /// Soft tick each time the needle crosses into a new zone.
  void _tick() {
    if (_stopped >= 0) return;
    final p = meterPosition(_clock.time.value);
    final z = (p * kMultiplierZones.length).floor(), lz = (_lastPos * kMultiplierZones.length).floor();
    if (z != lz) Services.of(context).fx.play(Sfx.meterTick, volumeScale: 0.5);
    _lastPos = p;
  }

  @override
  void dispose() {
    _done?.cancel();
    _clock.time.removeListener(_tick);
    _cards.dispose();
    _result.dispose();
    _clock.dispose();
    super.dispose();
  }

  Future<void> _claim(bool multiply) async {
    if (_claiming) return;
    _claiming = true;
    final s = Services.of(context);
    s.fx.tap();
    final pos = meterPosition(_clock.time.value);
    final mult = multiply ? multiplierAt(pos) : 1;
    setState(() {
      _stopped = pos;
      _mult = mult;
    });
    final paid = await s.store.claimBonus(mult);
    if (!mounted) return;
    final coins = paid?.$1 ?? 0, gems = paid?.$2 ?? 0;
    if (mult > 1) {
      s.fx.play(Sfx.claim);
      s.fx.hapticHeavy();
    } else {
      s.fx.play(Sfx.coin);
    }
    if (reduceMotion(context)) {
      _result.value = 1;
    } else {
      _result.forward();
    }
    _done = Timer(Duration(milliseconds: mult > 1 ? 1500 : 700), () {
      if (mounted) widget.onClaimed(mult, coins, gems);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cards = <(bool, int)>[
      if (widget.coins > 0) (false, widget.coins),
      if (widget.gems > 0) (true, widget.gems),
    ];
    return Stack(fit: StackFit.expand, children: [
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
              center: Alignment(0, -0.2), radius: 1.0, colors: [Color(0xFF3EF0FF), Color(0xFF1C9BF0), Color(0xFF1560D8)]),
        ),
      ),
      SafeArea(
        child: Column(children: [
          const Spacer(flex: 3),
          AnimatedBuilder(
            animation: Listenable.merge([_cards, _result]),
            builder: (context, _) => Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                for (var i = 0; i < cards.length; i++)
                  _LootCard(
                    key: Key(cards[i].$1 ? 'lootGems' : 'lootCoins'),
                    gem: cards[i].$1,
                    value: (cards[i].$2 * (1 + (_mult - 1) * Curves.easeOutCubic.transform(_result.value))).round(),
                    appear: ((_cards.value - i * 0.2) / 0.6).clamp(0.0, 1.0),
                    glow: _result.value,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          AnimatedBuilder(
            animation: _result,
            builder: (context, _) => _result.value == 0 || _mult <= 1
                ? const SizedBox(height: 70)
                : Transform.scale(
                    scale: Curves.elasticOut.transform(_result.value),
                    child: OutlinedText('x$_mult!', key: const Key('multiplierResult'), size: 64, color: 0xFF7DFF5A, stroke: 9),
                  ),
          ),
          const Spacer(flex: 4),
          ValueListenableBuilder<double>(
            valueListenable: _clock.time,
            builder: (context, t, _) => _Meter(position: _stopped >= 0 ? _stopped : meterPosition(t), chosen: _stopped >= 0),
          ),
          const SizedBox(height: 10),
          ChunkyButton(
            key: const Key('multiplyButton'),
            label: 'Multiply',
            width: 260,
            height: 64,
            fontSize: 30,
            onTap: _claiming ? null : () => _claim(true),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            key: const Key('noThanks'),
            behavior: HitTestBehavior.opaque,
            onTap: _claiming ? null : () => _claim(false),
            child: Opacity(
              opacity: _claiming ? 0.4 : 1,
              child: const Padding(
                padding: EdgeInsets.all(10),
                child: OutlinedText('No, thanks', size: 26, stroke: 5),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ]),
      ),
    ]);
  }
}

class _LootCard extends StatelessWidget {
  const _LootCard({super.key, required this.gem, required this.value, required this.appear, required this.glow});
  final bool gem;
  final int value;
  final double appear;
  final double glow;

  @override
  Widget build(BuildContext context) {
    final s = Curves.easeOutBack.transform(appear);
    return Opacity(
      opacity: appear,
      child: Transform.scale(
        scale: 0.4 + 0.6 * s + 0.08 * math.sin(glow * math.pi),
        child: Container(
          width: 112,
          height: 128,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF16204A), width: 3),
            boxShadow: [
              BoxShadow(color: fade(gem ? 0xFFE77BFF : 0xFFFFD84D, 0.4 + 0.5 * glow), blurRadius: 18 + 14 * glow),
            ],
          ),
          padding: const EdgeInsets.all(5),
          child: Column(children: [
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(11),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: gem
                        ? const [Color(0xFFFF8BE8), Color(0xFFD444F2)]
                        : const [Color(0xFFFFE066), Color(0xFFFFA51F)],
                  ),
                ),
                alignment: Alignment.center,
                child: gem ? const GemIcon(size: 56) : const CoinIcon(size: 56),
              ),
            ),
            FittedBox(
              child: OutlinedText('$value',
                  size: 30, stroke: 6, color: gem ? 0xFFF2C2FF : 0xFFFFFFFF, outline: gem ? 0xFF4A1A80 : 0xFF16204A),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Curved x2 x3 x4 x3 x2 meter with a sweeping pointer.
class _Meter extends StatelessWidget {
  const _Meter({required this.position, required this.chosen});
  final double position;
  final bool chosen;

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('multiplierMeter'),
        width: 300,
        height: 100,
        decoration: BoxDecoration(
          color: const Color(0xFFFFA51F),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFF16204A), width: 3),
        ),
        child: CustomPaint(painter: _MeterPainter(position, chosen)),
      );
}

class _MeterPainter extends CustomPainter {
  _MeterPainter(this.position, this.chosen);
  final double position;
  final bool chosen;
  static const _zoneColors = [0xFFFF4757, 0xFFFFE14D, 0xFF5DD62C, 0xFFFFE14D, 0xFFFF4757];

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width * 0.62;
    // Arc top sits 40 px down so the labels fit above it.
    final c = Offset(size.width / 2, 40 + r);
    const span = 0.72; // radians either side of straight up
    const start = -math.pi / 2 - span;
    final rect = Rect.fromCircle(center: c, radius: r);
    final n = kMultiplierZones.length;
    final band = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 20;
    canvas.drawArc(rect, start, span * 2, false, band..color = const Color(0xFF16204A)..strokeWidth = 26);
    final sel = (position * n).floor().clamp(0, n - 1);
    for (var i = 0; i < n; i++) {
      final a0 = start + span * 2 * i / n;
      band
        ..strokeWidth = 20
        ..color = col(_zoneColors[i]).withValues(alpha: chosen && i != sel ? 0.45 : 1);
      canvas.drawArc(rect, a0, span * 2 / n, false, band);
      final mid = a0 + span / n;
      final tp = TextPainter(
        text: TextSpan(
          text: 'x${kMultiplierZones[i]}',
          style: TextStyle(
            fontFamily: 'Lilita',
            fontSize: i == 2 ? 22 : 18,
            color: col(i == 2 ? 0xFF2E9A0E : (i == 0 || i == 4 ? 0xFFD62F45 : 0xFFE89A00)),
            shadows: const [Shadow(color: Color(0xFFFFFFFF), offset: Offset(0, 1.5))],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final p = c + Offset(math.cos(mid), math.sin(mid)) * (r + 22);
      tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
    }
    // Pointer.
    final a = start + span * 2 * position.clamp(0.0, 1.0);
    final tip = c + Offset(math.cos(a), math.sin(a)) * (r - 2);
    canvas.save();
    canvas.translate(tip.dx, tip.dy);
    canvas.rotate(a + math.pi / 2);
    final arrow = Path()
      ..moveTo(0, -4)
      ..lineTo(-10, 16)
      ..lineTo(10, 16)
      ..close();
    canvas.drawPath(arrow, Paint()..color = Colors.white);
    canvas.drawPath(
        arrow,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeJoin = StrokeJoin.round
          ..color = const Color(0xFF16204A));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MeterPainter old) => old.position != position || old.chosen != chosen;
}
