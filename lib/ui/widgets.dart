import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../game/sim/skins.dart';
import 'blob_painter.dart';
import 'palette.dart';

const TextStyle kTitle = TextStyle(
  fontFamily: 'Lilita',
  color: Color(Palette.white),
  fontSize: 30,
  shadows: [Shadow(color: Color(Palette.ink), offset: Offset(0, 3))],
);

TextStyle bodyStyle(double size, {Color color = const Color(Palette.ink)}) => TextStyle(
      fontFamily: 'Fredoka',
      fontVariations: const [FontVariation('wght', 600)],
      fontSize: size,
      color: color,
    );

/// True when the platform asks for reduced motion.
bool reduceMotion(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// [d], or zero when animations are disabled.
Duration motion(BuildContext context, Duration d) => reduceMotion(context) ? Duration.zero : d;

/// Cinematic ink-splash route: the new page is revealed by a growing circle
/// from [origin] with an ink rim and droplets. Pops retract the splash.
Route<T> inkRoute<T>(Widget page, {Alignment origin = const Alignment(0, 0.45), int ink = Palette.yellow}) =>
    PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 450),
      reverseTransitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondary) => page,
      transitionsBuilder: (context, a, secondary, child) => reduceMotion(context)
          ? FadeTransition(opacity: a, child: child)
          : _InkReveal(animation: a, origin: origin, ink: ink, child: child),
    );

class _InkReveal extends StatelessWidget {
  const _InkReveal({required this.animation, required this.origin, required this.ink, required this.child});
  final Animation<double> animation;
  final Alignment origin;
  final int ink;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final v = animation.value;
        final t = animation.status == AnimationStatus.reverse
            ? Curves.easeInCubic.transform(v)
            : Curves.easeOutCubic.transform(v);
        final done = v >= 1;
        // Fixed tree shape so the page keeps its state when the reveal ends.
        return CustomPaint(
          foregroundPainter: done ? null : _InkRimPainter(origin, t, ink),
          child: ClipPath(
            clipper: done ? null : _CircleClipper(origin, t),
            clipBehavior: done ? Clip.none : Clip.antiAlias,
            child: Transform.scale(scale: done ? 1 : 1 + 0.06 * (1 - t), child: child),
          ),
        );
      },
    );
  }
}

double _revealRadius(Size size, Alignment origin, double t) {
  final c = origin.alongSize(size);
  final dx = math.max(c.dx, size.width - c.dx), dy = math.max(c.dy, size.height - c.dy);
  // Full coverage slightly before the curve ends so taps land on the new page.
  return math.sqrt(dx * dx + dy * dy) * (t / 0.9);
}

class _CircleClipper extends CustomClipper<Path> {
  _CircleClipper(this.origin, this.t);
  final Alignment origin;
  final double t;

  @override
  Path getClip(Size size) =>
      Path()..addOval(Rect.fromCircle(center: origin.alongSize(size), radius: _revealRadius(size, origin, t)));

  @override
  bool shouldReclip(covariant _CircleClipper old) => old.t != t || old.origin != origin;
}

class _InkRimPainter extends CustomPainter {
  _InkRimPainter(this.origin, this.t, this.ink);
  final Alignment origin;
  final double t;
  final int ink;
  static final Paint _p = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || t >= 0.9) return;
    final c = origin.alongSize(size);
    final r = _revealRadius(size, origin, t);
    final k = 1 - t / 0.9;
    _p
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6 + 26 * k
      ..color = fade(ink, 0.9 * k);
    canvas.drawCircle(c, r, _p);
    _p
      ..style = PaintingStyle.fill
      ..color = fade(ink, k);
    for (var i = 0; i < 9; i++) {
      final a = i * 0.698 + 0.4;
      final d = r + 20 + 34 * (i % 3) * (1 - k);
      canvas.drawCircle(c + Offset(math.cos(a) * d, math.sin(a) * d), (5 + (i % 4) * 3) * k, _p);
    }
  }

  @override
  bool shouldRepaint(covariant _InkRimPainter old) => old.t != t || old.ink != ink;
}

