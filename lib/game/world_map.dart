import 'dart:convert';
import 'dart:ui';

import 'package:flutter/services.dart';

/// One country outline from assets/data/world.json (map units: 3600 x 1420,
/// equirectangular).
class MapCountry {
  MapCountry(this.iso, this.name, this.order, this.path, this.bounds, this.anchor);
  final String iso;
  final String name;

  /// Campaign index, or -1 for decorative land.
  final int order;
  final Path path;
  final Rect bounds;

  /// Where the pin / label goes: centroid of the largest ring.
  final Offset anchor;

  bool get playable => order >= 0;
}

class WorldMapData {
  WorldMapData(this.size, this.countries)
      : playable = countries.where((c) => c.playable).toList()..sort((a, b) => a.order.compareTo(b.order));

  final Size size;
  final List<MapCountry> countries;
  final List<MapCountry> playable;

  static WorldMapData? _cache;

  static Future<WorldMapData> load([AssetBundle? bundle]) async {
    final hit = _cache;
    if (hit != null) return hit;
    final text = await (bundle ?? rootBundle).loadString('assets/data/world.json');
    return _cache = parse(text);
  }

  static WorldMapData parse(String text) {
    final j = jsonDecode(text) as Map<String, dynamic>;
    final out = <MapCountry>[];
    for (final c in j['countries'] as List) {
      final m = c as Map<String, dynamic>;
      final path = Path()..fillType = PathFillType.evenOdd;
      var bestArea = -1.0;
      var anchor = Offset.zero;
      for (final r in m['rings'] as List) {
        final pts = (r as List).cast<num>();
        if (pts.length < 6) continue;
        path.moveTo(pts[0].toDouble(), pts[1].toDouble());
        var a = 0.0, cx = 0.0, cy = 0.0;
        for (var i = 0; i < pts.length; i += 2) {
          final x0 = pts[i].toDouble(), y0 = pts[i + 1].toDouble();
          final k = (i + 2) % pts.length;
          final x1 = pts[k].toDouble(), y1 = pts[k + 1].toDouble();
          if (i > 0) path.lineTo(x0, y0);
          final cr = x0 * y1 - x1 * y0;
          a += cr;
          cx += (x0 + x1) * cr;
          cy += (y0 + y1) * cr;
        }
        path.close();
        if (a.abs() > bestArea && a != 0) {
          bestArea = a.abs();
          anchor = Offset(cx / (3 * a), cy / (3 * a));
        }
      }
      out.add(MapCountry(m['iso'] as String, m['name'] as String, m['order'] as int, path, path.getBounds(), anchor));
    }
    return WorldMapData(Size((j['width'] as num).toDouble(), (j['height'] as num).toDouble()), out);
  }

  /// Country under [p] (map units). Playable countries win over decorative
  /// land, then the smallest match (so small countries stay tappable).
  MapCountry? hitTest(Offset p, {double slop = 0}) {
    MapCountry? best;
    for (final c in countries) {
      if (!c.bounds.inflate(slop).contains(p)) continue;
      if (!c.path.contains(p)) continue;
      if (best == null ||
          (c.playable && !best.playable) ||
          (c.playable == best.playable && c.bounds.shortestSide < best.bounds.shortestSide)) {
        best = c;
      }
    }
    if (best != null || slop <= 0) return best;
    // Fat-finger fallback: nearest playable anchor within [slop].
    for (final c in playable) {
      if ((c.anchor - p).distance <= slop && (best == null || (c.anchor - p).distance < (best.anchor - p).distance)) {
        best = c;
      }
    }
    return best;
  }
}
