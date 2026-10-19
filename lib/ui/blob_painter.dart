import 'dart:math' as math;
import 'dart:ui';

import '../game/sim/skins.dart';
import 'palette.dart';

enum Mood { happy, focused, worried, excited, dizzy }

// Shared paints/shaders: canvas copies paint state per draw call, so reuse is safe.
final Paint _fill = Paint();
final Paint _shade = Paint();
final Paint _line = Paint()
  ..style = PaintingStyle.stroke
  ..strokeCap = StrokeCap.round;
final Map<int, Shader> _bodyShaders = {};
final Map<int, Shader> _glowShaders = {};

// Body geometry in units of the body width; drawn under canvas.scale(s).
final RRect _unitGloss = RRect.fromRectAndRadius(const Rect.fromLTWH(-0.36, -0.378, 0.42, 0.144), const Radius.circular(0.1));
final Paint _outline = Paint()
  ..style = PaintingStyle.stroke
  ..strokeJoin = StrokeJoin.round
  ..strokeWidth = 0.1;

Path _ghostPath() {
  const w = 0.5, bottom = 0.42;
  final p = Path()
    ..moveTo(-w, bottom)
    ..lineTo(-w, -0.02)
    ..arcToPoint(const Offset(w, -0.02), radius: const Radius.elliptical(w, 0.46))
    ..lineTo(w, bottom);
  // Three scallops along the hem.
  const n = 3;
  for (var i = 0; i < n; i++) {
    final x0 = w - i * 2 * w / n, x1 = w - (i + 1) * 2 * w / n;
    p.quadraticBezierTo((x0 + x1) / 2, bottom - 0.14, x1, bottom);
  }
  return p..close();
}

final Map<BodyShape, Path> _bodies = {
  BodyShape.cube: Path()
    ..addRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: 1, height: 0.9), const Radius.circular(0.3))),
  BodyShape.round: Path()..addOval(Rect.fromCenter(center: const Offset(0, 0.01), width: 1.04, height: 0.94)),
  BodyShape.bean: Path()
    ..addRRect(RRect.fromRectAndRadius(
        Rect.fromCenter(center: const Offset(0, -0.03), width: 0.88, height: 1.0), const Radius.circular(0.44))),
  BodyShape.ghost: _ghostPath(),
};
final Map<BodyShape, Path> _bases = {
  for (final e in _bodies.entries) e.key: e.value.shift(const Offset(0, 0.12)),
};

/// Top of the body (unit space) where accessories attach.
double _top(BodyShape shape) => switch (shape) {
      BodyShape.cube => 0.45,
      BodyShape.round => 0.46,
      BodyShape.bean => 0.53,
      BodyShape.ghost => 0.48,
    };

Paint _c(Color c) => _fill..color = c;

Paint _stroke(Color c, double w) => _line
  ..color = c
  ..strokeWidth = w;

Shader _bodyShader(Skin skin) {
  final key = Object.hash(skin.light, skin.color);
  final hit = _bodyShaders[key];
  if (hit != null) return hit;
  if (_bodyShaders.length > 32) _bodyShaders.clear();
  return _bodyShaders[key] = Gradient.linear(
    const Offset(0, -0.45),
    const Offset(0, 0.45),
    [col(skin.light), col(skin.color), col(skin.color)],
    [0, 0.45, 1],
  );
}

Shader _glowShader(int c) {
  final hit = _glowShaders[c];
  if (hit != null) return hit;
  if (_glowShaders.length > 32) _glowShaders.clear();
  return _glowShaders[c] = Gradient.radial(
    Offset.zero,
    1,
    [fade(c, 0.6), fade(c, 0.42), fade(c, 0.15), fade(c, 0)],
    [0, 0.5, 0.75, 1],
  );
}

/// Deterministic 0..1 hash.
double _hash(int a, int b) {
  var x = ((a & 0xFFFFF) * 374761393 + (b & 0xFFFFF) * 668265263) & 0x7FFFFFFF;
  x = ((x ^ (x >> 13)) * 1274126177) & 0x7FFFFFFF;
  return ((x ^ (x >> 16)) & 0xFFFF) / 0xFFFF;
}

/// Eyelid closure 0..1: one ~0.12 s blink every 2.5-4.5 s.
double _blink(double time, int seed) {
  if (time <= 0) return 0;
  const period = 3.5, dur = 0.12;
  final t = time + (seed == 0 ? 0 : _hash(seed, 911) * period);
  final k = (t / period).floor();
  final u = (t - k * period - 1.5 - _hash(seed, k)) / dur;
  return u <= 0 || u >= 1 ? 0 : math.sin(u * math.pi);
}

