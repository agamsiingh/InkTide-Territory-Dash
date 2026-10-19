import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app.dart';
import '../../game/sim/skins.dart';
import '../../services/feedback.dart';
import '../blob_painter.dart';
import '../palette.dart';
import '../widgets.dart';
import 'bonus_screens.dart';
import 'event_screen.dart' show ConfettiBurstPainter;

/// Capsule colours per rarity: (lid, lid dark, glow).
(int, int, int) rarityColors(Rarity r) => switch (r) {
      Rarity.common => (0xFF35B6FF, 0xFF1C7BD6, 0xFF8FDBFF),
      Rarity.rare => (0xFF4ED96A, 0xFF22A043, 0xFFB4FFC2),
      Rarity.epic => (0xFFB45CFF, 0xFF7A2FD6, 0xFFE2B8FF),
      Rarity.legendary => (0xFFFFC21F, 0xFFE08A00, 0xFFFFF0A0),
    };

/// Full-screen "capsule" reveal for newly unlocked skins: the capsule bobs
/// until tapped, shakes, bursts, and the character appears on a podium.
class CapsuleScreen extends StatefulWidget {
  const CapsuleScreen({super.key, required this.skins});
  final List<Skin> skins;

  static Future<void> show(BuildContext context, List<Skin> skins) async {
    if (skins.isEmpty) return;
    await Navigator.of(context).push(PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: motion(context, const Duration(milliseconds: 300)),
      pageBuilder: (_, __, ___) => CapsuleScreen(skins: skins),
      transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
    ));
  }

  @override
  State<CapsuleScreen> createState() => _CapsuleScreenState();
}

enum _Stage { closed, opening, revealed }

class _CapsuleScreenState extends State<CapsuleScreen> with TickerProviderStateMixin {
  int _index = 0;
  _Stage _stage = _Stage.closed;
  late final AnimationController _open = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  late final AnimationController _reveal = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
  late final AnimationController _confetti =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
  late final TickerClock _clock = TickerClock(this);

