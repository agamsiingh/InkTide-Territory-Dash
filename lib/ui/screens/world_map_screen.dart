import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app.dart';
import '../../game/world.dart';
import '../../game/world_map.dart';
import '../../services/feedback.dart';
import '../flags.dart';
import '../map_painter.dart';
import '../palette.dart';
import '../widgets.dart';
import 'event_screen.dart' show ConfettiBurstPainter;
import 'game_screen.dart';
import 'menu_screen.dart' show fadeRoute;

/// Zoomable, pannable world map for picking a campaign country.
class WorldMapScreen extends StatefulWidget {
  const WorldMapScreen({super.key});

  @override
  State<WorldMapScreen> createState() => WorldMapScreenState();
}

class WorldMapScreenState extends State<WorldMapScreen> with TickerProviderStateMixin {
  final TransformationController _tc = TransformationController();
  late final AnimationController _fly = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
  late final AnimationController _bob =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
  late final AnimationController _confetti =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));

  /// Country whose completion is being celebrated (banner + confetti).
  int? _celebrating;
  Animation<Matrix4>? _flyAnim;
  WorldMapData? _data;
  Size _view = Size.zero;
  int? _selected;
  bool _placed = false;

  /// Selected campaign index (exposed for tests).
  int? get selected => _selected;
  WorldMapData? get data => _data;

  @override
  void initState() {
    super.initState();
    _fly.addListener(() {
      final a = _flyAnim;
      if (a != null) _tc.value = a.value;
    });
    WorldMapData.load().then((d) {
      if (!mounted) return;
      setState(() => _data = d);
      _celebrate();
    });
  }

  /// Plays the completion celebration once for each newly finished country.
  Future<void> _celebrate() async {
    final s = Services.of(context);
    final done = await s.store.takeUncelebratedCountries();
    if (!mounted || done.isEmpty) return;
    final i = done.last;
    setState(() => _celebrating = i);
    s.fx.play(Sfx.countryComplete);
    s.fx.hapticHeavy();
    if (!reduceMotion(context)) _confetti.forward(from: 0);
    final d = _data;
    if (d != null) WidgetsBinding.instance.addPostFrameCallback((_) => _flyTo(d.playable[i]));
    await Future<void>.delayed(const Duration(milliseconds: 2400));
    if (mounted) setState(() => _celebrating = null);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _selected ??= Services.of(context).store.selectedCountry;
  }

  @override
  void dispose() {
    _fly.dispose();
    _bob.dispose();
    _confetti.dispose();
    _tc.dispose();
    super.dispose();
  }

  /// Open ocean around the map so edge countries (Canada, Australia) can be
  /// centred above the card.
  static const Offset _pad = Offset(160, 320);

  Size _padded(Size map) => Size(map.width + _pad.dx * 2, map.height + _pad.dy * 2);

  double _minScale(Size view, Size map) {
    final m = _padded(map);
    return math.max(view.width / m.width, view.height / m.height);
  }

  /// Matrix that centres [focus] (map units) at [scale], clamped to the map.
  Matrix4 _matrixFor(Offset focus, double scale) {
    final map = _padded(_data!.size);
    final s = scale.clamp(_minScale(_view, _data!.size), 8.0);
    final f = focus + _pad;
    var tx = _view.width / 2 - f.dx * s, ty = _view.height * 0.4 - f.dy * s;
    tx = tx.clamp(_view.width - map.width * s, 0.0);
    ty = ty.clamp(_view.height - map.height * s, 0.0);
    return Matrix4.identity()
      ..translateByDouble(tx, ty, 0, 1)
      ..scaleByDouble(s, s, 1, 1);
  }

  Matrix4 _matrixForCountry(MapCountry c) =>
      _matrixFor(c.bounds.center, math.min(_view.width * 0.8 / c.bounds.width, _view.height * 0.36 / c.bounds.height));

  void _flyTo(MapCountry c) {
    if (_view.isEmpty) return;
    _flyAnim = Matrix4Tween(begin: _tc.value.clone(), end: _matrixForCountry(c))
        .animate(CurvedAnimation(parent: _fly, curve: Curves.easeInOutCubic));
    _fly.forward(from: reduceMotion(context) ? 1 : 0);
  }

  /// Handles a tap at [scene] (map units).
  void tapAt(Offset scene) {
    final d = _data;
    if (d == null) return;
    final s = _tc.value.getMaxScaleOnAxis();
    final c = d.hitTest(scene, slop: 18 / s);
    final fx = Services.of(context).fx;
    if (c == null || !c.playable) {
      fx.tap();
      if (c != null) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('${c.name} is not on the campaign route yet.')));
      }
      return;
    }
    fx.tap();
    setState(() => _selected = c.order);
    _flyTo(c);
  }

  Future<void> _play() async {
    final s = Services.of(context);
    final i = _selected ?? s.store.selectedCountry;
    if (!s.store.isCountryUnlocked(i)) return;
    await s.store.selectCountry(i);
    s.fx.tap();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(fadeRoute(GameScreen(level: s.store.level, country: i)));
  }

  @override
  Widget build(BuildContext context) {
    final s = Services.of(context);
    final store = s.store;
    final d = _data;
    final cur = store.currentCountry;
    final continent = kCountries[cur].continent;
    final inContinent = countriesOf(continent);
    final doneHere = inContinent.where(store.isCountryComplete).length;
    final ci = kContinents.indexOf(continent);
    final nextContinent = ci + 1 < kContinents.length ? kContinents[ci + 1] : null;
    final nextPin = cur + 1 < kCountries.length && !store.isCountryUnlocked(cur + 1) ? cur + 1 : null;
    return Scaffold(
      backgroundColor: const Color(0xFF1DB4F0),
      body: Stack(fit: StackFit.expand, children: [
        if (d != null)
          LayoutBuilder(builder: (context, box) {
            _view = box.biggest;
            if (!_placed) {
              _placed = true;
              final c = d.playable[_selected ?? store.selectedCountry];
              _tc.value = _matrixForCountry(c);
            }
            final looks = {
              for (final c in d.playable)
                c.iso: CountryLook(
                  unlocked: store.isCountryUnlocked(c.order),
                  progress: store.countryProgress[c.order],
                  selected: c.order == _selected,
                ),
            };
            return Stack(children: [
              InteractiveViewer(
                key: const Key('worldMap'),
                transformationController: _tc,
                constrained: false,
                minScale: _minScale(box.biggest, d.size),
                maxScale: 8,
                boundaryMargin: EdgeInsets.zero,
                onInteractionStart: (_) => _fly.stop(),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (e) => tapAt(e.localPosition - _pad),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: _pad.dx, vertical: _pad.dy),
                    child: RepaintBoundary(
                      child: CustomPaint(size: d.size, painter: WorldMapPainter(d, looks)),
                    ),
                  ),
                ),
              ),
              // "Next" marker on the country after the current one.
              if (nextPin != null && nextPin != _selected)
                AnimatedBuilder(
                  animation: _tc,
                  builder: (context, _) {
                    final at = MatrixUtils.transformPoint(_tc.value, d.playable[nextPin].anchor + _pad);
                    return Positioned(
                      left: at.dx - 18,
                      top: at.dy - 48,
                      child: const IgnorePointer(child: _NextPin(key: Key('nextPin'))),
                    );
                  },
                ),
              // Pin stays the same size on screen while the map zooms.
              if (_selected != null)
                AnimatedBuilder(
                  animation: Listenable.merge([_tc, _bob]),
                  builder: (context, _) {
                    final c = d.playable[_selected!];
                    final at = MatrixUtils.transformPoint(_tc.value, c.anchor + _pad);
                    final up = 6 * Curves.easeInOut.transform(_bob.value);
                    return Positioned(
                      left: at.dx - 22,
                      top: at.dy - 60 - up,
                      child: IgnorePointer(child: _Pin(unlocked: store.isCountryUnlocked(c.order))),
                    );
                  },
                ),
            ]);
          })
        else
          const Center(child: CircularProgressIndicator(color: Colors.white)),
        Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: ConfettiBurstPainter(_confetti)))),
        SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: Row(children: [
                RoundIconButton(
                  key: const Key('backButton'),
                  icon: Icons.arrow_back_rounded,
                  tooltip: 'Back',
                  onTap: () {
                    s.fx.tap();
                    Navigator.of(context).pop();
                  },
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(Palette.ink), width: 2.5),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('Choose a country to fill!',
                          style: kTitle.copyWith(fontSize: 20, color: const Color(Palette.ink), shadows: [])),
                    ),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                key: const Key('worldProgress'),
                margin: const EdgeInsets.only(left: 14),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: const Color(0xEEFFFFFF), borderRadius: BorderRadius.circular(14)),
                child: _ContinentProgress(
                  title: nextContinent == null ? 'Fill the WORLD' : 'Unlock ${nextContinent.toUpperCase()}',
                  done: doneHere,
                  total: inContinent.length,
                ),
              ),
            ),
            if (_celebrating != null) ...[
              const SizedBox(height: 18),
              TweenAnimationBuilder<double>(
                key: ValueKey('celebrate_$_celebrating'),
                tween: Tween(begin: 0, end: 1),
                duration: motion(context, const Duration(milliseconds: 600)),
                curve: Curves.elasticOut,
                builder: (_, t, child) => Transform.scale(scale: t, child: child),
                child: Container(
                  key: const Key('mapCelebration'),
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF33C759),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white, width: 4),
                    boxShadow: const [BoxShadow(color: Color(0x5516204A), offset: Offset(0, 6))],
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    FlagIcon(iso: kCountries[_celebrating!].iso, width: 40),
                    const SizedBox(width: 10),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('${kCountries[_celebrating!].name} complete!', style: kTitle.copyWith(fontSize: 22)),
                      ),
                    ),
                  ]),
                ),
              ),
            ],
            const Spacer(),
            if (_selected != null)
              _CountryCard(
                index: _selected!,
                onPlay: _play,
              ),
          ]),
        ),
      ]),
    );
  }
}