/// Draws the glossy cube mascot used for the player, bots and menus.
/// [center] is the middle of the body, [s] its width in pixels.
/// [time] (seconds) drives idle wobble and blinks, [seed] de-syncs characters,
/// [stretch] 0..1 elongates along [lookAngle], [glow] 0..1 adds a skin halo.
void paintBlob(
  Canvas canvas,
  Offset center,
  double s,
  Skin skin, {
  double lookAngle = math.pi / 2,
  double squash = 0,
  Mood mood = Mood.happy,
  double tilt = 0,
  double time = 0,
  int seed = 0,
  double stretch = 0,
  double glow = 0,
}) {
  canvas.save();
  canvas.translate(center.dx, center.dy);
  canvas.rotate(tilt);
  canvas.scale(1 + squash * 0.22, 1 - squash * 0.22);

  final h = s * 0.9;
  final live = time != 0;
  final ph = (seed & 0xFFFF) * 1.618;

  if (glow > 0) {
    final rad = s * (live ? 0.95 + 0.05 * math.sin(time * 2.4 + ph) : 0.95);
    canvas.save();
    canvas.translate(0, s * 0.04);
    canvas.scale(rad);
    canvas.drawCircle(
        Offset.zero,
        1,
        _shade
          ..shader = _glowShader(skin.color)
          ..color = fade(Palette.white, glow.clamp(0.0, 1.0)));
    canvas.restore();
  }

  // Soft ground shadow.
  canvas.drawOval(
    Rect.fromCenter(center: Offset(0, h * 0.58), width: s * 1.05, height: h * 0.32),
    _c(fade(Palette.ink, 0.16)),
  );

  // Speed stretch along the heading (area preserving).
  final st = stretch.clamp(0.0, 1.0) * 0.26;
  if (st > 0) {
    final a = lookAngle - tilt;
    canvas.rotate(a);
    canvas.scale(1 + st, 1 / (1 + st));
    canvas.rotate(-a);
  }
  // Jelly idle: breathing squash and a sway anchored at the feet.
  final sway = live ? math.sin(time * 3.1 + ph * 0.7) : 0.0;
  if (live) {
    final wob = math.sin(time * 5.2 + ph) * 0.025;
    final base = h / 2 + s * 0.12;
    canvas.translate(0, base);
    canvas.skew(sway * 0.05, 0);
    canvas.scale(1 + wob, 1 - wob);
    canvas.translate(0, -base);
  }

  _accessoryLayer(canvas, s, skin, time, ph, behind: true);
  _paintFeet(canvas, s, skin, time, ph);

  // Outline (stroked silhouette, inner half covered by the fills), extrusion
  // (darker underside), body, gloss.
  final body = _bodies[skin.shape]!, base = _bases[skin.shape]!;
  canvas.save();
  canvas.scale(s);
  _outline.color = fade(Palette.ink, 0.88);
  canvas.drawPath(base, _outline);
  canvas.drawPath(body, _outline);
  canvas.drawPath(base, _c(col(skin.dark)));
  canvas.drawPath(
      body,
      _shade
        ..shader = _bodyShader(skin)
        ..color = col(Palette.white));
  if (skin.pattern != SkinPattern.none) _paintPattern(canvas, skin, body);
  canvas.drawRRect(_unitGloss, _c(fade(Palette.white, 0.55)));
  canvas.drawCircle(const Offset(0.2, -0.306), 0.045, _c(fade(Palette.white, 0.6)));
  canvas.restore();

  _paintFace(canvas, s, lookAngle, mood, time, seed, ph);
  _accessoryLayer(canvas, s, skin, time, ph, behind: false);
  canvas.restore();
}

/// Two little feet peeking out under the body; they waddle when animated.
void _paintFeet(Canvas canvas, double s, Skin skin, double time, double ph) {
  final y = s * (skin.shape == BodyShape.bean ? 0.6 : 0.55);
  final edge = _stroke(fade(Palette.ink, 0.88), s * 0.05);
  for (final side in [-1.0, 1.0]) {
    final step = time == 0 ? 0.0 : math.max(0.0, math.sin(time * 9 + ph + (side > 0 ? math.pi : 0))) * s * 0.05;
    final r = Rect.fromCenter(center: Offset(side * s * 0.2, y - step), width: s * 0.24, height: s * 0.15);
    canvas.drawOval(r, edge);
    canvas.drawOval(r, _c(col(skin.dark)));
  }
}