/// Fades/slides/scales [child] in over the [start]..[end] slice of [animation].
class StaggerIn extends StatelessWidget {
  const StaggerIn({
    super.key,
    required this.animation,
    required this.child,
    this.start = 0,
    this.end = 1,
    this.offset = const Offset(0, 28),
    this.scale = 1,
    this.curve = Curves.easeOutCubic,
  });
  final Animation<double> animation;
  final Widget child;
  final double start;
  final double end;
  final Offset offset;
  final double scale;
  final Curve curve;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final u = ((animation.value - start) / (end - start)).clamp(0.0, 1.0);
        final t = u >= 1 ? 1.0 : curve.transform(u);
        return Opacity(
          opacity: math.min(1.0, u * 2.5),
          child: Transform.translate(
            offset: offset * (1 - t),
            child: Transform.scale(scale: scale + (1 - scale) * t, child: child),
          ),
        );
      },
    );
  }
}

/// Seconds since [start], ticking only while the owner's tickers are enabled.
class TickerClock {
  TickerClock(TickerProvider vsync) {
    _ticker = vsync.createTicker((e) => time.value = e.inMicroseconds / 1e6);
  }
  late final Ticker _ticker;
  final ValueNotifier<double> time = ValueNotifier(0);

  void start() {
    if (!_ticker.isActive) _ticker.start();
  }

  void dispose() {
    _ticker.dispose();
    time.dispose();
  }
}

/// Loading screen shown while services initialise.
class SplashView extends StatelessWidget {
  const SplashView({super.key, required this.progress});
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const PaintBackground(),
          SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 2),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.6, end: 1),
                  duration: motion(context, const Duration(milliseconds: 900)),
                  curve: Curves.elasticOut,
                  builder: (_, s, child) => Transform.scale(scale: s, child: child),
                  child: Image.asset('assets/images/logo.png', width: 260, height: 260),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 64),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(end: progress),
                      duration: motion(context, const Duration(milliseconds: 350)),
                      curve: Curves.easeOutCubic,
                      builder: (_, v, __) => LinearProgressIndicator(
                        value: v,
                        minHeight: 14,
                        backgroundColor: const Color(0x55FFFFFF),
                        valueColor: const AlwaysStoppedAnimation(Color(Palette.yellow)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text('Mixing the paint...', style: bodyStyle(16, color: Colors.white)),
                const Spacer(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Sky gradient with slowly drifting paint blobs.
class PaintBackground extends StatefulWidget {
  const PaintBackground({super.key, this.animate = true});
  final bool animate;

  @override
  State<PaintBackground> createState() => _PaintBackgroundState();
}

class _PaintBackgroundState extends State<PaintBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 20));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.animate && !reduceMotion(context)) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(painter: _BgPainter(_c), size: Size.infinite),
    );
  }
}

class _BgPainter extends CustomPainter {
  _BgPainter(this.anim) : super(repaint: anim);
  final Animation<double> anim;
  final Paint _p = Paint();
  Shader? _sky;
  Size? _skySize;

  static const _blobs = [
    (0.12, 0.18, 70.0, 0xFFFFC928),
    (0.85, 0.12, 54.0, 0xFFFF4FA3),
    (0.9, 0.62, 80.0, 0xFF2EB7FF),
    (0.08, 0.72, 62.0, 0xFF7EDB3A),
    (0.5, 0.92, 90.0, 0xFF9B5CFF),
    (0.55, 0.38, 40.0, 0xFFFF8A2A),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    if (_skySize != size) {
      _skySize = size;
      _sky = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF8FE0FF), Color(0xFF3AA8E8)],
      ).createShader(rect);
    }
    canvas.drawRect(rect, _p..shader = _sky);
    _p.shader = null;
    final t = anim.value * math.pi * 2;
    for (var i = 0; i < _blobs.length; i++) {
      final b = _blobs[i];
      final dx = math.sin(t + i) * 18, dy = math.cos(t * 1.3 + i * 2) * 14;
      final center = Offset(b.$1 * size.width + dx, b.$2 * size.height + dy);
      canvas.drawCircle(center, b.$3, _p..color = fade(b.$4, 0.28));
      canvas.drawCircle(center + Offset(b.$3 * 0.7, b.$3 * 0.5), b.$3 * 0.35, _p..color = fade(b.$4, 0.22));
    }
  }

  @override
  bool shouldRepaint(covariant _BgPainter old) => false;
}