/// "Unlock SOUTH AMERICA [==  ] 1/3" chip.
class _ContinentProgress extends StatelessWidget {
  const _ContinentProgress({required this.title, required this.done, required this.total});
  final String title;
  final int done;
  final int total;

  @override
  Widget build(BuildContext context) => Column(
        key: const Key('continentProgress'),
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: kTitle.copyWith(fontSize: 15, color: const Color(Palette.ink), shadows: [])),
          const SizedBox(height: 4),
          SizedBox(
            width: 140,
            height: 24,
            child: Stack(children: [
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1C5FA8),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(Palette.ink), width: 2),
                ),
              ),
              FractionallySizedBox(
                widthFactor: total == 0 ? 0 : (done / total).clamp(0.08, 1.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF4ED872),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(Palette.ink), width: 2),
                  ),
                ),
              ),
              Center(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('$done/$total', style: kTitle.copyWith(fontSize: 15)),
                  const SizedBox(width: 4),
                  const Icon(Icons.flag_rounded, size: 16, color: Colors.white),
                ]),
              ),
            ]),
          ),
        ],
      );
}

/// Yellow pin with a double arrow: "this one is next".
class _NextPin extends StatelessWidget {
  const _NextPin({super.key});

  @override
  Widget build(BuildContext context) => Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: const Color(0xFFFFC928),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(Palette.ink), width: 2.5),
          boxShadow: const [BoxShadow(color: Color(0x4416204A), offset: Offset(0, 3))],
        ),
        child: const Icon(Icons.fast_forward_rounded, color: Colors.white, size: 24),
      );
}