/// Markings clipped to the body silhouette; drawn in unit space.
void _paintPattern(Canvas canvas, Skin skin, Path body) {
  canvas.save();
  canvas.clipPath(body);
  final light = col(skin.light);
  switch (skin.pattern) {
    case SkinPattern.none:
      break;
    case SkinPattern.stripes:
      // Dark vertical melon stripes that bow slightly.
      final p = _stroke(fade(skin.dark, 0.75), 0.09);
      for (var i = -2; i <= 2; i++) {
        final x = i * 0.2;
        canvas.drawPath(
            Path()
              ..moveTo(x * 0.7, -0.5)
              ..quadraticBezierTo(x * 1.5, 0, x * 0.7, 0.5),
            p);
      }
    case SkinPattern.seeds:
      final f = _c(light);
      const pts = [
        Offset(-0.28, -0.22), Offset(0.02, -0.3), Offset(0.3, -0.2), Offset(-0.38, 0.06),
        Offset(0.38, 0.04), Offset(-0.22, 0.3), Offset(0.06, 0.34), Offset(0.28, 0.28),
      ];
      for (final o in pts) {
        canvas.drawOval(Rect.fromCenter(center: o, width: 0.04, height: 0.065), f);
      }
    case SkinPattern.belly:
      // Pale belly with throat grooves, like a whale.
      canvas.drawOval(Rect.fromCenter(center: const Offset(0, 0.36), width: 1.0, height: 0.52), _c(light));
      final g = _stroke(fade(skin.dark, 0.35), 0.018);
      // Throat grooves only on the whale (fin); penguins keep a plain belly.
      for (var i = 0; i < (skin.accessory == Accessory.fin ? 3 : 0); i++) {
        final y = 0.2 + i * 0.07;
        canvas.drawLine(Offset(-0.22 + i * 0.03, y), Offset(0.22 - i * 0.03, y), g);
      }
    case SkinPattern.crosshatch:
      final p = _stroke(fade(skin.dark, 0.55), 0.022);
      for (var i = -6; i <= 6; i++) {
        canvas.drawLine(Offset(i * 0.14 - 0.5, -0.55), Offset(i * 0.14 + 0.5, 0.55), p);
        canvas.drawLine(Offset(i * 0.14 + 0.5, -0.55), Offset(i * 0.14 - 0.5, 0.55), p);
      }
    case SkinPattern.muzzle:
      canvas.drawOval(Rect.fromCenter(center: const Offset(0, 0.17), width: 0.4, height: 0.24), _c(light));
    case SkinPattern.pandaPatches:
      final patch = _c(col(skin.dark));
      for (final side in [-1.0, 1.0]) {
        canvas.save();
        canvas.translate(side * 0.18, -0.05);
        canvas.rotate(side * -0.5);
        canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: 0.34, height: 0.42), patch);
        canvas.restore();
      }
    case SkinPattern.foxCheeks:
      canvas.drawOval(Rect.fromCenter(center: const Offset(-0.24, 0.24), width: 0.44, height: 0.36), _c(light));
      canvas.drawOval(Rect.fromCenter(center: const Offset(0.24, 0.24), width: 0.44, height: 0.36), _c(light));
    case SkinPattern.ribs:
      final p = _stroke(fade(skin.dark, 0.6), 0.03);
      for (final x in [-0.3, 0.0, 0.3]) {
        canvas.drawPath(
            Path()
              ..moveTo(x * 0.6, -0.5)
              ..quadraticBezierTo(x * 1.9, 0, x * 0.6, 0.5),
            p);
      }
  }
  canvas.restore();
}

/// Accessories lag the body sway slightly for follow-through.
void _accessoryLayer(Canvas canvas, double s, Skin skin, double time, double ph, {required bool behind}) {
  if (skin.accessory == Accessory.none) return;
  if (time == 0) {
    _paintAccessory(canvas, s, skin, behind: behind);
    return;
  }
  final top = -s * _top(skin.shape);
  canvas.save();
  canvas.translate(0, top);
  canvas.rotate(math.sin(time * 3.1 + ph * 0.7 - 0.9) * 0.06);
  canvas.translate(0, -top);
  _paintAccessory(canvas, s, skin, behind: behind);
  canvas.restore();
}