/// The mascot drawn with the shared blob painter. Pass [time] (seconds) to
/// animate idle wobble and blinks; only this widget repaints then.
class BlobAvatar extends StatelessWidget {
  const BlobAvatar({
    super.key,
    required this.skin,
    this.size = 80,
    this.mood = Mood.happy,
    this.look = math.pi / 2,
    this.time,
    this.seed = 0,
  });
  final Skin skin;
  final double size;
  final Mood mood;
  final double look;
  final ValueListenable<double>? time;
  final int seed;

  @override
  Widget build(BuildContext context) {
    final paint = CustomPaint(
      size: Size(size, size * 1.15),
      painter: _BlobAvatarPainter(skin, mood, look, time, seed),
    );
    return time == null ? paint : RepaintBoundary(child: paint);
  }
}

class _BlobAvatarPainter extends CustomPainter {
  _BlobAvatarPainter(this.skin, this.mood, this.look, this.time, this.seed) : super(repaint: time);
  final Skin skin;
  final Mood mood;
  final double look;
  final ValueListenable<double>? time;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    paintBlob(canvas, Offset(size.width / 2, size.height * 0.56), size.width * 0.8, skin,
        mood: mood, lookAngle: look, time: time?.value ?? 0, seed: seed);
  }

  @override
  bool shouldRepaint(covariant _BlobAvatarPainter old) =>
      old.skin != skin || old.mood != mood || old.look != look || old.time != time || old.seed != seed;
}

/// Glossy, chunky 3D-style button with press animation.
class ChunkyButton extends StatefulWidget {
  const ChunkyButton({
    super.key,
    required this.label,
    required this.onTap,
    this.color = Palette.green,
    this.dark = Palette.greenDark,
    this.icon,
    this.fontSize = 24,
    this.height = 62,
    this.width,
  });

  final String label;
  final VoidCallback? onTap;
  final int color;
  final int dark;
  final IconData? icon;
  final double fontSize;
  final double height;
  final double? width;

  @override
  State<ChunkyButton> createState() => _ChunkyButtonState();
}

class _ChunkyButtonState extends State<ChunkyButton> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final color = enabled ? widget.color : 0xFFB0B8C8;
    final dark = enabled ? widget.dark : 0xFF8890A0;
    const depth = 6.0;
    return Semantics(
      button: true,
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => _set(true) : null,
        onTapCancel: enabled ? () => _set(false) : null,
        onTapUp: enabled ? (_) => _set(false) : null,
        onTap: widget.onTap,
        child: AnimatedScale(
          // Squash on press, springy overshoot on release.
          scale: _down ? 0.95 : 1,
          duration: Duration(milliseconds: _down ? 70 : 260),
          curve: _down ? Curves.easeOut : Curves.easeOutBack,
          child: SizedBox(
            width: widget.width,
            height: widget.height + depth,
            child: Stack(
              children: [
                Positioned.fill(
                  top: depth,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Color(dark),
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                ),
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 60),
                  left: 0,
                  right: 0,
                  top: _down ? depth : 0,
                  height: widget.height,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(mix(color, 0xFFFFFFFF, _down ? 0.2 : 0.35)), Color(color)],
                      ),
                      border: Border.all(color: const Color(0x33FFFFFF), width: 2),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.icon != null) ...[
                          Icon(widget.icon, color: Colors.white, size: widget.fontSize + 2),
                          const SizedBox(width: 8),
                        ],
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(widget.label, style: kTitle.copyWith(fontSize: widget.fontSize)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Rounded pill showing an icon and value (coins, level...).
class StatPill extends StatelessWidget {
  const StatPill({super.key, required this.icon, required this.value, this.iconColor = Palette.yellow});
  final IconData icon;
  final String value;
  final int iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 4, 14, 4),
      decoration: BoxDecoration(
        color: const Color(0xCC16204A),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: const Color(0x44FFFFFF), width: 2),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(color: Color(iconColor), shape: BoxShape.circle),
          child: Icon(icon, size: 18, color: Colors.white),
        ),
        const SizedBox(width: 8),
        Text(value, style: kTitle.copyWith(fontSize: 18)),
      ]),
    );
  }
}