  Skin get _skin => widget.skins[_index];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!reduceMotion(context)) _clock.start();
  }

  @override
  void dispose() {
    _open.dispose();
    _reveal.dispose();
    _confetti.dispose();
    _clock.dispose();
    super.dispose();
  }

  Future<void> _tapCapsule() async {
    if (_stage != _Stage.closed) return;
    final s = Services.of(context);
    s.fx.tap();
    s.fx.hapticLight();
    setState(() => _stage = _Stage.opening);
    final still = reduceMotion(context);
    if (still) {
      _open.value = 1;
    } else {
      await _open.forward(from: 0);
    }
    if (!mounted) return;
    s.fx.play(Sfx.capsuleOpen);
    s.fx.hapticHeavy();
    setState(() => _stage = _Stage.revealed);
    await s.store.markSkinSeen(_skin);
    if (!mounted) return;
    s.fx.play(Sfx.unlock);
    if (still) {
      _reveal.value = 1;
    } else {
      _confetti.forward(from: 0);
      _reveal.forward(from: 0);
    }
  }

  void _next() {
    Services.of(context).fx.tap();
    if (_index + 1 < widget.skins.length) {
      setState(() {
        _index++;
        _stage = _Stage.closed;
        _open.value = 0;
        _reveal.value = 0;
      });
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = _skin;
    final rarity = rarityName(skin.rarity);
    final store = Services.of(context).store;
    return Scaffold(
      body: Stack(fit: StackFit.expand, children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF1A66F0), Color(0xFF34B4FF), Color(0xFFE8F7FF)],
              stops: [0, 0.55, 1],
            ),
          ),
        ),
        const CustomPaint(painter: _EyesPatternPainter()),
        if (_stage == _Stage.revealed) const CustomPaint(painter: _GridFloorPainter()),
        Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: ConfettiBurstPainter(_confetti)))),
        SafeArea(
          child: _stage == _Stage.revealed ? _revealView(skin, rarity, store.requirementText(skin)) : _capsuleView(skin, rarity),
        ),
      ]),
    );
  }

  Widget _capsuleView(Skin skin, String rarity) {
    return GestureDetector(
      key: const Key('capsuleTap'),
      behavior: HitTestBehavior.opaque,
      onTap: _tapCapsule,
      child: Column(children: [
        const SizedBox(height: 40),
        OutlinedText(rarity, key: const Key('capsuleRarity'), size: 44),
        if (widget.skins.length > 1) ...[
          const SizedBox(height: 8),
          OutlinedText('${_index + 1} / ${widget.skins.length}', size: 22, stroke: 4),
        ],
        Expanded(
          child: Center(
            child: AnimatedBuilder(
              animation: Listenable.merge([_open, _clock.time]),
              builder: (context, _) {
                final t = _clock.time.value;
                final o = _open.value;
                final bob = math.sin(t * 2.4) * 8 * (1 - o);
                final shake = _stage == _Stage.opening ? math.sin(o * 60) * 0.12 * o : 0.0;
                final swell = 1 + 0.18 * Curves.easeIn.transform(o);
                return Transform.translate(
                  offset: Offset(0, bob),
                  child: Transform.rotate(
                    angle: shake,
                    child: Transform.scale(
                      scale: swell,
                      child: CustomPaint(
                        size: const Size(240, 220),
                        painter: _CapsulePainter(rarityColors(skin.rarity), o),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(bottom: 70),
          child: OutlinedText('Tap to open!', size: 30, stroke: 6),
        ),
      ]),
    );
  }

  Widget _revealView(Skin skin, String rarity, String requirement) {
    return AnimatedBuilder(
      animation: _reveal,
      builder: (context, _) {
        final t = _reveal.value;
        final pop = Curves.elasticOut.transform((t / 0.8).clamp(0.0, 1.0));
        final late = Curves.easeOutBack.transform(((t - 0.35) / 0.65).clamp(0.0, 1.0));
        return Column(children: [
          const SizedBox(height: 30),
          OutlinedText(rarity, size: 30, stroke: 5),
          const SizedBox(height: 8),
          Transform.scale(
            scale: 0.5 + 0.5 * late,
            child: Opacity(
              opacity: late.clamp(0.0, 1.0),
              child: _NameBanner(name: skin.name, colors: rarityColors(skin.rarity)),
            ),
          ),
          Expanded(
            child: Stack(alignment: Alignment.center, children: [
              Positioned(bottom: 40, child: _Podium(glow: t)),
              Positioned(
                bottom: 70,
                child: Transform.scale(
                  scale: pop,
                  alignment: Alignment.bottomCenter,
                  child: BlobAvatar(
                      key: const Key('capsuleSkin'), skin: skin, size: 170, mood: Mood.excited, time: _clock.time, seed: 2),
                ),
              ),
            ]),
          ),
          Opacity(
            opacity: late.clamp(0.0, 1.0),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: const Color(0xFF5DD62C),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                ),
                child: const Icon(Icons.check_rounded, color: Colors.white, size: 32),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text('UNLOCKED', style: bodyStyle(14, color: Colors.white)),
                  Text(requirement, style: kTitle.copyWith(fontSize: 22)),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 26),
          ChunkyButton(
            key: const Key('capsuleGreat'),
            label: 'Great!',
            width: 250,
            height: 64,
            fontSize: 30,
            onTap: t > 0.3 || reduceMotion(context) ? _next : null,
          ),
          const SizedBox(height: 40),
        ]);
      },
    );
  }
}

class _NameBanner extends StatelessWidget {
  const _NameBanner({required this.name, required this.colors});
  final String name;
  final (int, int, int) colors;

  @override
  Widget build(BuildContext context) => Stack(clipBehavior: Clip.none, children: [
        Container(
          constraints: const BoxConstraints(minWidth: 220),
          padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 8),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [const Color(0xFFE6F6FF), col(colors.$3)]),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF16204A), width: 3),
          ),
          child: OutlinedText(name, key: const Key('capsuleName'), size: 36, stroke: 6),
        ),
        Positioned(
          right: -14,
          top: -16,
          child: Transform.rotate(
            angle: 0.35,
            child: const OutlinedText('NEW', key: Key('newLabel'), size: 22, color: 0xFFFF5A7A, stroke: 5),
          ),
        ),
      ]);
}

