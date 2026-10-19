import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app.dart';
import '../../game/event.dart';
import '../../game/sim/levels.dart';
import '../../game/sim/skins.dart';
import '../../game/world.dart';
import '../../game/world_map.dart';
import '../blob_painter.dart';
import '../flags.dart';
import '../map_painter.dart';
import '../palette.dart';
import '../widgets.dart';
import 'achievements_screen.dart';
import 'event_screen.dart';
import 'game_screen.dart';
import 'online_screen.dart';
import 'settings_screen.dart';
import 'skins_screen.dart';
import 'tutorial.dart';
import 'world_map_screen.dart';

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> with TickerProviderStateMixin {
  late final AnimationController _bob =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
  late final AnimationController _intro =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 750));
  late final TickerClock _clock = TickerClock(this);
  bool _started = false;
  Timer? _minute;
  WorldMapData? _map;

  @override
  void initState() {
    super.initState();
    WorldMapData.load().then((d) {
      if (mounted) setState(() => _map = d);
    });
    // Keeps the event countdown fresh and rolls over expired events.
    _minute = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      Services.of(context).store.refreshEvent();
      setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (reduceMotion(context)) {
      _intro.value = 1;
    } else {
      _intro.forward();
      _bob.repeat(reverse: true);
      _clock.start();
    }
  }

  @override
  void dispose() {
    _minute?.cancel();
    _bob.dispose();
    _intro.dispose();
    _clock.dispose();
    super.dispose();
  }

  /// Ignores taps that land while another route is already on top/animating in.
  bool get _isTop => ModalRoute.of(context)?.isCurrent ?? true;

  void _push(Widget page, Alignment origin, int ink) {
    if (!_isTop) return;
    Services.of(context).fx.tap();
    Navigator.of(context).push(inkRoute(page, origin: origin, ink: ink));
  }

  void _play() {
    if (!_isTop) return;
    final s = Services.of(context);
    s.fx.tap();
    Navigator.of(context).push(fadeRoute(GameScreen(level: s.store.level, country: s.store.selectedCountry)));
  }

  void _openMap() => _push(const WorldMapScreen(), const Alignment(0, -0.3), Palette.cyan);

  void _rankInfo() {
    final s = Services.of(context);
    s.fx.tap();
    s.store.update((st) => st.seenRank = st.rank);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Rank ${s.store.rank}'),
        content: Text('Earn XP by painting territory, splatting rivals and winning. '
            '${s.store.rankXpNeeded - s.store.rankXp} XP to rank ${s.store.rank + 1}.'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final services = Services.of(context);
    final store = services.store;
    Widget enter(double start, double end, Widget child,
            {Offset offset = const Offset(0, 28), double scale = 1, Curve curve = Curves.easeOutCubic}) =>
        StaggerIn(
            animation: _intro, start: start, end: end, offset: offset, scale: scale, curve: curve, child: child);
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const PaintBackground(),
          SafeArea(
            child: AnimatedBuilder(
              animation: store,
              builder: (context, _) {
                final cfg = LevelConfig.forLevel(store.level);
                final skin = skinById(store.selectedSkin);
                final ci = store.selectedCountry;
                final ev = store.currentEvent;
                return LayoutBuilder(builder: (context, box) {
                  final compact = box.maxHeight < 680;
                  return Column(children: [
                    // Currencies + quick buttons.
                    enter(
                      0,
                      0.45,
                      offset: const Offset(0, -24),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                        child: Row(children: [
                          Expanded(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Row(children: [
                                StatPill(
                                    key: const Key('coinCounter'),
                                    icon: Icons.monetization_on_rounded,
                                    value: compactNumber(store.coins)),
                                const SizedBox(width: 6),
                                StatPill(
                                    key: const Key('gemCounter'),
                                    icon: Icons.diamond_rounded,
                                    value: compactNumber(store.gems),
                                    iconColor: 0xFFE040FB),
                              ]),
                            ),
                          ),
                          const SizedBox(width: 6),
                          RoundIconButton(
                            key: const Key('onlineButton'),
                            icon: Icons.groups_rounded,
                            tooltip: 'Play online',
                            color: Palette.pink,
                            onTap: () => _push(const OnlineScreen(), const Alignment(0.2, -0.9), Palette.pink),
                          ),
                          const SizedBox(width: 6),
                          RoundIconButton(
                            key: const Key('awardsButton'),
                            icon: Icons.emoji_events_rounded,
                            tooltip: 'Awards',
                            color: 0xFFF29A1F,
                            onTap: () => _push(const AchievementsScreen(), const Alignment(0.55, -0.9), Palette.gold),
                          ),
                          const SizedBox(width: 6),
                          RoundIconButton(
                            key: const Key('settingsButton'),
                            icon: Icons.settings_rounded,
                            tooltip: 'Settings',
                            onTap: () => _push(const SettingsScreen(), const Alignment(0.85, -0.9), Palette.cyan),
                          ),
                        ]),
                      ),
                    ),
                    // Event button (left) under the bar.
                    enter(
                      0.05,
                      0.5,
                      offset: const Offset(-30, 0),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 12, top: 8),
                          child: _EventButton(
                            tokens: store.eventTokens,
                            remaining: formatRemaining(ev.remaining(store.now)),
                            claimable: List.generate(kMilestones.length, store.canClaim).any((x) => x),
                            onTap: () => _push(const EventScreen(), const Alignment(-0.8, -0.7), 0xFFFF8A2A),
                          ),
                        ),
                      ),
                    ),
                    // Country progress pill + island hero.
                    enter(
                      0.12,
                      0.6,
                      scale: 0.8,
                      curve: Curves.easeOutBack,
                      _CountryPill(
                        name: kCountries[ci].name,
                        iso: kCountries[ci].iso,
                        progress: store.countryProgress[ci],
                        onTap: _openMap,
                      ),
                    ),
                    Expanded(
                      child: enter(
                        0.18,
                        0.7,
                        scale: 0.6,
                        curve: Curves.easeOutBack,
                        GestureDetector(
                          key: const Key('heroIsland'),
                          onTap: _openMap,
                          child: _HeroIsland(
                            map: _map,
                            country: ci,
                            progress: store.countryProgress[ci],
                            skin: skin,
                            bob: _bob,
                            clock: _clock,
                          ),
                        ),
                      ),
                    ),
                    enter(
                      0.3,
                      0.75,
                      Column(children: [
                        Text('LEVEL ${cfg.level}', style: kTitle.copyWith(fontSize: compact ? 26 : 30)),
                        Text(
                          'Paint ${cfg.targetPercent.toStringAsFixed(0)}% of the arena  •  ${cfg.bots} rivals',
                          style: bodyStyle(15, color: Colors.white),
                        ),
                      ]),
                    ),
                    SizedBox(height: compact ? 6 : 10),
                    // Skins card | PLAY | Rank card.
                    enter(
                      0.4,
                      0.9,
                      offset: const Offset(0, 48),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: SizedBox(
                          height: compact ? 112 : 124,
                          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Expanded(
                              child: _SideCard(
                                key: const Key('skinsButton'),
                                color: Palette.pink,
                                dark: 0xFFC92A7A,
                                badge: store.newSkinCount > 0 || store.hasNewFeatured,
                                onTap: () => _push(const SkinsScreen(), const Alignment(-0.5, 0.55), Palette.pink),
                                child: Column(mainAxisSize: MainAxisSize.min, children: [
                                  BlobAvatar(skin: skin, size: 46, mood: Mood.happy),
                                  Text('SKINS', style: kTitle.copyWith(fontSize: 17)),
                                ]),
                              ),
                            ),
                            const SizedBox(width: 8),
                            RepaintBoundary(
                              child: AnimatedBuilder(
                                animation: _bob,
                                builder: (_, child) => Transform.scale(
                                  scale: 1 + 0.04 * Curves.easeInOut.transform(_bob.value),
                                  child: child,
                                ),
                                child: _PlayButton(key: const Key('playButton'), onTap: _play, size: compact ? 104 : 116),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _SideCard(
                                key: const Key('rankCard'),
                                color: 0xFF4ED872,
                                dark: 0xFF1F9440,
                                badge: store.hasUnseenRankUp,
                                onTap: _rankInfo,
                                child: SizedBox(
                                  width: 112,
                                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                                  Container(
                                    key: const Key('rankBadge'),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF29A1F),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.white, width: 2.5),
                                    ),
                                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                                      const Icon(Icons.star_rounded, size: 18, color: Colors.white),
                                      Text('${store.rank}', style: kTitle.copyWith(fontSize: 18)),
                                    ]),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(store.hasUnseenRankUp ? 'RANK UP!' : 'RANK',
                                      style: kTitle.copyWith(fontSize: 16)),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 8),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: LinearProgressIndicator(
                                        value: store.rankXp / math.max(1, store.rankXpNeeded),
                                        minHeight: 8,
                                        backgroundColor: const Color(0x5516204A),
                                        color: const Color(Palette.gold),
                                      ),
                                    ),
                                  ),
                                  Text('${store.rankXp} / ${store.rankXpNeeded} XP',
                                      style: bodyStyle(11, color: Colors.white)),
                                ]),
                                ),
                              ),
                            ),
                          ]),
                        ),
                      ),
                    ),
                    SizedBox(height: compact ? 6 : 10),
                    // Bottom bar.
                    enter(
                      0.5,
                      1,
                      offset: const Offset(0, 40),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                        child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                          RoundIconButton(
                            key: const Key('howToButton'),
                            icon: Icons.help_rounded,
                            tooltip: 'How to play',
                            color: Palette.purple,
                            onTap: () {
                              services.fx.tap();
                              showGeneralDialog<void>(
                                context: context,
                                barrierDismissible: true,
                                barrierLabel: 'Close',
                                barrierColor: const Color(0x8A000000),
                                transitionDuration: motion(context, const Duration(milliseconds: 260)),
                                pageBuilder: (_, __, ___) => const Dialog(
                                  backgroundColor: Colors.transparent,
                                  insetPadding: EdgeInsets.all(20),
                                  child: TutorialCard(),
                                ),
                                transitionBuilder: (_, a, __, child) {
                                  final t = Curves.easeOutBack.transform(a.value);
                                  return FadeTransition(
                                    opacity: a,
                                    child: Transform.scale(scale: 0.8 + 0.2 * t, child: child),
                                  );
                                },
                              );
                            },
                          ),
                          RoundIconButton(
                            key: const Key('eventNavButton'),
                            icon: Icons.water_drop_rounded,
                            tooltip: 'Ink Festival',
                            color: 0xFFFF8A2A,
                            onTap: () => _push(const EventScreen(), const Alignment(-0.2, 0.9), 0xFFFF8A2A),
                          ),
                          RoundIconButton(
                            key: const Key('mapButton'),
                            icon: Icons.public_rounded,
                            tooltip: 'World map',
                            color: Palette.green,
                            onTap: _openMap,
                          ),
                        ]),
                      ),
                    ),
                  ]);
                });
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 16920 -> "16.92K".
String compactNumber(int v) {
  if (v < 10000) return '$v';
  if (v < 1000000) return '${(v / 1000).toStringAsFixed(2)}K';
  return '${(v / 1000000).toStringAsFixed(2)}M';
}