void _paintFace(Canvas canvas, double s, double look, Mood mood, double time, int seed, double ph) {
  final lx = math.cos(look) * s * 0.045, ly = math.sin(look) * s * 0.045;
  final eyeW = s * 0.22;
  final open = 1 - _blink(time, seed) * 0.92;
  final eyeH = (mood == Mood.focused ? s * 0.22 : s * 0.29) * open;
  final live = time != 0;
  final shimmer = live ? math.sin(time * 4.0 + ph) : 0.0;
  final white = col(Palette.white), ink = col(Palette.ink);
  for (var side = -1.0; side <= 1.0; side += 2) {
    final c = Offset(side * s * 0.17, -s * 0.06);
    if (mood == Mood.dizzy) {
      final p = _stroke(ink, s * 0.045);
      canvas.drawLine(c + Offset(-eyeW * 0.4, -eyeW * 0.4), c + Offset(eyeW * 0.4, eyeW * 0.4), p);
      canvas.drawLine(c + Offset(eyeW * 0.4, -eyeW * 0.4), c + Offset(-eyeW * 0.4, eyeW * 0.4), p);
      continue;
    }
    if (open < 0.3) {
      // Closed lid.
      canvas.drawArc(Rect.fromCenter(center: c, width: eyeW * 0.9, height: s * 0.08), 0.15, math.pi - 0.3,
          false, _stroke(ink, s * 0.04));
    } else {
      canvas.drawOval(Rect.fromCenter(center: c, width: eyeW, height: eyeH), _c(white));
      final pc = c + Offset(lx, ly * open);
      canvas.drawOval(Rect.fromCenter(center: pc, width: eyeW * 0.62, height: eyeH * 0.66), _c(ink));
      if (open > 0.6) {
        canvas.drawCircle(pc + Offset(-eyeW * 0.12, -eyeH * 0.14), eyeW * 0.13 * (1 + shimmer * 0.12), _c(white));
        if (live) {
          canvas.drawCircle(pc + Offset(eyeW * 0.13, eyeH * 0.15), eyeW * 0.055,
              _c(fade(Palette.white, 0.55 + 0.35 * shimmer)));
        }
      }
    }
    if (mood == Mood.focused) {
      // Determined brows.
      final bh = s * 0.2;
      canvas.drawLine(c + Offset(-side * eyeW * 0.5, -bh * 0.75), c + Offset(side * eyeW * 0.45, -bh * 0.55),
          _stroke(ink, s * 0.04));
    }
  }
  // Cheeks.
  final blush = _c(fade(0xFFFF6F91, 0.55));
  canvas.drawCircle(Offset(-s * 0.31, s * 0.12), s * 0.06, blush);
  canvas.drawCircle(Offset(s * 0.31, s * 0.12), s * 0.06, blush);
  // Mouth.
  final mouthC = Offset(0, s * 0.17);
  switch (mood) {
    case Mood.happy:
    case Mood.focused:
      canvas.drawArc(Rect.fromCenter(center: mouthC - Offset(0, s * 0.03), width: s * 0.16, height: s * 0.12),
          0.2, math.pi - 0.4, false, _stroke(ink, s * 0.035));
    case Mood.excited:
      final path = Path()
        ..moveTo(-s * 0.09, s * 0.12)
        ..quadraticBezierTo(0, s * 0.3, s * 0.09, s * 0.12)
        ..close();
      canvas.drawPath(path, _c(col(0xFFD6334F)));
      canvas.drawCircle(Offset(0, s * 0.2), s * 0.035, _c(col(0xFFFF8FA3)));
    case Mood.worried:
    case Mood.dizzy:
      canvas.drawOval(Rect.fromCenter(center: mouthC, width: s * 0.09, height: s * 0.11), _c(ink));
  }
}

