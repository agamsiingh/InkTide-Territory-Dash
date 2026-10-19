import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/animation.dart' show Curves;
import 'package:flutter/painting.dart';

import '../ui/blob_painter.dart';
import '../ui/palette.dart';
import 'bonus.dart';
import 'inktide_game.dart';
import 'sim/arena.dart';
import 'sim/simulation.dart';
import 'territory_raster.dart';

// Particle kinds; the first four map 1:1 to atlas sprites.
const int _drop = 0, _spray = 1, _confetti = 2, _glint = 3, _ring = 4;
const int _splatSprite = 4;
const double _sp = 64; // atlas cell size in px
const double _half = _sp / 2;

class _Particle {
  double x = 0, y = 0, vx = 0, vy = 0, life = 0, maxLife = 1, size = 1;
  double rot = 0, spin = 0, grav = 0, drag = 0;
  int color = 0;
  int kind = _drop;
}

class _Splat {
  double x = 0, y = 0, life = 0, maxLife = 1, size = 1, rot = 0;
  int color = 0;
}

class _FloatText {
  _FloatText(this.painter, this.x, this.y);
  final TextPainter painter;
  double x, y;
  double age = 0;
}

/// Renders the whole arena in world space (pixels = cells * cell size).
/// Territory is cached in a Picture and only re-recorded when ownership
/// changes; particles and splats come from fixed pools and are drawn in
/// batched atlas calls.
class ArenaView extends Component {
  ArenaView(this.game);

  final InkTideGame game;
  static const double c = InkTideGame.cell;
  static const int maxParticles = 380;
  static const int maxSplats = 20;
  static const int _maxIds = 64;

  /// Scales effect time (hit-stop / slow motion), set by the game.
  double timeScale = 1;

  final List<_Particle> _pool = List.generate(maxParticles, (_) => _Particle());
  final List<_Splat> _splats = List.generate(maxSplats, (_) => _Splat());
  int _nextParticle = 0, _nextSplat = 0, _live = 0, _liveSplats = 0;
  final List<_FloatText> _texts = [];
  final Map<int, TextPainter> _labels = {};
  final math.Random _rng = math.Random(3);

  ui.Picture? _floorPic;
  ui.Picture? _territoryPic;

  // Smooth territory: rasterised on a background isolate whenever ownership
  // changes (throttled); new captures cross-fade in.
  static const double _rpx = 8; // raster pixels per cell
  ui.Image? _terrImg, _prevImg;
  double _terrFade = 1, _sinceRaster = 1;
  int _rasterVersion = -1;
  bool _rastering = false, _removed = false;
  final Paint _imgPaint = Paint()..filterQuality = FilterQuality.low;
  final Paint _foam = Paint()..style = PaintingStyle.stroke;
  final Paint _arrow = Paint();
  final Paint _arrowEdge = Paint()
    ..style = PaintingStyle.stroke
    ..strokeJoin = StrokeJoin.round;
  ui.Image? _atlas;
  int _territoryVersion = -1;
  double _time = 0;
  double _sprayTimer = 0;

  // Atlas batches: normal (src-over) and additive glints.
  final Float32List _xf = Float32List(maxParticles * 4), _src = Float32List(maxParticles * 4);
  final Int32List _cols = Int32List(maxParticles);
  final Float32List _xfA = Float32List(maxParticles * 4), _srcA = Float32List(maxParticles * 4);
  final Int32List _colsA = Int32List(maxParticles);
  final Float32List _xfS = Float32List(maxSplats * 4), _srcS = Float32List(maxSplats * 4);
  final Int32List _colsS = Int32List(maxSplats);

  // Per-player motion tracking for squash-and-stretch.
  final Float64List _lx = Float64List(_maxIds), _ly = Float64List(_maxIds), _st = Float64List(_maxIds);
  final List<SimPlayer> _alive = [];

  // Visible world rect (inflated) for culling, refreshed each render.
  double _vl = -1e9, _vt = -1e9, _vr = 1e9, _vb = 1e9;

  final Paint _trailFill = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  final Paint _trailEdge = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  final Paint _trailGlow = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  final Paint _ringPaint = Paint()..style = PaintingStyle.stroke;
  final Paint _p = Paint();
  final Paint _atlasPaint = Paint()..filterQuality = FilterQuality.low;
  final Paint _addPaint = Paint()
    ..filterQuality = FilterQuality.low
    ..blendMode = BlendMode.plus;
  final Paint _textLayer = Paint();
  final Path _path = Path();
  final Map<int, Paint> _halos = {};
  final Map<int, Paint> _pools = {};

  Simulation get sim => game.sim;

  @override
  void update(double dt) {
    _time += dt;
    final sdt = dt * timeScale;
    var live = 0;
    for (final p in _pool) {
      if (p.life <= 0) continue;
      p.life -= sdt;
      if (p.life <= 0) continue;
      live++;
      if (p.kind == _ring) continue;
      final d = math.max(0.0, 1 - sdt * p.drag);
      p.vx *= d;
      p.vy = p.vy * d + p.grav * sdt;
      p.x += p.vx * sdt;
      p.y += p.vy * sdt;
      p.rot += p.spin * sdt;
      if (p.kind == _confetti) p.x += math.sin(p.rot * 1.7) * 38 * sdt;
    }
    _live = live;
    var ls = 0;
    for (final s in _splats) {
      if (s.life <= 0) continue;
      s.life -= sdt;
      if (s.life > 0) ls++;
    }
    _liveSplats = ls;
    for (final t in _texts) {
      t.age += dt;
      t.y -= dt * 1.1;
    }
    if (_texts.isNotEmpty) _texts.removeWhere((t) => t.age > 1.3);
    _trackMotion(dt);
    _emitSpray(sdt);
    _sinceRaster += dt;
    if (_terrFade < 1) _terrFade = math.min(1, _terrFade + dt / 0.2);
    if (!_rastering && _rasterVersion != sim.arena.version && _sinceRaster > 0.1) _rasterTerritory();
  }