class _EventButton extends StatelessWidget {
  const _EventButton({required this.tokens, required this.remaining, required this.claimable, required this.onTap});
  final int tokens;
  final String remaining;
  final bool claimable;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const Key('eventButton'),
      onTap: onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Stack(clipBehavior: Clip.none, children: [
          Container(
            width: 58,
            height: 50,
            decoration: BoxDecoration(
              color: const Color(0xFF7A46E8),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white, width: 3),
            ),
            child: const Icon(Icons.water_drop_rounded, color: Color(0xFFFFD21F), size: 30),
          ),
          Positioned(
            right: -8,
            top: -8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: claimable ? const Color(0xFFFF3B3B) : const Color(0xFF233A8B),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: Text(claimable ? '!' : '$tokens', style: kTitle.copyWith(fontSize: 13)),
            ),
          ),
        ]),
        const SizedBox(height: 3),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: const Color(0xFF2E6BE6), borderRadius: BorderRadius.circular(8)),
          child: Text(remaining, style: kTitle.copyWith(fontSize: 13)),
        ),
      ]),
    );
  }
}

class _CountryPill extends StatelessWidget {
  const _CountryPill({required this.name, required this.iso, required this.progress, required this.onTap});
  final String name;
  final String iso;
  final double progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const Key('countryPill'),
      onTap: onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(name, style: kTitle.copyWith(fontSize: 22)),
        Container(
          width: 230,
          height: 34,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(Palette.ink), width: 2.5),
          ),
          child: Row(children: [
            Expanded(
              child: Container(
                decoration:
                    BoxDecoration(color: const Color(0xFF1838B8), borderRadius: BorderRadius.circular(13)),
                alignment: Alignment.centerLeft,
                child: Stack(children: [
                  FractionallySizedBox(
                    widthFactor: (progress / 100).clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                          color: const Color(0xFF33C759), borderRadius: BorderRadius.circular(13)),
                    ),
                  ),
                  Center(
                    child: Text('${progress.toStringAsFixed(0)}%', style: kTitle.copyWith(fontSize: 16)),
                  ),
                ]),
              ),
            ),
            const SizedBox(width: 4),
            FlagIcon(iso: iso, width: 30),
          ]),
        ),
      ]),
    );
  }
}