class _Podium extends StatelessWidget {
  const _Podium({required this.glow});
  final double glow;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 320,
        height: 90,
        child: CustomPaint(painter: _PodiumPainter(glow)),
      );
}

class _PodiumPainter extends CustomPainter {
  _PodiumPainter(this.glow);
  final double glow;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTWH(0, size.height * 0.2, size.width, size.height * 0.7);
    canvas.drawOval(r.shift(const Offset(0, 8)), Paint()..color = const Color(0x5516204A));
    canvas.drawOval(r, Paint()..color = const Color(0xFFDFF4FF));
    canvas.drawOval(
        r.deflate(14),
        Paint()
          ..shader = RadialGradient(colors: [fade(0xFFFFFFFF, 0.9 * glow), fade(0xFF7FE0FF, 0.3)])
              .createShader(r));
    canvas.drawOval(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..color = const Color(0xFFFFFFFF));
    // Light beams.
    final beam = Paint()
      ..shader = LinearGradient(
              begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [fade(0xFFFFFFFF, 0.45 * glow), fade(0xFFFFFFFF, 0)])
          .createShader(Rect.fromLTWH(0, -260, size.width, 300));
    canvas.drawPath(
        Path()
          ..moveTo(size.width * 0.12, size.height * 0.55)
          ..lineTo(size.width * 0.3, -240)
          ..lineTo(size.width * 0.7, -240)
          ..lineTo(size.width * 0.88, size.height * 0.55)
          ..close(),
        beam);
  }

  @override
  bool shouldRepaint(covariant _PodiumPainter old) => old.glow != glow;
}

class _CapsulePainter extends CustomPainter {
  _CapsulePainter(this.colors, this.open);
  final (int, int, int) colors;
  final double open;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..color = const Color(0xFF16204A);
    canvas.drawOval(Rect.fromLTWH(w * 0.05, h * 0.86, w * 0.9, h * 0.16), Paint()..color = const Color(0x3316204A));
    if (open > 0) {
      canvas.drawCircle(Offset(w / 2, h / 2), w * (0.4 + 0.5 * open), Paint()..color = fade(colors.$3, 0.6 * open));
    }
    final bottom = RRect.fromRectAndCorners(Rect.fromLTWH(w * 0.1, h * 0.48, w * 0.8, h * 0.42),
        bottomLeft: Radius.circular(w * 0.22), bottomRight: Radius.circular(w * 0.22));
    canvas.drawRRect(bottom, Paint()..color = const Color(0xFFF2FAFF));
    canvas.drawRRect(bottom, edge);
    // Lid lifts as it opens.
    final lift = -h * 0.08 * Curves.easeIn.transform(open);
    final lid = RRect.fromRectAndCorners(Rect.fromLTWH(w * 0.08, h * 0.06 + lift, w * 0.84, h * 0.48),
        topLeft: Radius.circular(w * 0.26), topRight: Radius.circular(w * 0.26));
    canvas.drawRRect(
        lid,
        Paint()
          ..shader = LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [col(colors.$3), col(colors.$1)])
              .createShader(lid.outerRect));
    canvas.drawRRect(lid, edge);
    canvas.drawOval(Rect.fromLTWH(w * 0.7, h * 0.14 + lift, w * 0.08, h * 0.07), Paint()..color = const Color(0xDDFFFFFF));
    // Band and emblem.
    final band = Rect.fromLTWH(w * 0.04, h * 0.44, w * 0.92, h * 0.12);
    canvas.drawRRect(RRect.fromRectAndRadius(band, const Radius.circular(10)), Paint()..color = col(colors.$2));
    canvas.drawRRect(RRect.fromRectAndRadius(band, const Radius.circular(10)), edge);
    final ec = Offset(w / 2, h * 0.5);
    canvas.drawCircle(ec, w * 0.17, Paint()..color = Colors.white);
    canvas.drawCircle(ec, w * 0.17, edge);
    canvas.drawCircle(ec, w * 0.13, Paint()..color = col(colors.$1));
    final eye = Paint()..color = Colors.white;
    canvas.drawOval(Rect.fromCenter(center: ec + Offset(-w * 0.045, 0), width: w * 0.07, height: w * 0.1), eye);
    canvas.drawOval(Rect.fromCenter(center: ec + Offset(w * 0.045, 0), width: w * 0.07, height: w * 0.1), eye);
    final pupil = Paint()..color = col(colors.$2);
    canvas.drawCircle(ec + Offset(-w * 0.045, h * 0.008), w * 0.018, pupil);
    canvas.drawCircle(ec + Offset(w * 0.045, h * 0.008), w * 0.018, pupil);
    if (open > 0.6) {
      canvas.drawRect(Offset.zero & size, Paint()..color = fade(0xFFFFFFFF, (open - 0.6) / 0.4 * 0.85));
    }
  }

  @override
  bool shouldRepaint(covariant _CapsulePainter old) => old.open != open || old.colors != colors;
}