  Future<void> _rasterTerritory() async {
    _rastering = true;
    _sinceRaster = 0;
    final a = sim.arena;
    final version = a.version;
    final colors = Int32List(Arena.maxPlayers + 1), darks = Int32List(Arena.maxPlayers + 1);
    for (final p in sim.players) {
      if (p.id <= Arena.maxPlayers) {
        colors[p.id] = p.skin.color;
        darks[p.id] = p.skin.dark;
      }
    }
    final job = TerritoryRasterJob(
      owner: Uint8List.fromList(a.owner),
      width: a.width,
      height: a.height,
      colors: colors,
      darks: darks,
      pixelsPerCell: _rpx.toInt(),
    );
    ui.Image? base;
    try {
      // CPU raster in a background isolate keeps the frame thread free.
      final pixels = await Isolate.run(() => rasterTerritory(job));
      if (_removed) return;
      final buf = await ui.ImmutableBuffer.fromUint8List(pixels);
      final desc = ui.ImageDescriptor.raw(buf,
          width: job.imageWidth, height: job.imageHeight, pixelFormat: ui.PixelFormat.rgba8888);
      final codec = await desc.instantiateCodec();
      base = (await codec.getNextFrame()).image;
      codec.dispose();
      desc.dispose();
      buf.dispose();
      final rec = ui.PictureRecorder();
      final cv = Canvas(rec);
      cv.drawImage(base, Offset.zero, _imgPaint..color = const Color(0xFFFFFFFF));
      _paintSprinkles(cv, _rpx);
      final pic = rec.endRecording();
      final img = await pic.toImage(job.imageWidth, job.imageHeight);
      pic.dispose();
      if (_removed) {
        img.dispose();
        return;
      }
      _prevImg?.dispose();
      _prevImg = _terrImg;
      _terrImg = img;
      _terrFade = _prevImg == null ? 1 : 0;
      _rasterVersion = version;
    } catch (_) {
      // Keep using the vector territory picture.
      _rasterVersion = version;
    } finally {
      base?.dispose();
      _rastering = false;
    }
  }

  void _trackMotion(double dt) {
    if (dt <= 0) return;
    final k = 1 - math.pow(0.002, dt).toDouble();
    for (final p in sim.players) {
      final id = p.id;
      if (id < 0 || id >= _maxIds) continue;
      if (!p.alive) {
        _st[id] = 0;
        _lx[id] = p.x;
        _ly[id] = p.y;
        continue;
      }
      final dx = p.x - _lx[id], dy = p.y - _ly[id];
      final v = math.sqrt(dx * dx + dy * dy) / dt;
      _lx[id] = p.x;
      _ly[id] = p.y;
      // Ignore teleports (respawn); otherwise stretch with speed.
      final target = v > p.speed * 4 ? 0.0 : (v / math.max(p.speed, 1) * 0.32).clamp(0.0, 0.45);
      _st[id] += (target - _st[id]) * k;
    }
  }

  void _emitSpray(double sdt) {
    _sprayTimer -= sdt;
    if (_sprayTimer > 0) return;
    _sprayTimer = 0.06;
    for (final p in sim.players) {
      if (!p.alive || !p.hasTrail) continue;
      final x = p.x * c, y = p.y * c;
      if (!_onScreen(x, y, c)) continue;
      final cs = math.cos(p.heading), sn = math.sin(p.heading);
      final side = (_rng.nextDouble() - 0.5) * 2;
      _spawn(_spray, x - cs * c * 0.45 + sn * side * c * 0.2, y - sn * c * 0.45 - cs * side * c * 0.2,
          vx: -cs * 50 + sn * side * 40, vy: -sn * 50 - cs * side * 40,
          life: 0.35 + _rng.nextDouble() * 0.2, size: c * (0.16 + _rng.nextDouble() * 0.12),
          color: p.skin.light, drag: 3);
    }
  }

  // ---- effects API -----------------------------------------------------

  bool _onScreen(double x, double y, double margin) =>
      x > _vl - margin && x < _vr + margin && y > _vt - margin && y < _vb + margin;

  void _spawn(int kind, double x, double y,
      {double vx = 0,
      double vy = 0,
      double life = 0.7,
      double size = 6,
      int color = 0xFFFFFFFF,
      double grav = 0,
      double drag = 2.5,
      double spin = 0}) {
    final p = _pool[_nextParticle];
    _nextParticle = (_nextParticle + 1) % maxParticles;
    if (p.life <= 0) _live++;
    p
      ..kind = kind
      ..x = x
      ..y = y
      ..vx = vx
      ..vy = vy
      ..maxLife = life
      ..life = life
      ..size = size
      ..color = color
      ..grav = grav
      ..drag = drag
      ..rot = _rng.nextDouble() * math.pi * 2
      ..spin = spin;
  }

  void _emit(double x, double y, int color, int n, double speed, double size,
      {double life = 0.7, int kind = _drop, double grav = 260, double drag = 2.5, double lift = 0.4}) {
    for (var i = 0; i < n; i++) {
      final a = _rng.nextDouble() * math.pi * 2;
      final v = speed * (0.35 + _rng.nextDouble() * 0.65);
      _spawn(kind, x, y,
          vx: math.cos(a) * v,
          vy: math.sin(a) * v - speed * lift,
          life: life * (0.6 + _rng.nextDouble() * 0.6),
          size: size * (0.5 + _rng.nextDouble()),
          color: color,
          grav: grav,
          drag: drag,
          spin: kind == _confetti ? (_rng.nextDouble() - 0.5) * 14 : (_rng.nextDouble() - 0.5) * 4);
    }
  }

  void _shockwave(double x, double y, int color, double size, {double life = 0.55}) {
    _spawn(_ring, x, y, life: life, size: size, color: color);
  }

  void _splat(double x, double y, int color, double size) {
    final s = _splats[_nextSplat];
    _nextSplat = (_nextSplat + 1) % maxSplats;
    if (s.life <= 0) _liveSplats++;
    s
      ..x = x
      ..y = y
      ..size = size
      ..color = color
      ..rot = _rng.nextDouble() * math.pi * 2
      ..maxLife = 2.8 + _rng.nextDouble() * 0.8
      ..life = s.maxLife;
  }