class _HeroIsland extends StatelessWidget {
  const _HeroIsland({
    required this.map,
    required this.country,
    required this.progress,
    required this.skin,
    required this.bob,
    required this.clock,
  });
  final WorldMapData? map;
  final int country;
  final double progress;
  final Skin skin;
  final Animation<double> bob;
  final TickerClock clock;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final w = math.min(box.maxWidth * 0.98, 420.0), h = math.max(60.0, box.maxHeight * 0.86);
      final c = map?.playable[country];
      final avatar = math.min(box.maxHeight * 0.42, 120.0);
      return Stack(alignment: Alignment.center, children: [
        // Soft glow behind the island.
        Container(
          width: w,
          height: h,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [Color(0x66FFFFFF), Color(0x00FFFFFF)]),
          ),
        ),
        RepaintBoundary(
          child: SizedBox(
            width: w,
            height: h,
            child: c == null
                ? null
                : CustomPaint(painter: CountryIslandPainter(c, CountryLook(unlocked: true, progress: progress))),
          ),
        ),
        RepaintBoundary(
          child: AnimatedBuilder(
            animation: bob,
            builder: (_, child) => Transform.translate(
              offset: Offset(0, -avatar * 0.15 - 10 * Curves.easeInOut.transform(bob.value)),
              child: child,
            ),
            child: BlobAvatar(skin: skin, size: avatar, mood: Mood.excited, time: clock.time, seed: 7),
          ),
        ),
      ]);
    });
  }
}