class _Pin extends StatelessWidget {
  const _Pin({required this.unlocked});
  final bool unlocked;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 44,
        height: 58,
        child: CustomPaint(painter: _PinPainter(unlocked)),
      );
}

class _PinPainter extends CustomPainter {
  _PinPainter(this.unlocked);
  final bool unlocked;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, r = w / 2;
    final path = Path()
      ..addArc(Rect.fromCircle(center: Offset(r, r), radius: r), math.pi * 0.8, math.pi * 1.4)
      ..lineTo(r, size.height)
      ..close();
    canvas.drawOval(Rect.fromCenter(center: Offset(r, size.height), width: w * 0.5, height: 6),
        Paint()..color = const Color(0x4416204A));
    canvas.drawPath(path, Paint()..color = const Color(Palette.ink));
    canvas.save();
    canvas.translate(r, r);
    canvas.scale(0.84);
    canvas.translate(-r, -r);
    canvas.drawPath(path, Paint()..color = Color(unlocked ? 0xFFFFC928 : 0xFFB0B8C8));
    canvas.restore();
    final ink = Paint()..color = const Color(Palette.ink);
    if (unlocked) {
      final tri = Path()
        ..moveTo(r - 6, r - 9)
        ..lineTo(r + 9, r)
        ..lineTo(r - 6, r + 9)
        ..close();
      canvas.drawPath(tri, Paint()..color = Colors.white);
      canvas.drawPath(
          tri,
          ink
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5
            ..strokeJoin = StrokeJoin.round);
    } else {
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(r, r + 3), width: 16, height: 12),
          const Radius.circular(3)), ink);
      canvas.drawArc(
          Rect.fromCenter(center: Offset(r, r - 3), width: 11, height: 12),
          math.pi,
          math.pi,
          false,
          Paint()
            ..color = const Color(Palette.ink)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3);
    }
  }

  @override
  bool shouldRepaint(covariant _PinPainter old) => old.unlocked != unlocked;
}