  void onCapture(SimPlayer p, int cells) {
    final x = p.x * c, y = p.y * c;
    if (!p.isHuman && !_onScreen(x, y, c * 4)) return;
    final n = (8 + cells / 6).clamp(8, 46).round();
    final big = cells >= sim.arena.cellCount * 0.04;
    _emit(x, y, p.skin.color, n, 340, 9);
    _emit(x, y, 0xFFFFFFFF, n ~/ 3, 260, 6);
    _emit(x, y, 0xFFFFF4C2, n ~/ 4, 300, c * 0.35, kind: _glint, grav: 0, drag: 3.5, lift: 0, life: 0.6);
    _shockwave(x, y, p.skin.light, c * (2 + math.min(cells / 40, 5)));
    if (big) {
      _shockwave(x, y, 0xFFFFFFFF, c * 9, life: 0.8);
      _emit(x, y, p.skin.light, 18, 520, 11, life: 0.9);
    }
  }

  /// Ink Splash power: big paint burst around the player.
  void onPowerSplash(SimPlayer p, int cells) {
    final x = p.x * c, y = p.y * c;
    _splat(x, y, p.skin.color, c * 3.4);
    _emit(x, y, p.skin.color, 40, 620, 12, life: 0.9);
    _emit(x, y, p.skin.light, 22, 420, 9);
    _emit(x, y, 0xFFFFF4C2, 14, 380, c * 0.4, kind: _glint, grav: 0, drag: 3, lift: 0, life: 0.7);
    _shockwave(x, y, 0xFFFFFFFF, c * 7, life: 0.7);
    _shockwave(x, y, p.skin.light, c * 4.5, life: 0.55);
  }

  /// Bonus pickup collected: sparkle burst in the pickup's colours.
  void onPickup(Pickup p) {
    final x = p.x * c, y = p.y * c - c * 0.4;
    final gem = p.kind == PickupKind.gem;
    _emit(x, y, gem ? 0xFFE070FF : 0xFFFFC928, gem ? 14 : 9, 260, 7, life: 0.6);
    _emit(x, y, 0xFFFFF4C2, 5, 220, c * 0.3, kind: _glint, grav: 0, drag: 3.5, lift: 0, life: 0.45);
  }

  void onDeath(SimPlayer p, double x, double y) {
    final wx = x * c, wy = y * c;
    if (!p.isHuman && !_onScreen(wx, wy, c * 4)) return;
    _emit(wx, wy, p.skin.color, 36, 520, 12, life: 0.9);
    _emit(wx, wy, p.skin.dark, 14, 380, 9, life: 0.9);
    _emit(wx, wy, 0xFFFFFFFF, 8, 300, c * 0.3, kind: _glint, grav: 0, drag: 3, lift: 0, life: 0.5);
    _shockwave(wx, wy, p.skin.color, c * 4);
    _splat(wx, wy, p.skin.color, c * 2.1);
    for (var i = 0; i < 3; i++) {
      final a = _rng.nextDouble() * math.pi * 2, r = c * (1.1 + _rng.nextDouble() * 1.2);
      _splat(wx + math.cos(a) * r, wy + math.sin(a) * r, i == 0 ? p.skin.dark : p.skin.color,
          c * (0.6 + _rng.nextDouble() * 0.5));
    }
  }

  void onSpawn(SimPlayer p) {
    if (p.id >= 0 && p.id < _maxIds) {
      _lx[p.id] = p.x;
      _ly[p.id] = p.y;
      _st[p.id] = 0;
    }
    final x = p.x * c, y = p.y * c;
    if (!p.isHuman && !_onScreen(x, y, c * 4)) return;
    _emit(x, y, p.skin.light, 14, 220, 7);
    _emit(x, y, p.skin.light, 6, 120, c * 0.5, kind: _spray, grav: 0, drag: 3, lift: 0, life: 0.5);
    _shockwave(x, y, p.skin.light, c * 2.2, life: 0.45);
  }

  void celebrate(SimPlayer p) {
    final x = p.x * c, y = p.y * c;
    const colors = [0xFFFFC928, 0xFFFF4FA3, 0xFF2EB7FF, 0xFF7EDB3A];
    for (var i = 0; i < 4; i++) {
      _emit(x, y, colors[i], 22, 640, 11, life: 1.6, kind: _confetti, grav: 220, drag: 1.8, lift: 0.7);
    }
    _emit(x, y, 0xFFFFF4C2, 16, 420, c * 0.45, kind: _glint, grav: 0, drag: 2.5, lift: 0, life: 1.0);
    _shockwave(x, y, 0xFFFFFFFF, c * 8, life: 0.9);
    _shockwave(x, y, p.skin.light, c * 5, life: 0.7);
    floatText('TARGET REACHED!', p.x, p.y - 2.2, 0xFFFFFFFF, big: true);
  }

  void floatText(String text, double x, double y, int color, {bool big = false}) {
    final style = TextStyle(
      fontFamily: 'Lilita',
      fontSize: big ? 30 : 24,
      color: col(color),
      shadows: const [
        Shadow(color: Color(0xFF16204A), offset: Offset(0, 3), blurRadius: 0),
        Shadow(color: Color(0x8816204A), offset: Offset(0, 0), blurRadius: 6),
      ],
    );
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    if (_texts.length > 6) _texts.removeAt(0);
    _texts.add(_FloatText(tp, x, y));
  }

  // ---- rendering ---------------------------------------------------------

