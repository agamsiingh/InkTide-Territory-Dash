import 'dart:math' as math;

import 'package:flutter/rendering.dart';

import '../game/world_map.dart';

/// Visual state of one campaign country on the map.
class CountryLook {
  const CountryLook({required this.unlocked, required this.progress, this.selected = false});
  final bool unlocked;

  /// 0..100.
  final double progress;
  final bool selected;
}

const _sideOffset = Offset(0, 7);
final Map<String, Path> _sideCache = {};
Path _side(MapCountry c) => _sideCache.putIfAbsent(c.iso, () => c.path.shift(_sideOffset));

/// Draws [c] as a raised slab: darker side, top face, and for playable
/// countries a liquid-style fill rising with progress.
void paintCountrySlab(Canvas canvas, MapCountry c, CountryLook? look, {double outline = 1.5}) {
  final p = Paint();
  int top, side;
  if (look == null) {
    // Decorative land: soft mint so the map reads colourful, not grey.
    top = 0xFFE3F6E6;
    side = 0xFFA9CDB2;
  } else if (!look.unlocked) {
    top = 0xFFD3DDE7;
    side = 0xFF9FB0C1;
  } else if (look.progress >= 100) {
    top = 0xFF33C759;
    side = 0xFF1F9440;
  } else {
    top = 0xFFFFFFFF;
    side = 0xFFC3D2DF;
  }
  canvas.drawPath(_side(c), p..color = Color(side));
  canvas.drawPath(c.path, p..color = Color(top));
  if (look != null && look.unlocked && look.progress > 0 && look.progress < 100) {
    final b = c.bounds;
    final h = b.height * look.progress / 100;
    canvas.save();
    canvas.clipPath(c.path);
    canvas.drawRect(Rect.fromLTRB(b.left - 1, b.bottom - h, b.right + 1, b.bottom + 1), p..color = const Color(0xFF4ED872));
    // Bright "surface" line on top of the liquid.
    canvas.drawRect(Rect.fromLTRB(b.left - 1, b.bottom - h, b.right + 1, b.bottom - h + math.max(1.5, b.height * 0.02)),
        p..color = const Color(0xFF9CF0B2));
    canvas.restore();
  }
  canvas.drawPath(
      c.path,
      p
        ..style = PaintingStyle.stroke
        ..strokeWidth = outline
        ..strokeJoin = StrokeJoin.round
        ..color = look?.selected == true ? const Color(0xFFFFD21F) : const Color(0x3316204A));
  if (look?.selected == true) {
    canvas.drawPath(
        c.path,
        p
          ..strokeWidth = outline * 3.2
          ..color = const Color(0xFFFFD21F));
  }
  if (look != null && !look.unlocked) _paintLock(canvas, c.anchor, math.min(26, math.max(9, c.bounds.shortestSide * 0.22)));
}

void _paintLock(Canvas canvas, Offset at, double s) {
  final p = Paint()..color = const Color(0xCC16204A);
  canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: at.translate(0, s * 0.25), width: s, height: s * 0.8),
          Radius.circular(s * 0.18)),
      p);
  canvas.drawArc(
      Rect.fromCenter(center: at.translate(0, -s * 0.12), width: s * 0.66, height: s * 0.8),
      math.pi,
      math.pi,
      false,
      Paint()
        ..color = const Color(0xCC16204A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.16);
}

class WorldMapPainter extends CustomPainter {
  WorldMapPainter(this.data, this.looks);
  final WorldMapData data;

  /// Look per campaign country iso.
  final Map<String, CountryLook> looks;

  @override
  void paint(Canvas canvas, Size size) {
    // Decorative land first, then campaign countries on top.
    for (final c in data.countries) {
      if (!c.playable) paintCountrySlab(canvas, c, null, outline: 1);
    }
    for (final c in data.playable) {
      if (!(looks[c.iso]?.selected ?? false)) paintCountrySlab(canvas, c, looks[c.iso]);
    }
    for (final c in data.playable) {
      if (looks[c.iso]?.selected ?? false) paintCountrySlab(canvas, c, looks[c.iso]);
    }
  }

  @override
  bool shouldRepaint(covariant WorldMapPainter old) {
    if (old.data != data || old.looks.length != looks.length) return true;
    for (final e in looks.entries) {
      final o = old.looks[e.key];
      if (o == null || o.unlocked != e.value.unlocked || o.progress != e.value.progress || o.selected != e.value.selected) {
        return true;
      }
    }
    return false;
  }
}

/// A single country fitted into [size] (home-screen island).
class CountryIslandPainter extends CustomPainter {
  CountryIslandPainter(this.country, this.look);
  final MapCountry country;
  final CountryLook look;

  @override
  void paint(Canvas canvas, Size size) {
    final b = country.bounds;
    final s = math.min(size.width / b.width, (size.height - 14) / b.height);
    canvas.save();
    canvas.translate(size.width / 2 - b.center.dx * s, (size.height - 14) / 2 - b.center.dy * s);
    canvas.scale(s);
    // Soft shadow under the island.
    canvas.drawPath(
        country.path.shift(Offset(0, 16 / s)),
        Paint()
          ..color = const Color(0x3316204A)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6 / s));
    canvas.save();
    // Thicker extrusion for the hero island.
    canvas.translate(0, 6 / s);
    canvas.drawPath(country.path, Paint()..color = Color(look.progress >= 100 ? 0xFF1F9440 : 0xFFB4C6D4));
    canvas.restore();
    paintCountrySlab(canvas, country, CountryLook(unlocked: true, progress: look.progress), outline: 1.2 / s);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CountryIslandPainter old) =>
      old.country != country || old.look.progress != look.progress;
}