void _paintAccessory(Canvas canvas, double s, Skin skin, {required bool behind}) {
  final top = -s * _top(skin.shape);
  switch (skin.accessory) {
    case Accessory.none:
      return;
    case Accessory.bearEars:
    case Accessory.pandaEars:
    case Accessory.koala:
      if (!behind) {
        if (skin.accessory == Accessory.koala) {
          // Big shiny koala nose.
          final nose = Rect.fromCenter(center: Offset(0, s * 0.08), width: s * 0.16, height: s * 0.12);
          canvas.drawOval(nose, _c(col(0xFF3A3F4A)));
          canvas.drawOval(Rect.fromCenter(center: Offset(-s * 0.03, s * 0.06), width: s * 0.05, height: s * 0.03),
              _c(fade(Palette.white, 0.7)));
        }
        return;
      }
      final koala = skin.accessory == Accessory.koala;
      final panda = skin.accessory == Accessory.pandaEars;
      final r = s * (koala ? 0.2 : 0.14);
      for (final side in [-1.0, 1.0]) {
        final c = Offset(side * s * (koala ? 0.4 : 0.32), top + s * (koala ? 0.08 : 0.02));
        canvas.drawCircle(c, r, _stroke(fade(Palette.ink, 0.88), s * 0.05));
        canvas.drawCircle(c, r, _c(col(panda ? skin.dark : skin.color)));
        canvas.drawCircle(c, r * 0.55, _c(col(panda ? 0xFF55556A : (koala ? 0xFFF2D0DC : skin.light))));
      }
    case Accessory.pig:
      if (behind) {
        for (final side in [-1.0, 1.0]) {
          final ear = Path()
            ..moveTo(side * s * 0.16, top + s * 0.06)
            ..lineTo(side * s * 0.36, top - s * 0.12)
            ..lineTo(side * s * 0.4, top + s * 0.12)
            ..close();
          canvas.drawPath(ear, _stroke(fade(Palette.ink, 0.88), s * 0.05));
          canvas.drawPath(ear, _c(col(skin.dark)));
        }
        return;
      }
      final snout = Rect.fromCenter(center: Offset(0, s * 0.1), width: s * 0.24, height: s * 0.15);
      canvas.drawOval(snout, _stroke(fade(skin.dark, 0.9), s * 0.025));
      canvas.drawOval(snout, _c(col(0xFFFF8DB1)));
      for (final side in [-1.0, 1.0]) {
        canvas.drawOval(Rect.fromCenter(center: Offset(side * s * 0.045, s * 0.1), width: s * 0.04, height: s * 0.06),
            _c(col(0xFFB4456E)));
      }
    case Accessory.frog:
      if (behind) return;
      for (final side in [-1.0, 1.0]) {
        final c = Offset(side * s * 0.2, top + s * 0.02);
        canvas.drawCircle(c, s * 0.13, _stroke(fade(Palette.ink, 0.88), s * 0.05));
        canvas.drawCircle(c, s * 0.13, _c(col(skin.color)));
        canvas.drawCircle(c, s * 0.08, _c(col(Palette.white)));
        canvas.drawCircle(c + Offset(0, s * 0.01), s * 0.045, _c(col(Palette.ink)));
        canvas.drawCircle(c + Offset(-s * 0.02, -s * 0.015), s * 0.017, _c(col(Palette.white)));
      }
    case Accessory.chick:
      if (behind) return;
      // Feather tuft.
      for (var i = -1; i <= 1; i++) {
        final tuft = Path()
          ..moveTo(i * s * 0.04, top + s * 0.04)
          ..quadraticBezierTo(i * s * 0.12, top - s * 0.14, i * s * 0.02 + s * 0.02, top - s * 0.2)
          ..quadraticBezierTo(i * s * 0.06, top - s * 0.06, i * s * 0.04 + s * 0.04, top + s * 0.04)
          ..close();
        canvas.drawPath(tuft, _stroke(fade(Palette.ink, 0.88), s * 0.035));
        canvas.drawPath(tuft, _c(col(skin.dark)));
      }
      // Beak over the mouth.
      final beak = Path()
        ..moveTo(-s * 0.07, s * 0.08)
        ..lineTo(s * 0.07, s * 0.08)
        ..lineTo(0, s * 0.16)
        ..close();
      canvas.drawPath(beak, _stroke(fade(Palette.ink, 0.88), s * 0.03));
      canvas.drawPath(beak, _c(col(0xFFFF9A1F)));
    case Accessory.fox:
      if (!behind) {
        // Black nose tip.
        canvas.drawOval(Rect.fromCenter(center: Offset(0, s * 0.1), width: s * 0.09, height: s * 0.06), _c(col(Palette.ink)));
        return;
      }
      for (final side in [-1.0, 1.0]) {
        final ear = Path()
          ..moveTo(side * s * 0.1, top + s * 0.06)
          ..lineTo(side * s * 0.34, top - s * 0.26)
          ..lineTo(side * s * 0.44, top + s * 0.1)
          ..close();
        canvas.drawPath(ear, _stroke(fade(Palette.ink, 0.88), s * 0.05));
        canvas.drawPath(ear, _c(col(skin.color)));
        final inner = Path()
          ..moveTo(side * s * 0.2, top + s * 0.04)
          ..lineTo(side * s * 0.33, top - s * 0.15)
          ..lineTo(side * s * 0.38, top + s * 0.06)
          ..close();
        canvas.drawPath(inner, _c(col(skin.light)));
      }
    case Accessory.penguin:
      if (behind) {
        for (final side in [-1.0, 1.0]) {
          final fl = Path()
            ..moveTo(side * s * 0.38, top + s * 0.4)
            ..quadraticBezierTo(side * s * 0.62, top + s * 0.62, side * s * 0.5, top + s * 0.86)
            ..quadraticBezierTo(side * s * 0.42, top + s * 0.64, side * s * 0.34, top + s * 0.6)
            ..close();
          canvas.drawPath(fl, _stroke(fade(Palette.ink, 0.88), s * 0.05));
          canvas.drawPath(fl, _c(col(skin.dark)));
        }
        return;
      }
      final beak = Path()
        ..moveTo(-s * 0.06, s * 0.08)
        ..lineTo(s * 0.06, s * 0.08)
        ..lineTo(0, s * 0.15)
        ..close();
      canvas.drawPath(beak, _stroke(fade(Palette.ink, 0.88), s * 0.03));
      canvas.drawPath(beak, _c(col(0xFFFFB020)));
    case Accessory.bow:
      if (behind) return;
      final c = Offset(s * 0.24, top + s * 0.04);
      final bowPaint = _c(col(0xFFFF3D8B));
      for (final side in [-1.0, 1.0]) {
        final wing = Path()
          ..moveTo(c.dx, c.dy)
          ..lineTo(c.dx + side * s * 0.16, c.dy - s * 0.1)
          ..lineTo(c.dx + side * s * 0.16, c.dy + s * 0.1)
          ..close();
        canvas.drawPath(wing, _stroke(fade(Palette.ink, 0.88), s * 0.04));
        canvas.drawPath(wing, bowPaint);
      }
      canvas.drawCircle(c, s * 0.05, _stroke(fade(Palette.ink, 0.88), s * 0.035));
      canvas.drawCircle(c, s * 0.05, _c(col(0xFFFF77B0)));
    case Accessory.stem:
      if (behind) return;
      // Brown stem with a green leaf.
      final stem = _stroke(const Color(0xFF6B3E1B), s * 0.07)..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(0, top + s * 0.03), Offset(s * 0.02, top - s * 0.14), stem);
      final leaf = Path()
        ..moveTo(s * 0.03, top - s * 0.1)
        ..quadraticBezierTo(s * 0.2, top - s * 0.28, s * 0.3, top - s * 0.1)
        ..quadraticBezierTo(s * 0.18, top - s * 0.02, s * 0.03, top - s * 0.1)
        ..close();
      canvas.drawPath(leaf, _stroke(fade(Palette.ink, 0.88), s * 0.04));
      canvas.drawPath(leaf, _c(col(0xFF4CC24E)));
    case Accessory.calyx:
      if (behind) return;
      // Star-shaped strawberry cap.
      final cap = Path();
      for (var i = 0; i < 12; i++) {
        final a = -math.pi / 2 + i * math.pi / 6;
        final r = i.isEven ? s * 0.2 : s * 0.08;
        final pt = Offset(math.cos(a) * r, top + s * 0.02 + math.sin(a) * r * 0.55);
        i == 0 ? cap.moveTo(pt.dx, pt.dy) : cap.lineTo(pt.dx, pt.dy);
      }
      cap.close();
      canvas.drawPath(cap, _stroke(fade(Palette.ink, 0.88), s * 0.04));
      canvas.drawPath(cap, _c(col(0xFF3FB34A)));
    case Accessory.pineCrown:
      if (!behind) return;
      for (var i = -2; i <= 2; i++) {
        final x = i * s * 0.1;
        final h = s * (0.3 - i.abs() * 0.05);
        final blade = Path()
          ..moveTo(x - s * 0.06, top + s * 0.08)
          ..quadraticBezierTo(x + i * s * 0.03, top - h * 0.6, x + i * s * 0.07, top - h)
          ..quadraticBezierTo(x + s * 0.07, top - h * 0.4, x + s * 0.06, top + s * 0.08)
          ..close();
        canvas.drawPath(blade, _stroke(fade(Palette.ink, 0.88), s * 0.04));
        canvas.drawPath(blade, _c(col(i.isEven ? 0xFF2E9A3A : 0xFF4CC24E)));
      }
    case Accessory.bananaTip:
      if (behind) return;
      final tip = RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(s * 0.04, top - s * 0.01), width: s * 0.16, height: s * 0.12),
          Radius.circular(s * 0.03));
      canvas.drawRRect(tip, _stroke(fade(Palette.ink, 0.88), s * 0.04));
      canvas.drawRRect(tip, _c(col(0xFF7A4A1A)));
    case Accessory.thor:
      if (behind) {
        // Flowing red cape and golden hair.
        final cape = Path()
          ..moveTo(-s * 0.46, top + s * 0.35)
          ..quadraticBezierTo(-s * 0.62, top + s * 0.9, -s * 0.38, top + s * 1.0)
          ..lineTo(s * 0.38, top + s * 1.0)
          ..quadraticBezierTo(s * 0.62, top + s * 0.9, s * 0.46, top + s * 0.35)
          ..close();
        canvas.drawPath(cape, _stroke(fade(Palette.ink, 0.88), s * 0.05));
        canvas.drawPath(cape, _c(col(0xFFD6283A)));
        for (final side in [-1.0, 1.0]) {
          final hair = Path()
            ..moveTo(side * s * 0.36, top + s * 0.1)
            ..quadraticBezierTo(side * s * 0.6, top + s * 0.3, side * s * 0.44, top + s * 0.62)
            ..lineTo(side * s * 0.32, top + s * 0.5)
            ..close();
          canvas.drawPath(hair, _stroke(fade(Palette.ink, 0.88), s * 0.04));
          canvas.drawPath(hair, _c(col(0xFFFFD84D)));
        }
        return;
      }
      // Silver winged helmet.
      for (final side in [-1.0, 1.0]) {
        final wing = Path()
          ..moveTo(side * s * 0.3, top + s * 0.02)
          ..quadraticBezierTo(side * s * 0.62, top - s * 0.28, side * s * 0.52, top - s * 0.34)
          ..quadraticBezierTo(side * s * 0.46, top - s * 0.12, side * s * 0.28, top - s * 0.06)
          ..close();
        canvas.drawPath(wing, _stroke(fade(Palette.ink, 0.88), s * 0.04));
        canvas.drawPath(wing, _c(col(0xFFFFFFFF)));
      }
      final helm = Path()
        ..moveTo(-s * 0.4, top + s * 0.16)
        ..quadraticBezierTo(-s * 0.36, top - s * 0.2, 0, top - s * 0.2)
        ..quadraticBezierTo(s * 0.36, top - s * 0.2, s * 0.4, top + s * 0.16)
        ..close();
      canvas.drawPath(helm, _stroke(fade(Palette.ink, 0.88), s * 0.05));
      canvas.drawPath(helm, _c(col(0xFFB8C2D1)));
      canvas.drawRect(
          Rect.fromLTRB(-s * 0.4, top + s * 0.08, s * 0.4, top + s * 0.17), _c(col(0xFF8A96A8)));
      // Lightning bolt on the brow.
      final bolt = Path()
        ..moveTo(s * 0.03, top - s * 0.15)
        ..lineTo(-s * 0.05, top - s * 0.02)
        ..lineTo(s * 0.0, top - s * 0.02)
        ..lineTo(-s * 0.03, top + s * 0.08)
        ..lineTo(s * 0.07, top - s * 0.06)
        ..lineTo(s * 0.02, top - s * 0.06)
        ..close();
      canvas.drawPath(bolt, _c(col(0xFFFFE14D)));
    case Accessory.unicorn:
      if (behind) return;
      final horn = Path()
        ..moveTo(-s * 0.07, top + s * 0.04)
        ..lineTo(s * 0.0, top - s * 0.34)
        ..lineTo(s * 0.07, top + s * 0.04)
        ..close();
      canvas.drawPath(horn, _stroke(fade(Palette.ink, 0.88), s * 0.04));
      canvas.drawPath(horn, _c(col(0xFFFFD84D)));
      final band = _stroke(const Color(0xFFFF8AD0), s * 0.025);
      for (var i = 1; i <= 3; i++) {
        final y = top + s * 0.04 - i * s * 0.095;
        final w = s * 0.07 * (1 - i * 0.25);
        canvas.drawLine(Offset(-w, y + s * 0.025), Offset(w, y - s * 0.015), band);
      }
      for (final side in [-1.0, 1.0]) {
        final ear = Path()
          ..moveTo(side * s * 0.14, top + s * 0.05)
          ..lineTo(side * s * 0.3, top - s * 0.16)
          ..lineTo(side * s * 0.34, top + s * 0.1)
          ..close();
        canvas.drawPath(ear, _stroke(fade(Palette.ink, 0.88), s * 0.04));
        canvas.drawPath(ear, _c(col(0xFFFFB8E4)));
      }
    case Accessory.spikes:
      if (!behind) {
        // Two little dino teeth over the smile.
        final tooth = _c(col(Palette.white));
        for (var side = -1.0; side <= 1.0; side += 2) {
          final r = Rect.fromLTWH(side * s * 0.035 - s * 0.03, s * 0.12, s * 0.06, s * 0.07);
          canvas.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(s * 0.015)), tooth);
        }
        return;
      }
      // Back plates along the top, plus a stubby tail.
      final ridge = Path();
      for (var i = 0; i < 3; i++) {
        final x = -s * 0.22 + i * s * 0.22;
        final h = i == 1 ? s * 0.26 : s * 0.19;
        ridge
          ..moveTo(x - s * 0.11, top + s * 0.06)
          ..lineTo(x, top - h)
          ..lineTo(x + s * 0.11, top + s * 0.06)
          ..close();
      }
      ridge
        ..moveTo(s * 0.3, top + s * 0.55)
        ..quadraticBezierTo(s * 0.62, top + s * 0.5, s * 0.7, top + s * 0.28)
        ..quadraticBezierTo(s * 0.58, top + s * 0.72, s * 0.3, top + s * 0.76)
        ..close();
      canvas.drawPath(ridge, _stroke(fade(Palette.ink, 0.88), s * 0.05));
      canvas.drawPath(ridge, _c(col(0xFFFF8A2A)));
    case Accessory.fin:
      if (!behind) {
        // Little water spout.
        final w = _c(fade(0xFFBFE9FF, 0.95));
        canvas.drawCircle(Offset(-s * 0.04, top - s * 0.14), s * 0.06, w);
        canvas.drawCircle(Offset(s * 0.07, top - s * 0.2), s * 0.05, w);
        canvas.drawCircle(Offset(-s * 0.1, top - s * 0.24), s * 0.04, w);
        return;
      }
      // Whale tail fin poking out behind the body.
      final tail = Path()
        ..moveTo(s * 0.3, top + s * 0.3)
        ..quadraticBezierTo(s * 0.48, top + s * 0.02, s * 0.66, top - s * 0.12)
        ..quadraticBezierTo(s * 0.6, top + s * 0.08, s * 0.72, top + s * 0.18)
        ..quadraticBezierTo(s * 0.52, top + s * 0.18, s * 0.38, top + s * 0.4)
        ..close();
      canvas.drawPath(tail, _stroke(fade(Palette.ink, 0.88), s * 0.05));
      canvas.drawPath(tail, _c(col(skin.dark)));
    case Accessory.bunnyEars:
      if (!behind) return;
      for (var side = -1.0; side <= 1.0; side += 2) {
        canvas.save();
        canvas.translate(side * s * 0.2, top + s * 0.05);
        canvas.rotate(side * 0.18);
        final ear = RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(0, -s * 0.2), width: s * 0.2, height: s * 0.48),
            Radius.circular(s * 0.1));
        canvas.drawRRect(ear, _c(col(skin.color)));
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromCenter(center: Offset(0, -s * 0.2), width: s * 0.09, height: s * 0.32),
                Radius.circular(s * 0.05)),
            _c(col(0xFFFFD1E6)));
        canvas.restore();
      }
    case Accessory.catEars:
      if (!behind) return;
      for (var side = -1.0; side <= 1.0; side += 2) {
        final p = Path()
          ..moveTo(side * s * 0.08, top + s * 0.06)
          ..lineTo(side * s * 0.34, top - s * 0.2)
          ..lineTo(side * s * 0.4, top + s * 0.1)
          ..close();
        canvas.drawPath(p, _c(col(skin.color)));
      }
    case Accessory.horns:
      if (behind) return;
      for (var side = -1.0; side <= 1.0; side += 2) {
        final p = Path()
          ..moveTo(side * s * 0.14, top + s * 0.04)
          ..quadraticBezierTo(side * s * 0.34, top - s * 0.06, side * s * 0.3, top - s * 0.22)
          ..lineTo(side * s * 0.24, top + s * 0.06)
          ..close();
        canvas.drawPath(p, _c(col(0xFFFFF6D6)));
      }
    case Accessory.crown:
      if (behind) return;
      final p = Path()
        ..moveTo(-s * 0.22, top + s * 0.04)
        ..lineTo(-s * 0.24, top - s * 0.18)
        ..lineTo(-s * 0.11, top - s * 0.06)
        ..lineTo(0, top - s * 0.24)
        ..lineTo(s * 0.11, top - s * 0.06)
        ..lineTo(s * 0.24, top - s * 0.18)
        ..lineTo(s * 0.22, top + s * 0.04)
        ..close();
      canvas.drawPath(p, _c(col(0xFFFFD43B)));
      canvas.drawPath(p, _stroke(col(0xFFE0A100), s * 0.025));
      canvas.drawCircle(Offset(0, top - s * 0.04), s * 0.035, _c(col(0xFFFF4757)));
    case Accessory.leaf:
      if (behind) return;
      canvas.drawLine(Offset(0, top + s * 0.02), Offset(s * 0.02, top - s * 0.12), _stroke(col(0xFF7A4B1E), s * 0.04));
      canvas.save();
      canvas.translate(s * 0.1, top - s * 0.12);
      canvas.rotate(-0.5);
      canvas.drawOval(
          Rect.fromCenter(center: Offset.zero, width: s * 0.26, height: s * 0.12), _c(col(0xFF2FAF3A)));
      canvas.restore();
    case Accessory.antenna:
      if (behind) return;
      for (var side = -1.0; side <= 1.0; side += 2) {
        canvas.drawLine(Offset(side * s * 0.12, top + s * 0.03), Offset(side * s * 0.2, top - s * 0.18),
            _stroke(col(skin.dark), s * 0.035));
        canvas.drawCircle(Offset(side * s * 0.2, top - s * 0.19), s * 0.06, _c(col(skin.light)));
      }
    case Accessory.star:
      if (behind) return;
      final path = Path();
      for (var i = 0; i < 10; i++) {
        final rr = i.isEven ? s * 0.13 : s * 0.06;
        final a = -math.pi / 2 + i * math.pi / 5;
        final pt = Offset(s * 0.18 + math.cos(a) * rr, top - s * 0.02 + math.sin(a) * rr);
        if (i == 0) {
          path.moveTo(pt.dx, pt.dy);
        } else {
          path.lineTo(pt.dx, pt.dy);
        }
      }
      path.close();
      canvas.drawPath(path, _c(col(0xFFFFE14D)));
  }
}