  @override
  void render(Canvas canvas) {
    final vis = game.camera.visibleWorldRect;
    _vl = vis.left - c;
    _vt = vis.top - c;
    _vr = vis.right + c;
    _vb = vis.bottom + c;
    _renderWater(canvas);
    _floorPic ??= _recordFloor();
    canvas.drawPicture(_floorPic!);
    final img = _terrImg;
    if (img != null) {
      final dst = Rect.fromLTWH(0, 0, sim.arena.width * c, (sim.arena.height + 1) * c);
      final prev = _prevImg;
      if (prev != null && _terrFade < 1) {
        _imgPaint.color = const Color(0xFFFFFFFF);
        canvas.drawImageRect(prev, Rect.fromLTWH(0, 0, prev.width.toDouble(), prev.height.toDouble()), dst, _imgPaint);
        _imgPaint.color = Color.fromARGB((_terrFade * 255).round(), 255, 255, 255);
      } else {
        _imgPaint.color = const Color(0xFFFFFFFF);
      }
      canvas.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()), dst, _imgPaint);
    } else {
      if (_territoryVersion != sim.arena.version || _territoryPic == null) {
        _territoryPic?.dispose();
        _territoryPic = _recordTerritory();
        _territoryVersion = sim.arena.version;
      }
      canvas.drawPicture(_territoryPic!);
    }
    _atlas ??= _buildAtlas();
    if (_liveSplats > 0) _renderSplats(canvas);
    _renderTrails(canvas);
    final b = game.bonus;
    if (b != null) _renderPickups(canvas, b);
    _renderPlayers(canvas);
    if (_live > 0) _renderParticles(canvas);
    for (final t in _texts) {
      final a = (t.age < 0.15 ? t.age / 0.15 : (t.age > 0.9 ? (1.3 - t.age) / 0.4 : 1.0)).clamp(0.0, 1.0);
      final pop = t.age < 0.15 ? t.age / 0.15 : 1.0;
      final scale = t.age < 0.15 ? 0.6 + 0.55 * pop - 0.15 * pop * pop : 1.0;
      canvas.save();
      canvas.translate(t.x * c, t.y * c);
      canvas.scale(scale);
      final layered = a < 0.99;
      if (layered) {
        _textLayer.color = fade(0xFFFFFFFF, a);
        canvas.saveLayer(null, _textLayer);
      }
      t.painter.paint(canvas, Offset(-t.painter.width / 2, -t.painter.height / 2));
      if (layered) canvas.restore();
      canvas.restore();
    }
  }

  ui.Picture _recordFloor() {
    final rec = ui.PictureRecorder();
    final cv = Canvas(rec);
    final w = sim.arena.width * c, h = sim.arena.height * c;
    // Island: shadowed underside in the water, a light shelf, then the rim.
    cv.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(-c * 0.6, -c * 0.6, w + c * 1.2, h + c * 1.9),
            const Radius.circular(c)),
        Paint()..color = col(0xFF2A9CC7));
    cv.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(-c * 0.6, -c * 0.6, w + c * 1.2, h + c * 1.5),
            const Radius.circular(c)),
        Paint()..color = col(0xFFB9E8F7));
    cv.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(-c * 0.6, -c * 0.6, w + c * 1.2, h + c * 1.2),
            const Radius.circular(c)),
        Paint()..color = col(Palette.white));
    cv.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = col(Palette.floor));
    // Soft checker tiles (4x4 cells) for a sense of speed.
    final alt = Paint()..color = col(Palette.floorAlt);
    const t = 4;
    for (var ty = 0; ty < sim.arena.height; ty += t) {
      for (var tx = 0; tx < sim.arena.width; tx += t) {
        if (((tx ~/ t) + (ty ~/ t)).isEven) continue;
        cv.drawRect(
            Rect.fromLTWH(tx * c, ty * c, math.min(t, sim.arena.width - tx) * c,
                math.min(t, sim.arena.height - ty) * c),
            alt);
      }
    }
    return rec.endRecording();
  }

  ui.Picture _recordTerritory() {
    final rec = ui.PictureRecorder();
    final cv = Canvas(rec);
    final a = sim.arena;
    final w = a.width, h = a.height;
    final owner = a.owner;
    const r = Radius.circular(c * 0.42);
    // Pass 0: darker "thickness" offset downwards; pass 1: top color.
    for (var pass = 0; pass < 2; pass++) {
      for (final p in sim.players) {
        if (a.counts[p.id] == 0) continue;
        _p.color = col(pass == 0 ? p.skin.dark : p.skin.color);
        final dy = pass == 0 ? c * 0.28 : 0.0;
        for (var y = 0; y < h; y++) {
          var x = 0;
          final row = y * w;
          while (x < w) {
            if (owner[row + x] != p.id) {
              x++;
              continue;
            }
            final x0 = x;
            while (x < w && owner[row + x] == p.id) {
              x++;
            }
            cv.drawRRect(
                RRect.fromLTRBR(x0 * c - c * 0.08, y * c - c * 0.22 + dy, x * c + c * 0.08,
                    (y + 1) * c + c * 0.22 + dy, r),
                _p);
          }
        }
      }
    }
    _paintSprinkles(cv, c);
    return rec.endRecording();
  }

  /// Deterministic per-cell texture sprinkles; [k] is pixels per cell.
  void _paintSprinkles(Canvas cv, double k) {
    final owner = sim.arena.owner, w = sim.arena.width;
    for (var i = 0; i < owner.length; i++) {
      final o = owner[i];
      if (o == 0) continue;
      final hsh = (i * 2654435761) & 0xFFFFFFFF;
      if (hsh % 11 != 0) continue;
      final p = sim.byId(o);
      if (p == null) continue;
      final x = (i % w) * k, y = (i ~/ w) * k;
      final ox = ((hsh >> 8) % 100) / 100 * k * 0.6 + k * 0.2;
      final oy = ((hsh >> 16) % 100) / 100 * k * 0.6 + k * 0.2;
      _p.color = fade((hsh >> 4).isEven ? p.skin.light : 0xFFFFFFFF, 0.75);
      cv.save();
      cv.translate(x + ox, y + oy);
      cv.rotate(((hsh >> 12) % 6) * 0.5);
      cv.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(center: Offset.zero, width: k * 0.34, height: k * 0.12), Radius.circular(k * 0.06)),
          _p);
      cv.restore();
    }
  }

  /// Animated foam rings around the island (two strokes per frame).
  void _renderWater(Canvas canvas) {
    final w = sim.arena.width * c, h = sim.arena.height * c;
    for (var i = 0; i < 2; i++) {
      final grow = c * (1.3 + i * 1.1 + 0.18 * math.sin(_time * 1.6 + i * 1.7));
      _foam
        ..color = fade(0xFFFFFFFF, i == 0 ? 0.55 : 0.28)
        ..strokeWidth = c * (i == 0 ? 0.32 : 0.22);
      canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTRB(-grow, -grow, w + grow, h + grow + c * 0.6), Radius.circular(c + grow)),
          _foam);
    }
  }

  ui.Image _buildAtlas() {
    final rec = ui.PictureRecorder();
    final cv = Canvas(rec);
    final paint = Paint();
    // 0: ink droplet with a highlight.
    paint.color = const Color(0xFFE2E2E2);
    cv.drawCircle(const Offset(_half, _half), 29, paint);
    paint.color = const Color(0xFFFFFFFF);
    cv.drawCircle(const Offset(_half - 9, _half - 9), 8, paint);
    // 1: soft dot.
    paint.shader = ui.Gradient.radial(const Offset(_sp + _half, _half), 30,
        const [Color(0xFFFFFFFF), Color(0x88FFFFFF), Color(0x00FFFFFF)], const [0, 0.35, 1]);
    cv.drawCircle(const Offset(_sp + _half, _half), 30, paint);
    // 3: four-point star with a soft core.
    paint.shader = ui.Gradient.radial(const Offset(_sp * 3 + _half, _half), 30,
        const [Color(0xFFFFFFFF), Color(0x55FFFFFF), Color(0x00FFFFFF)], const [0, 0.3, 1]);
    cv.drawCircle(const Offset(_sp * 3 + _half, _half), 30, paint);
    paint.shader = null;
    paint.color = const Color(0xFFFFFFFF);
    final star = Path();
    for (var i = 0; i < 8; i++) {
      final r = i.isEven ? 30.0 : 6.0;
      final a = i * math.pi / 4 - math.pi / 2;
      final px = _sp * 3 + _half + math.cos(a) * r, py = _half + math.sin(a) * r;
      if (i == 0) {
        star.moveTo(px, py);
      } else {
        star.lineTo(px, py);
      }
    }
    cv.drawPath(star..close(), paint);
    // 2: confetti strip.
    cv.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(center: const Offset(_sp * 2 + _half, _half), width: 54, height: 28),
            const Radius.circular(6)),
        paint);
    // 4: ink splat (blob + satellite drops).
    const sx = _sp * 4 + _half;
    cv.drawCircle(const Offset(sx, _half), 19, paint);
    for (var i = 0; i < 7; i++) {
      final a = i * 0.9 + 0.3;
      final r = 15.0 + (i * 37 % 7);
      cv.drawCircle(Offset(sx + math.cos(a) * r, _half + math.sin(a) * r), 4.0 + (i * 13 % 5), paint);
    }
    final pic = rec.endRecording();
    final img = pic.toImageSync((_sp * 5).toInt(), _sp.toInt());
    pic.dispose();
    return img;
  }

  static void _put(Float32List xf, Float32List src, Int32List cols, int i, double x, double y,
      double scale, double rot, int sprite, int argb) {
    final sc = scale * math.cos(rot), ss = scale * math.sin(rot);
    final j = i * 4;
    xf[j] = sc;
    xf[j + 1] = ss;
    xf[j + 2] = x - sc * _half + ss * _half;
    xf[j + 3] = y - ss * _half - sc * _half;
    src[j] = sprite * _sp;
    src[j + 1] = 0;
    src[j + 2] = sprite * _sp + _sp;
    src[j + 3] = _sp;
    cols[i] = argb;
  }

  static int _alpha(int argb, double a) =>
      (argb & 0x00FFFFFF) | ((a.clamp(0.0, 1.0) * 255).round() << 24);

  void _drawBatch(Canvas canvas, Float32List xf, Float32List src, Int32List cols, int n, Paint paint) {
    if (n == 0) return;
    canvas.drawRawAtlas(_atlas!, Float32List.sublistView(xf, 0, n * 4), Float32List.sublistView(src, 0, n * 4),
        Int32List.sublistView(cols, 0, n), BlendMode.modulate, null, paint);
  }

  void _renderSplats(Canvas canvas) {
    var n = 0;
    for (final s in _splats) {
      if (s.life <= 0 || !_onScreen(s.x, s.y, s.size)) continue;
      final age = s.maxLife - s.life;
      final grow = age < 0.12 ? age / 0.12 : 1.0;
      final scale = s.size / _half * (0.5 + 0.5 * grow + 0.08 * math.sin(math.min(age * 9, math.pi)));
      final a = math.min(1.0, s.life / 0.7) * 0.9;
      _put(_xfS, _srcS, _colsS, n++, s.x, s.y, scale, s.rot, _splatSprite, _alpha(s.color, a));
    }
    _drawBatch(canvas, _xfS, _srcS, _colsS, n, _atlasPaint);
  }

  Paint _halo(int color) => _halos.putIfAbsent(
      color,
      () => Paint()
        ..blendMode = BlendMode.screen
        ..shader = ui.Gradient.radial(Offset.zero, 64, [fade(color, 0.7), fade(color, 0.28), fade(color, 0)],
            const [0, 0.45, 1]));

  Paint _groundGlow(int color) => _pools.putIfAbsent(
      color,
      () => Paint()
        ..shader = ui.Gradient.radial(
            Offset.zero, 64, [fade(color, 0.42), fade(color, 0.16), fade(color, 0)], const [0, 0.55, 1]));

  void _renderTrails(Canvas canvas) {
    for (final p in sim.players) {
      if (!p.alive || p.trailPoints.length < 4) continue;
      final pts = p.trailPoints;
      final path = _path
        ..reset()
        ..moveTo(pts[0] * c, pts[1] * c);
      for (var i = 2; i < pts.length; i += 2) {
        path.lineTo(pts[i] * c, pts[i + 1] * c);
      }
      path.lineTo(p.x * c, p.y * c);
      final long = p.trailCells.length > 30;
      final pulse = 0.5 + 0.5 * math.sin(_time * 10);
      if (p.isHuman && long) {
        _trailGlow
          ..color = fade(0xFFFF3B3B, 0.22 + 0.22 * pulse)
          ..strokeWidth = c * (1.5 + 0.25 * pulse);
      } else {
        _trailGlow
          ..color = fade(p.skin.color, p.isHuman ? 0.26 : 0.18)
          ..strokeWidth = c * 1.3;
      }
      canvas.drawPath(path, _trailGlow);
      _trailEdge
        ..color = fade(p.skin.dark, 0.85)
        ..strokeWidth = c * 0.78;
      canvas.save();
      canvas.translate(0, c * 0.12);
      canvas.drawPath(path, _trailEdge);
      canvas.restore();
      _trailFill
        ..color = col(p.skin.light)
        ..strokeWidth = c * 0.62;
      canvas.drawPath(path, _trailFill);
      // Pulsing danger tint on long trails.
      if (long) {
        _trailFill
          ..color = fade(0xFFFFFFFF, 0.1 + 0.35 * pulse)
          ..strokeWidth = c * 0.22;
        canvas.drawPath(path, _trailFill);
      }
    }
  }

  void _renderPlayers(Canvas canvas) {
    _alive.clear();
    for (final p in sim.players) {
      if (p.alive) _alive.add(p);
    }
    _alive.sort((a, b) => a.y.compareTo(b.y));
    for (final p in _alive) {
      final x = p.x * c, y = p.y * c;
      if (!_onScreen(x, y, c * 2)) continue;
      final bob = math.sin(_time * 14 + p.id) * c * 0.04;
      final sq = p.sinceCapture < 0.45 ? math.sin(p.sinceCapture / 0.45 * math.pi) : 0.0;
      final Mood mood;
      if (p.sinceCapture < 0.8) {
        mood = Mood.excited;
      } else if (p.trailCells.length > 30) {
        mood = Mood.worried;
      } else if (p.hasTrail) {
        mood = Mood.focused;
      } else {
        mood = Mood.happy;
      }
      final tilt = math.cos(p.heading) * 0.12;
      final pulse = math.sin(_time * 4 + p.id);
      // Ground light pool + head halo (cached shaders, scaled unit gradients).
      canvas.save();
      canvas.translate(x, y + c * 0.35);
      canvas.scale(c * 1.1 / 64, c * 0.55 / 64);
      canvas.drawCircle(Offset.zero, 64, _groundGlow(p.skin.color));
      canvas.restore();
      final hr = c * (p.isHuman ? 1.15 + 0.1 * pulse : 0.95) * (1 + 0.25 * sq);
      canvas.save();
      canvas.translate(x, y - c * 0.2);
      canvas.scale(hr / 64);
      canvas.drawCircle(Offset.zero, 64, _halo(p.skin.light));
      canvas.restore();
      final st = p.id >= 0 && p.id < _maxIds ? _st[p.id] : 0.0;
      final steering = game.phase == MatchPhase.playing || game.phase == MatchPhase.bonus;
      if (p.isHuman && steering) _paintArrow(canvas, x, y, p.heading);
      paintBlob(canvas, Offset(x, y - c * 0.2 + bob), c * 1.5, p.skin,
          lookAngle: p.heading,
          squash: sq,
          mood: mood,
          tilt: tilt,
          time: _time,
          seed: p.id,
          stretch: st,
          glow: p.isHuman ? 0.55 + 0.25 * pulse : 0);
      if (p.isHuman && sim.powersEnabled && game.phase == MatchPhase.playing) {
        _paintPowerBubble(canvas, x, y + bob, sim.humanPower);
      }
      if (!p.isHuman) {
        final tp = _labels.putIfAbsent(p.id, () {
          return TextPainter(
            text: TextSpan(
              text: p.name,
              style: const TextStyle(
                fontFamily: 'Fredoka',
                fontSize: 15,
                color: Color(0xFFFFFFFF),
                fontVariations: [ui.FontVariation('wght', 600)],
                shadows: [Shadow(color: Color(0xCC16204A), offset: Offset(0, 1.5), blurRadius: 2)],
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
        });
        tp.paint(canvas, Offset(x - tp.width / 2, y - c * 1.6 - tp.height));
      }
    }
  }

  // ---- bonus pickups -----------------------------------------------------

  static final Paint _coinSide = Paint()..color = const Color(0xFFD08A0E);
  static final Paint _coinTop = Paint()..color = const Color(0xFFFFC928);
  static final Paint _pickEdge = Paint()
    ..style = PaintingStyle.stroke
    ..color = const Color(0xFF16204A);
  static final Paint _pickShadow = Paint()..color = const Color(0x3316204A);
  static final Paint _gemDark = Paint()..color = const Color(0xFF8E2BD6);
  static final Paint _gemMid = Paint()..color = const Color(0xFFC152F5);
  static final Paint _gemLight = Paint()..color = const Color(0xFFF2B8FF);
  static final Paint _gemRing = Paint()
    ..style = PaintingStyle.stroke
    ..color = const Color(0x88C152F5);
  final Paint _pickFade = Paint();
  final Path _gemShine = Path();

  void _renderPickups(Canvas canvas, BonusRound b) {
    _pickEdge.strokeWidth = c * 0.06;
    _gemRing.strokeWidth = c * 0.07;
    // Collected loot flies to the counter at the top of the screen.
    final vis = game.camera.visibleWorldRect;
    final tx = vis.center.dx, ty = vis.top + vis.height * 0.07;
    for (final p in b.pickups) {
      if (p.taken && p.takenAge > 0.5) continue;
      final x = p.x * c, y = p.y * c;
      if (!p.taken && !_onScreen(x, y, c * 2)) continue;
      final since = b.elapsed - p.delay;
      if (since < 0) continue; // not dropped in yet
      final bob = math.sin(_time * 3 + p.x * 1.3 + p.y) * c * 0.06;
      canvas.save();
      if (p.taken) {
        final t = (p.takenAge / 0.5).clamp(0.0, 1.0);
        final e = Curves.easeInCubic.transform(t);
        // Pop up first, then arc to the counter.
        final px = x + (tx - x) * e;
        final py = y + (ty - y) * e - math.sin(t * math.pi) * c * 1.4;
        canvas.translate(px, py);
        canvas.scale((1.25 - 0.75 * e).clamp(0.3, 1.25));
        if (t > 0.75) {
          _pickFade.color = Color.fromARGB(((1 - t) / 0.25 * 255).round().clamp(0, 255), 255, 255, 255);
          canvas.saveLayer(null, _pickFade);
        }
        if (p.kind == PickupKind.coins) {
          _paintSpinCoin(canvas, 0, -c * 0.5, c * 0.38, _time * 14 + p.x);
        } else {
          _paintGem(canvas, 0);
        }
        if (t > 0.75) canvas.restore();
        canvas.restore();
        continue;
      }
      // Drop in from above with a little bounce; the shadow grows as it lands.
      final d = (since / BonusRound.dropTime).clamp(0.0, 1.0);
      final fall = d >= 1 ? 0.0 : (1 - Curves.bounceOut.transform(d)) * c * 5;
      canvas.translate(x, y);
      if (d < 1) {
        canvas.save();
        canvas.scale(0.4 + 0.6 * d);
        canvas.drawOval(Rect.fromCenter(center: const Offset(0, c * 0.2), width: c * 0.9, height: c * 0.4), _pickShadow);
        canvas.restore();
      }
      canvas.translate(0, -fall);
      if (p.kind == PickupKind.coins) {
        _paintCoinStack(canvas, bob, p.x * 0.7 + p.y);
      } else {
        _paintGem(canvas, bob);
      }
      canvas.restore();
    }
  }

  static final Paint _coinRim = Paint()..color = const Color(0xFFB8740A);
  static final Paint _coinFace = Paint()..color = const Color(0xFFFFCB2E);
  static final Paint _coinInner = Paint()..color = const Color(0xFFFFDD5C);
  static final Paint _coinGlint = Paint()..color = const Color(0xDDFFFFFF);

  /// A single coin spinning on its vertical axis: the face narrows to the
  /// rim and back, showing its thickness edge-on, with a glint when it faces us.
  void _paintSpinCoin(Canvas canvas, double x, double y, double r, double phase) {
    final k = math.cos(phase);
    final w = r * 2 * k.abs().clamp(0.12, 1.0);
    final thick = r * 0.22 * math.sin(phase).abs() + r * 0.06;
    final side = k >= 0 ? 1.0 : -1.0;
    // Edge (thickness) behind the face.
    final rim = Rect.fromCenter(center: Offset(x + side * thick * 0.5, y), width: w + thick, height: r * 2);
    canvas.drawOval(rim, _coinRim);
    final face = Rect.fromCenter(center: Offset(x - side * thick * 0.2, y), width: w, height: r * 2);
    canvas.drawOval(face, _coinFace);
    canvas.drawOval(face.deflate(r * 0.22).inflate(0), _coinInner);
    _pickEdge.strokeWidth = c * 0.05;
    canvas.drawOval(face, _pickEdge);
    if (k.abs() > 0.45) {
      // Emblem rings + a highlight that slides across the face as it turns.
      final ew = w * 0.18, eh = r * 0.62;
      _pickEdge.strokeWidth = c * 0.035;
      canvas.drawOval(Rect.fromCenter(center: Offset(face.center.dx - w * 0.13, y), width: ew, height: eh), _pickEdge);
      canvas.drawOval(Rect.fromCenter(center: Offset(face.center.dx + w * 0.13, y), width: ew, height: eh), _pickEdge);
      final gx = face.center.dx + math.sin(phase) * w * 0.3;
      canvas.drawOval(Rect.fromCenter(center: Offset(gx - w * 0.15, y - r * 0.45), width: w * 0.16, height: r * 0.28), _coinGlint);
    }
    _pickEdge.strokeWidth = c * 0.06;
  }

  void _paintCoinStack(Canvas canvas, double bob, double seed) {
    final w = c * 0.8, h = c * 0.36, step = c * 0.17;
    canvas.drawOval(Rect.fromCenter(center: const Offset(0, c * 0.2), width: w * 1.15, height: h * 1.1), _pickShadow);
    for (var i = 0; i < 3; i++) {
      final cy = c * 0.1 - i * step;
      canvas.drawOval(Rect.fromCenter(center: Offset(0, cy + step * 0.5), width: w, height: h), _coinSide);
      canvas.drawRect(Rect.fromLTRB(-w / 2, cy, w / 2, cy + step * 0.5), _coinSide);
      final top = Rect.fromCenter(center: Offset(0, cy), width: w, height: h);
      canvas.drawOval(top, _coinTop);
      canvas.drawOval(top, _pickEdge);
    }
    // A coin spinning just above the stack, bobbing.
    _paintSpinCoin(canvas, 0, c * 0.1 - 3 * step - c * 0.42 + bob * 1.5, c * 0.3, _time * 4.5 + seed);
    // Occasional sparkle.
    final tw = math.sin(_time * 2.3 + seed * 3);
    if (tw > 0.85) {
      final sx = w * 0.32, sy = c * 0.1 - 2 * step;
      final a = (tw - 0.85) / 0.15;
      _arrow.color = fade(0xFFFFFFFF, a);
      final r1 = c * 0.16 * a, r2 = c * 0.04;
      canvas.drawPath(
          _path
            ..reset()
            ..moveTo(sx, sy - r1)
            ..lineTo(sx + r2, sy - r2)
            ..lineTo(sx + r1, sy)
            ..lineTo(sx + r2, sy + r2)
            ..lineTo(sx, sy + r1)
            ..lineTo(sx - r2, sy + r2)
            ..lineTo(sx - r1, sy)
            ..lineTo(sx - r2, sy - r2)
            ..close(),
          _arrow);
    }
  }

  void _paintGem(Canvas canvas, double bob) {
    canvas.drawOval(Rect.fromCenter(center: const Offset(0, c * 0.2), width: c * 0.95, height: c * 0.42), _gemRing);
    final y = -c * 0.45 + bob * 2;
    final r = c * 0.34;
    final path = _path..reset();
    for (var i = 0; i < 6; i++) {
      final a = math.pi / 6 + i * math.pi / 3;
      final px = math.cos(a) * r, py = y + math.sin(a) * r * 1.25;
      if (i == 0) {
        path.moveTo(px, py);
      } else {
        path.lineTo(px, py);
      }
    }
    path.close();
    canvas.drawPath(path, _gemDark);
    canvas.drawCircle(Offset(0, y), r * 0.72, _gemMid);
    _gemShine
      ..reset()
      ..moveTo(-r * 0.5, y - r * 0.2)
      ..lineTo(0, y - r * 0.85)
      ..lineTo(r * 0.5, y - r * 0.2)
      ..close();
    canvas.drawPath(_gemShine, _gemLight);
    canvas.drawPath(path, _pickEdge);
  }

  // ---- power charge bubble ---------------------------------------------

  static final Paint _bubbleBg = Paint()..color = const Color(0xEEFFFFFF);
  static final Paint _bubbleFill = Paint()..color = const Color(0xFFFF4FA3);
  static final Paint _bubbleGlow = Paint()..color = const Color(0x66FF4FA3);
  final Path _bubbleClip = Path();

  /// Pink bubble above the player that fills as the Ink Splash charges.
  void _paintPowerBubble(Canvas canvas, double x, double y, double charge) {
    final r = c * 0.42;
    final cy = y - c * 1.85;
    final ready = charge >= 1;
    if (ready) {
      canvas.drawCircle(Offset(x, cy), r * (1.35 + 0.15 * math.sin(_time * 8)), _bubbleGlow);
    }
    canvas.drawCircle(Offset(x, cy), r, _bubbleBg);
    canvas.save();
    _bubbleClip
      ..reset()
      ..addOval(Rect.fromCircle(center: Offset(x, cy), radius: r * 0.82));
    canvas.clipPath(_bubbleClip);
    final top = cy + r * 0.82 - r * 1.64 * charge;
    canvas.drawRect(Rect.fromLTRB(x - r, top, x + r, cy + r), _bubbleFill);
    canvas.restore();
    // Splat glyph.
    final g = _path
      ..reset()
      ..addOval(Rect.fromCircle(center: Offset(x, cy), radius: r * 0.32))
      ..addOval(Rect.fromCircle(center: Offset(x + r * 0.34, cy - r * 0.26), radius: r * 0.13))
      ..addOval(Rect.fromCircle(center: Offset(x - r * 0.36, cy + r * 0.22), radius: r * 0.1))
      ..addOval(Rect.fromCircle(center: Offset(x - r * 0.1, cy + r * 0.48), radius: r * 0.09));
    _arrow.color = ready ? const Color(0xFFFFFFFF) : const Color(0xCCFFFFFF);
    canvas.drawPath(g, _arrow);
    _pickEdge.strokeWidth = c * 0.07;
    canvas.drawCircle(Offset(x, cy), r, _pickEdge);
    _pickEdge.strokeWidth = c * 0.06;
  }

  /// Direction chevron in front of the human player.
  void _paintArrow(Canvas canvas, double x, double y, double heading) {
    final pulse = 0.5 + 0.5 * math.sin(_time * 6);
    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(heading);
    canvas.translate(c * (1.2 + 0.1 * pulse), 0);
    final path = _path
      ..reset()
      ..moveTo(c * 0.32, 0)
      ..lineTo(-c * 0.16, -c * 0.3)
      ..lineTo(-c * 0.04, 0)
      ..lineTo(-c * 0.16, c * 0.3)
      ..close();
    _arrowEdge
      ..color = fade(Palette.ink, 0.55)
      ..strokeWidth = c * 0.1;
    canvas.drawPath(path, _arrowEdge);
    _arrow.color = fade(0xFFFFFFFF, 0.8 + 0.2 * pulse);
    canvas.drawPath(path, _arrow);
    canvas.restore();
  }

  void _renderParticles(Canvas canvas) {
    var n = 0, na = 0;
    for (final p in _pool) {
      if (p.life <= 0) continue;
      final t = p.life / p.maxLife;
      if (p.kind == _ring) {
        if (!_onScreen(p.x, p.y, p.size)) continue;
        final u = 1 - t;
        final rad = p.size * (1 - (1 - u) * (1 - u) * (1 - u));
        _ringPaint
          ..color = fade(p.color, t * 0.85)
          ..strokeWidth = c * 0.34 * t + 1;
        canvas.drawCircle(Offset(p.x, p.y), rad, _ringPaint);
        continue;
      }
      if (!_onScreen(p.x, p.y, p.size * 2)) continue;
      switch (p.kind) {
        case _glint:
          final tw = 0.7 + 0.3 * math.sin(p.rot * 3);
          _put(_xfA, _srcA, _colsA, na++, p.x, p.y, p.size / _half * (0.3 + 0.7 * t) * tw, p.rot * 0.3, _glint,
              _alpha(p.color, t));
        case _spray:
          _put(_xf, _src, _cols, n++, p.x, p.y, p.size / _half * (1.4 - 0.6 * t), 0, _spray,
              _alpha(p.color, t * 0.75));
        case _confetti:
          // Flutter as it spins (atlas transforms are uniform-scale only).
          final flip = 0.35 + 0.65 * math.cos(p.rot * 2).abs();
          _put(_xf, _src, _cols, n++, p.x, p.y, p.size / _half * flip, p.rot, _confetti,
              _alpha(p.color, math.min(1, t * 2)));
        default:
          _put(_xf, _src, _cols, n++, p.x, p.y, p.size / _half * (0.4 + 0.6 * t), p.rot, _drop,
              _alpha(p.color, math.min(1, t * 1.5)));
      }
    }
    _drawBatch(canvas, _xf, _src, _cols, n, _atlasPaint);
    _drawBatch(canvas, _xfA, _srcA, _colsA, na, _addPaint);
  }

  @override
  void onRemove() {
    _removed = true;
    _terrImg?.dispose();
    _prevImg?.dispose();
    _terrImg = null;
    _prevImg = null;
    _floorPic?.dispose();
    _territoryPic?.dispose();
    _atlas?.dispose();
    _floorPic = null;
    _territoryPic = null;
    _atlas = null;
    super.onRemove();
  }
}