/// White rounded card with a colored header, used by dialogs/screens.
class GamePanel extends StatelessWidget {
  const GamePanel({super.key, required this.title, required this.child, this.headerColor = Palette.skyDeep});
  final String title;
  final Widget child;
  final int headerColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        boxShadow: const [BoxShadow(color: Color(0x5516204A), offset: Offset(0, 8), blurRadius: 0)],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(mix(headerColor, Palette.white, 0.18)), Color(headerColor)],
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          child: Text(title, style: kTitle.copyWith(fontSize: 28)),
        ),
        // Transparent Material so ListTile ink/splashes paint above the white card.
        Material(
          type: MaterialType.transparency,
          child: Padding(padding: const EdgeInsets.all(18), child: child),
        ),
      ]),
    );
  }
}

/// Round icon button in the game style, with a springy press.
class RoundIconButton extends StatefulWidget {
  const RoundIconButton({super.key, required this.icon, required this.onTap, this.color = Palette.skyDeep, this.tooltip});
  final IconData icon;
  final VoidCallback onTap;
  final int color;
  final String? tooltip;

  @override
  State<RoundIconButton> createState() => _RoundIconButtonState();
}

class _RoundIconButtonState extends State<RoundIconButton> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.tooltip,
      child: GestureDetector(
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? 0.86 : 1,
          duration: Duration(milliseconds: _down ? 70 : 260),
          curve: _down ? Curves.easeOut : Curves.easeOutBack,
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Color(widget.color),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: const [BoxShadow(color: Color(0x5516204A), offset: Offset(0, 4))],
            ),
            child: Icon(widget.icon, color: Colors.white, size: 26),
          ),
        ),
      ),
    );
  }
}

/// Player rank badge with an XP progress bar; the fill animates on change.
class RankBar extends StatelessWidget {
  const RankBar({super.key, required this.rank, required this.xp, required this.needed, this.width = 230});
  final int rank;
  final int xp;
  final int needed;
  final double width;

  @override
  Widget build(BuildContext context) {
    final f = needed <= 0 ? 0.0 : (xp / needed).clamp(0.0, 1.0).toDouble();
    return SizedBox(
      width: width,
      child: Row(children: [
        Container(
          key: const Key('rankBadge'),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFF29A1F),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white, width: 2.5),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.star_rounded, size: 18, color: Colors.white),
            const SizedBox(width: 2),
            Text('$rank', style: kTitle.copyWith(fontSize: 17)),
          ]),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Container(
              height: 12,
              decoration: BoxDecoration(
                color: const Color(0x5516204A),
                borderRadius: BorderRadius.circular(6),
              ),
              alignment: Alignment.centerLeft,
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: f),
                duration: motion(context, const Duration(milliseconds: 700)),
                curve: Curves.easeOutCubic,
                builder: (_, v, __) => FractionallySizedBox(
                  widthFactor: math.max(v, 0.04),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(Palette.gold),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text('$xp / $needed XP', style: bodyStyle(12, color: Colors.white)),
          ]),
        ),
      ]),
    );
  }
}