class _CountryCard extends StatelessWidget {
  const _CountryCard({required this.index, required this.onPlay});
  final int index;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final store = Services.of(context).store;
    final def = kCountries[index];
    final unlocked = store.isCountryUnlocked(index);
    final progress = store.countryProgress[index];
    final complete = progress >= 100;
    return AnimatedSwitcher(
      duration: motion(context, const Duration(milliseconds: 260)),
      transitionBuilder: (child, a) => SlideTransition(
          position: Tween(begin: const Offset(0, 0.4), end: Offset.zero).animate(a),
          child: FadeTransition(opacity: a, child: child)),
      child: Container(
        key: ValueKey('countryCard_${def.iso}'),
        margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(Palette.ink), width: 3),
          boxShadow: const [BoxShadow(color: Color(0x5516204A), offset: Offset(0, 6))],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            FlagIcon(iso: def.iso, width: 48),
            const SizedBox(width: 10),
            Expanded(
              child: Text(def.name,
                  key: const Key('countryName'),
                  style: kTitle.copyWith(fontSize: 24, color: const Color(Palette.ink), shadows: [])),
            ),
            if (complete) const Icon(Icons.check_circle_rounded, color: Color(Palette.green), size: 30),
          ]),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: progress / 100,
              minHeight: 16,
              backgroundColor: const Color(0xFFE2E8F0),
              color: const Color(0xFF33C759),
            ),
          ),
          const SizedBox(height: 4),
          Row(children: [
            Text('${progress.toStringAsFixed(0)}% filled', key: const Key('countryProgress'), style: bodyStyle(14)),
            const SizedBox(width: 8),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.monetization_on_rounded, size: 18, color: Color(Palette.yellow)),
                  Text(' ${def.coins}  ', style: bodyStyle(14)),
                  const Icon(Icons.diamond_rounded, size: 18, color: Color(0xFFE040FB)),
                  Text(' ${def.gems}', style: bodyStyle(14)),
                ]),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          if (unlocked)
            ChunkyButton(
              key: const Key('mapPlayButton'),
              label: complete ? 'PLAY AGAIN' : 'PLAY',
              icon: Icons.play_arrow_rounded,
              width: double.infinity,
              height: 58,
              onTap: onPlay,
            )
          else
            Container(
              key: const Key('lockedRequirement'),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(16)),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.lock_rounded, color: Color(0xFF6A7393)),
                const SizedBox(width: 6),
                Flexible(
                  child: Text('Fill ${kCountries[index - 1].name} to unlock',
                      style: bodyStyle(16, color: const Color(0xFF6A7393))),
                ),
              ]),
            ),
        ]),
      ),
    );
  }
}

/// Plays the country-complete fanfare (used by the results screen).
void playCountryComplete(GameFeedback fx) => fx.play(Sfx.countryComplete);