/// Faint repeating "eyes" pattern on the blue background.
class _EyesPatternPainter extends CustomPainter {
  const _EyesPatternPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = const Color(0x1FFFFFFF);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..color = const Color(0x1FFFFFFF);
    for (var y = 30.0; y < size.height; y += 150) {
      final off = ((y / 150).floor().isEven) ? 0.0 : 85.0;
      for (var x = off - 40; x < size.width + 60; x += 170) {
        canvas.drawOval(Rect.fromCenter(center: Offset(x, y), width: 44, height: 58), ring);
        canvas.drawOval(Rect.fromCenter(center: Offset(x + 50, y - 10), width: 44, height: 58), ring);
        canvas.drawCircle(Offset(x + 6, y + 6), 6, p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Perspective grid floor behind the podium.
class _GridFloorPainter extends CustomPainter {
  const _GridFloorPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final top = size.height * 0.5;
    canvas.drawRect(Rect.fromLTWH(0, top, size.width, size.height - top), Paint()..color = const Color(0xFF1C9BF0));
    final line = Paint()
      ..strokeWidth = 2
      ..color = const Color(0x66FFFFFF);
    final cx = size.width / 2;
    for (var i = -6; i <= 6; i++) {
      canvas.drawLine(Offset(cx + i * 40, top), Offset(cx + i * 160, size.height), line);
    }
    for (var k = 0; k < 6; k++) {
      final y = top + (size.height - top) * math.pow(k / 6, 1.6);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// "POWERS UNLOCKED!" explainer shown once before the first match with powers.
class PowersIntroCard extends StatelessWidget {
  const PowersIntroCard({super.key, required this.skin, required this.onDone});
  final Skin skin;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    Widget row(bool charging, String a, String b) => Row(children: [
          SizedBox(
            width: 130,
            height: 140,
            child: Stack(alignment: Alignment.center, children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [
                  BoxShadow(color: charging ? const Color(0x9934B4FF) : const Color(0x99FFB020), blurRadius: 30, spreadRadius: 6),
                ]),
              ),
              Positioned(top: 34, child: BlobAvatar(skin: skin, size: 74, mood: charging ? Mood.focused : Mood.excited)),
              Positioned(
                top: 0,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF4FA3),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF16204A), width: 3),
                  ),
                  child: const Icon(Icons.water_drop_rounded, color: Colors.white),
                ),
              ),
            ]),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: a, style: const TextStyle(color: Colors.white)),
                TextSpan(text: b, style: const TextStyle(color: Color(0xFFFFE14D))),
              ]),
              style: kTitle.copyWith(fontSize: 24),
            ),
          ),
        ]);
    return Container(
      key: const Key('powersIntro'),
      color: const Color(0xF0383C44),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(children: [
            const SizedBox(height: 30),
            const OutlinedText('POWERS', size: 64, color: 0xFFFFE14D, stroke: 9),
            const OutlinedText('UNLOCKED!', size: 40, stroke: 7),
            const Spacer(),
            row(true, 'Powers ', 'charge automatically'),
            const Icon(Icons.arrow_downward_rounded, size: 46, color: Color(0xFFFFE14D)),
            row(false, 'Double tap ', 'to activate the Ink Splash'),
            const Spacer(),
            ChunkyButton(key: const Key('powersGotIt'), label: 'Got it!', width: 260, height: 64, fontSize: 30, onTap: onDone),
            const SizedBox(height: 40),
          ]),
        ),
      ),
    );
  }
}