class _SideCard extends StatefulWidget {
  const _SideCard({
    super.key,
    required this.color,
    required this.dark,
    required this.child,
    required this.onTap,
    this.badge = false,
  });
  final int color;
  final int dark;
  final Widget child;
  final VoidCallback onTap;
  final bool badge;

  @override
  State<_SideCard> createState() => _SideCardState();
}

class _SideCardState extends State<_SideCard> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.94 : 1,
        duration: Duration(milliseconds: _down ? 70 : 260),
        curve: _down ? Curves.easeOut : Curves.easeOutBack,
        child: Stack(clipBehavior: Clip.none, children: [
          Container(
            height: 104,
            decoration: BoxDecoration(
              color: Color(widget.color),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [BoxShadow(color: Color(widget.dark), offset: const Offset(0, 6))],
            ),
            padding: const EdgeInsets.all(4),
            alignment: Alignment.center,
            // Content scales down instead of overflowing on short screens.
            child: FittedBox(fit: BoxFit.scaleDown, child: widget.child),
          ),
          if (widget.badge)
            const Positioned(
              right: -6,
              top: -8,
              child: CircleAvatar(
                radius: 13,
                backgroundColor: Color(0xFFFF3B3B),
                child: Text('!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
              ),
            ),
        ]),
      ),
    );
  }
}

class _PlayButton extends StatefulWidget {
  const _PlayButton({super.key, required this.onTap, this.size = 116});
  final VoidCallback onTap;
  final double size;

  @override
  State<_PlayButton> createState() => _PlayButtonState();
}

class _PlayButtonState extends State<_PlayButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return Semantics(
      button: true,
      label: 'Play',
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? 0.9 : 1,
          duration: Duration(milliseconds: _down ? 70 : 280),
          curve: _down ? Curves.easeOut : Curves.easeOutBack,
          child: Container(
            width: s,
            height: s,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                center: Alignment(-0.3, -0.4),
                colors: [Color(0xFFFFF3A0), Color(0xFFFFD21F), Color(0xFFF2A900)],
                stops: [0, 0.55, 1],
              ),
              border: Border.all(color: const Color(Palette.ink), width: 4),
              boxShadow: const [BoxShadow(color: Color(0xFFB37800), offset: Offset(0, 7))],
            ),
            child: Icon(Icons.play_arrow_rounded, size: s * 0.66, color: const Color(Palette.ink)),
          ),
        ),
      ),
    );
  }
}

/// Route used for menu <-> game; now the shared ink-splash reveal.
Route<T> fadeRoute<T>(Widget page) => inkRoute<T>(page, origin: const Alignment(0, 0.45));
