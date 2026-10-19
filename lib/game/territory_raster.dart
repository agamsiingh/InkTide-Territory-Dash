import 'dart:typed_data';

/// Input for [rasterTerritory]; plain data so it can cross an isolate.
class TerritoryRasterJob {
  const TerritoryRasterJob({
    required this.owner,
    required this.width,
    required this.height,
    required this.colors,
    required this.darks,
    this.pixelsPerCell = 6,
    this.thickness = 0.3,
  });

  /// Cell owners (0 = none), row-major, [width] x [height].
  final Uint8List owner;
  final int width;
  final int height;

  /// ARGB top / side colour per player id (index = id).
  final Int32List colors;
  final Int32List darks;
  final int pixelsPerCell;

  /// Downward offset of the darker "side" layer, in cells.
  final double thickness;

  int get imageWidth => width * pixelsPerCell;
  int get imageHeight => (height + 1) * pixelsPerCell;
}

/// Renders territory as smooth, anti-aliased blobs: ownership is sampled
/// with cubic B-spline weights over the 4x4 surrounding cells and
/// thresholded at [_threshold]. Straight edges stay on cell borders while
/// staircase diagonals and corners become smooth curves. A darker copy shifted
/// down gives the extruded look. Returns premultiplied RGBA8888 pixels (what
/// Flutter's raw image decoding expects).
const double _threshold = 0.4;

Uint8List rasterTerritory(TerritoryRasterJob job) {
  final w = job.width, h = job.height, k = job.pixelsPerCell;
  final iw = job.imageWidth, ih = job.imageHeight;
  final out = Uint8List(iw * ih * 4);
  final owner = job.owner;
  // Anti-aliasing ramp: ~1 output pixel wide.
  final ramp = k * 1.6;
  final wx = List<double>.filled(4, 0), wy = List<double>.filled(4, 0);
  final ids = List<int>.filled(16, 0), ws = List<double>.filled(16, 0);

  void bspline(double t, List<double> o) {
    final t2 = t * t, t3 = t2 * t;
    o[0] = (1 - t) * (1 - t) * (1 - t) / 6;
    o[1] = (3 * t3 - 6 * t2 + 4) / 6;
    o[2] = (-3 * t3 + 3 * t2 + 3 * t + 1) / 6;
    o[3] = t3 / 6;
  }

  // Samples the dominant owner and its weight at cell coords (u, v).
  int sampledOwner = 0;
  double sample(double u, double v) {
    final x0 = u.floor(), y0 = v.floor();
    bspline(u - x0, wx);
    bspline(v - y0, wy);
    var n = 0;
    for (var j = 0; j < 4; j++) {
      final y = y0 - 1 + j;
      if (y < 0 || y >= h) continue;
      final row = y * w;
      for (var i = 0; i < 4; i++) {
        final x = x0 - 1 + i;
        if (x < 0 || x >= w) continue;
        final o = owner[row + x];
        if (o == 0) continue;
        final wt = wx[i] * wy[j];
        var m = 0;
        while (m < n && ids[m] != o) {
          m++;
        }
        if (m == n) {
          ids[n] = o;
          ws[n] = 0;
          n++;
        }
        ws[m] += wt;
      }
    }
    var best = 0, bestW = 0.0;
    for (var m = 0; m < n; m++) {
      if (ws[m] > bestW) {
        bestW = ws[m];
        best = ids[m];
      }
    }
    sampledOwner = best;
    return bestW;
  }

  for (var py = 0; py < ih; py++) {
    final v = (py + 0.5) / k - 0.5;
    for (var px = 0; px < iw; px++) {
      final u = (px + 0.5) / k - 0.5;
      // Top surface.
      final wt = sample(u, v);
      final topO = sampledOwner;
      final topA = wt <= 0 ? 0.0 : ((wt - _threshold) * ramp + 0.5).clamp(0.0, 1.0);
      final j = (py * iw + px) * 4;
      if (topA >= 1) {
        final c = job.colors[topO];
        out[j] = (c >> 16) & 0xFF;
        out[j + 1] = (c >> 8) & 0xFF;
        out[j + 2] = c & 0xFF;
        out[j + 3] = 255;
        continue;
      }
      // Side layer (sampled higher up = drawn lower).
      final sw = sample(u, v - job.thickness);
      final sideO = sampledOwner;
      final sideA = sw <= 0 ? 0.0 : ((sw - _threshold) * ramp + 0.5).clamp(0.0, 1.0);
      if (topA <= 0 && sideA <= 0) continue;
      // Composite top over side (straight alpha).
      final tc = topA > 0 ? job.colors[topO] : 0;
      final sc = sideA > 0 ? job.darks[sideO] : 0;
      final a = topA + sideA * (1 - topA);
      if (a <= 0) continue;
      // Premultiplied "top over side".
      double ch(int shift) => ((tc >> shift) & 0xFF) * topA + ((sc >> shift) & 0xFF) * sideA * (1 - topA);
      out[j] = ch(16).round();
      out[j + 1] = ch(8).round();
      out[j + 2] = ch(0).round();
      out[j + 3] = (a * 255).round();
    }
  }
  return out;
}
