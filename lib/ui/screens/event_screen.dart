import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app.dart';
import '../../game/event.dart';
import '../../game/sim/skins.dart';
import '../../services/feedback.dart';
import '../blob_painter.dart';
import '../palette.dart';
import '../widgets.dart';
import 'capsule_screen.dart';

/// "Ink Festival" timed event: a vertical milestone track of rewards.
class EventScreen extends StatefulWidget {
  const EventScreen({super.key});

  @override
  State<EventScreen> createState() => _EventScreenState();
}

class _EventScreenState extends State<EventScreen> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Countdown + expiry check.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!mounted) return;
      final store = Services.of(context).store;
      if (await store.refreshEvent() && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('A new Ink Festival has started!')));
      }
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Services.of(context).store.refreshEvent();
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _claim(int i) async {
    final s = Services.of(context);
    final m = await s.store.claimMilestone(i);
    if (m == null || !mounted) return;
    s.fx.play(Sfx.claim);
    s.fx.hapticLight();
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: const Color(0x8A000000),
      transitionDuration: motion(context, const Duration(milliseconds: 320)),
      pageBuilder: (_, __, ___) => RewardCardDialog(milestone: m),
      transitionBuilder: (_, a, __, child) => FadeTransition(
        opacity: a,
        child: Transform.scale(scale: 0.6 + 0.4 * Curves.easeOutBack.transform(a.value), child: child),
      ),
    );
    // A brand-new skin also gets the capsule reveal.
    final skin = m.kind == RewardKind.skin ? skinById(m.skinId!) : null;
    if (skin != null && mounted && s.store.isNewSkin(skin)) await CapsuleScreen.show(context, [skin]);
  }

  @override
  Widget build(BuildContext context) {
    final s = Services.of(context);
    final store = s.store;
    final ev = store.currentEvent;
    final left = ev.remaining(store.now);
    return Scaffold(
      body: Stack(fit: StackFit.expand, children: [
        const RepaintBoundary(child: CustomPaint(painter: _FestivalBackground())),
        SafeArea(
          child: AnimatedBuilder(
            animation: store,
            builder: (context, _) => Column(children: [
              const SizedBox(height: 4),
              _Sign(remaining: formatRemaining(left)),
              const SizedBox(height: 8),
              Expanded(
                child: _Track(
                  tokens: store.eventTokens,
                  claimed: store.eventClaimed,
                  canClaim: store.canClaim,
                  onClaim: _claim,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 12, top: 6),
                child: RoundIconButton(
                  key: const Key('closeEvent'),
                  icon: Icons.close_rounded,
                  tooltip: 'Close',
                  color: 0xFF2E6BE6,
                  onTap: () {
                    s.fx.tap();
                    Navigator.of(context).pop();
                  },
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _Sign extends StatelessWidget {
  const _Sign({required this.remaining});
  final String remaining;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(
        padding: const EdgeInsets.fromLTRB(26, 12, 26, 12),
        decoration: BoxDecoration(
          color: const Color(0xFFD9772B),
          borderRadius: BorderRadius.circular(40),
          border: Border.all(color: const Color(0xFF7A3A12), width: 4),
          boxShadow: const [BoxShadow(color: Color(0x5516204A), offset: Offset(0, 6))],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.water_drop_rounded, color: Color(0xFF9B5CFF), size: 34),
          Text('COLLECT', style: kTitle.copyWith(fontSize: 30)),
          Text('TO WIN', style: kTitle.copyWith(fontSize: 26, color: const Color(0xFFFFD21F))),
        ]),
      ),
      const SizedBox(height: 6),
      Container(
        key: const Key('eventCountdown'),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(color: const Color(0xFF233A8B), borderRadius: BorderRadius.circular(12)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.timer_rounded, color: Color(0xFFFFD21F), size: 18),
          const SizedBox(width: 4),
          Text(remaining, style: kTitle.copyWith(fontSize: 16)),
        ]),
      ),
    ]);
  }
}

class _Track extends StatelessWidget {
  const _Track({required this.tokens, required this.claimed, required this.canClaim, required this.onClaim});
  final int tokens;
  final Set<int> claimed;
  final bool Function(int) canClaim;
  final void Function(int) onClaim;

  /// Fill 0..1: milestones sit at even heights, interpolating between them.
  static double fillFor(int tokens) {
    final n = kMilestones.length;
    var prev = 0;
    for (var i = 0; i < n; i++) {
      final g = kMilestones[i].goal;
      if (tokens < g) return (i + (tokens - prev) / (g - prev)) / (n + 0.4);
      prev = g;
    }
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final h = box.maxHeight, w = box.maxWidth;
      const barW = 64.0;
      final barTop = 8.0, barBottom = h - 8;
      final barH = barBottom - barTop;
      final n = kMilestones.length;
      double yFor(int i) => barBottom - barH * (i + 1) / (n + 0.4);
      final fill = fillFor(tokens).clamp(0.0, 1.0);
      final markerY = barBottom - barH * fill;
      return Stack(clipBehavior: Clip.none, children: [
        // Bar.
        Positioned(
          left: w / 2 - barW / 2,
          top: barTop,
          width: barW,
          height: barH,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1838B8),
              borderRadius: BorderRadius.circular(barW / 2),
              border: Border.all(color: Colors.white, width: 5),
              boxShadow: const [BoxShadow(color: Color(0x5516204A), offset: Offset(0, 5))],
            ),
            alignment: Alignment.bottomCenter,
            padding: const EdgeInsets.all(6),
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: fill),
              duration: motion(context, const Duration(milliseconds: 800)),
              curve: Curves.easeOutCubic,
              builder: (_, v, __) => FractionallySizedBox(
                heightFactor: math.max(v, 0.02),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFFFFB061), Color(0xFFFF7A1A)]),
                    borderRadius: BorderRadius.circular(barW / 2),
                  ),
                ),
              ),
            ),
          ),
        ),
        for (var i = 0; i < n; i++) ...[
          Positioned(
            left: w / 2 - 26,
            top: yFor(i) - 13,
            child: Container(
              width: 52,
              height: 26,
              alignment: Alignment.center,
              child: Text('${kMilestones[i].goal}', style: kTitle.copyWith(fontSize: 18)),
            ),
          ),
          Positioned(
            left: i.isEven ? null : w / 2 + barW / 2 + 10,
            right: i.isEven ? w / 2 + barW / 2 + 10 : null,
            top: yFor(i) - 46,
            child: _RewardTile(
              key: Key('milestone_$i'),
              milestone: kMilestones[i],
              claimed: claimed.contains(i),
              claimable: canClaim(i),
              onClaim: () => onClaim(i),
            ),
          ),
        ],
        // Current tokens marker.
        Positioned(
          left: w / 2 - barW / 2 - 58,
          top: markerY - 26,
          child: Container(
            key: const Key('eventTokens'),
            width: 64,
            height: 52,
            decoration: BoxDecoration(
              color: const Color(0xFFFF8A2A),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: const Color(0xFF233A8B), width: 4),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.water_drop_rounded, color: Color(0xFF9B5CFF), size: 18),
              Flexible(
                child: FittedBox(child: Text('$tokens', style: kTitle.copyWith(fontSize: 20))),
              ),
            ]),
          ),
        ),
      ]);
    });
  }
}

class _RewardTile extends StatelessWidget {
  const _RewardTile({
    super.key,
    required this.milestone,
    required this.claimed,
    required this.claimable,
    required this.onClaim,
  });
  final Milestone milestone;
  final bool claimed;
  final bool claimable;
  final VoidCallback onClaim;

  @override
  Widget build(BuildContext context) {
    final bg = claimed ? const Color(0xFF5B3418) : const Color(0xFFC9692A);
    return GestureDetector(
      onTap: claimable ? onClaim : null,
      child: AnimatedScale(
        scale: claimable ? 1.06 : 1,
        duration: const Duration(milliseconds: 300),
        child: Container(
          width: 128,
          height: 92,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: claimable ? const Color(0xFFFFD21F) : const Color(0xFF7A3A12), width: 3.5),
            boxShadow: [
              const BoxShadow(color: Color(0x5516204A), offset: Offset(0, 5)),
              if (claimable) const BoxShadow(color: Color(0x99FFD21F), blurRadius: 16, spreadRadius: 1),
            ],
          ),
          child: Stack(clipBehavior: Clip.none, children: [
            Center(
              child: Opacity(opacity: claimed ? 0.55 : 1, child: RewardIcon(milestone: milestone, size: 46)),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 4,
              child: Text(
                claimed
                    ? 'Claimed'
                    : claimable
                        ? 'CLAIM!'
                        : rewardLabel(milestone),
                textAlign: TextAlign.center,
                style: kTitle.copyWith(fontSize: 16, color: claimable ? const Color(0xFFFFE680) : Colors.white),
              ),
            ),
            if (claimed)
              const Positioned(
                right: -8,
                top: -10,
                child: CircleAvatar(
                  radius: 15,
                  backgroundColor: Color(Palette.green),
                  child: Icon(Icons.check_rounded, color: Colors.white, size: 22),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

String rewardLabel(Milestone m) => switch (m.kind) {
      RewardKind.coins => '${m.amount}',
      RewardKind.gems => '${m.amount}',
      RewardKind.skin => skinById(m.skinId!).name,
    };

class RewardIcon extends StatelessWidget {
  const RewardIcon({super.key, required this.milestone, this.size = 48});
  final Milestone milestone;
  final double size;

  @override
  Widget build(BuildContext context) => switch (milestone.kind) {
        RewardKind.coins => Icon(Icons.savings_rounded, size: size, color: const Color(0xFFFFC928)),
        RewardKind.gems => Icon(Icons.diamond_rounded, size: size, color: const Color(0xFFE040FB)),
        RewardKind.skin => BlobAvatar(skin: skinById(milestone.skinId!), size: size, mood: Mood.excited),
      };
}

/// Reward card popup with a confetti burst.
class RewardCardDialog extends StatefulWidget {
  const RewardCardDialog({super.key, required this.milestone});
  final Milestone milestone;

  @override
  State<RewardCardDialog> createState() => _RewardCardDialogState();
}

class _RewardCardDialogState extends State<RewardCardDialog> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!reduceMotion(context) && _c.status == AnimationStatus.dismissed) _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.milestone;
    final what = switch (m.kind) {
      RewardKind.coins => '${m.amount} coins',
      RewardKind.gems => '${m.amount} gems',
      RewardKind.skin => 'New skin: ${skinById(m.skinId!).name}!',
    };
    return Center(
      child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
        Positioned.fill(
          child: IgnorePointer(child: CustomPaint(painter: ConfettiBurstPainter(_c))),
        ),
        Material(
          type: MaterialType.transparency,
          child: Container(
            key: const Key('rewardCard'),
            width: 250,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFD25A), Color(0xFFFF8A1F)]),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: const Color(0xFF7A3A12), width: 4),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('REWARD!', style: kTitle.copyWith(fontSize: 32)),
              const SizedBox(height: 10),
              RewardIcon(milestone: m, size: 84),
              const SizedBox(height: 10),
              Text(what, textAlign: TextAlign.center, style: kTitle.copyWith(fontSize: 22)),
              const SizedBox(height: 14),
              ChunkyButton(
                key: const Key('rewardOk'),
                label: 'NICE!',
                width: 160,
                height: 52,
                fontSize: 22,
                onTap: () => Navigator.of(context).pop(),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// Fixed-count confetti burst driven by [anim] (0..1).
class ConfettiBurstPainter extends CustomPainter {
  ConfettiBurstPainter(this.anim) : super(repaint: anim);
  final Animation<double> anim;
  static const _n = 60;
  static final List<double> _pieces = () {
    final rnd = math.Random(5);
    return [
      for (var i = 0; i < _n; i++) ...[
        rnd.nextDouble() * math.pi * 2,
        220 + rnd.nextDouble() * 360,
        (rnd.nextDouble() - 0.5) * 14,
        6 + rnd.nextDouble() * 7,
      ],
    ];
  }();
  static const _colors = [0xFFFFC928, 0xFFFF4FA3, 0xFF2EB7FF, 0xFF7EDB3A, 0xFF9B5CFF, 0xFFFF4757];
  static final Paint _p = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    final t = anim.value;
    if (t <= 0 || t >= 1) return;
    final sec = t * 1.6;
    final drag = (1 - math.exp(-2.4 * sec)) / 2.4;
    final c = size.center(Offset.zero);
    for (var i = 0; i < _n; i++) {
      final a = _pieces[i * 4], v = _pieces[i * 4 + 1], spin = _pieces[i * 4 + 2], s = _pieces[i * 4 + 3];
      final x = c.dx + math.cos(a) * v * drag;
      final y = c.dy + math.sin(a) * v * drag + 300 * sec * sec * 0.5;
      _p.color = fade(_colors[i % _colors.length], 1 - t * t);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(spin * sec + i);
      canvas.drawRect(Rect.fromLTWH(-s / 2, -s * 0.3, s, s * 0.6), _p);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant ConfettiBurstPainter old) => old.anim != anim;
}

/// Warm autumn festival backdrop: sky gradient, rolling hills and round trees.
class _FestivalBackground extends CustomPainter {
  const _FestivalBackground();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFE3A3), Color(0xFFFFC56B), Color(0xFFF6A84A)],
          ).createShader(Offset.zero & size));
    final hill = Paint()..color = const Color(0x33C0581C);
    canvas.drawOval(Rect.fromLTWH(-w * 0.3, h * 0.35, w * 0.9, h * 0.5), hill);
    canvas.drawOval(Rect.fromLTWH(w * 0.4, h * 0.5, w * 0.9, h * 0.6), hill);
    final rnd = math.Random(9);
    void tree(double x, double y, double r) {
      canvas.drawRect(Rect.fromCenter(center: Offset(x, y + r * 0.9), width: r * 0.22, height: r * 0.9),
          Paint()..color = const Color(0xFF6B3A1E));
      for (var k = 0; k < 3; k++) {
        canvas.drawCircle(Offset(x + (k - 1) * r * 0.45, y - (k == 1 ? r * 0.3 : 0)), r * 0.62,
            Paint()..color = Color(k == 1 ? 0xFFE8591F : 0xFFD24A17));
      }
      canvas.drawCircle(Offset(x - r * 0.2, y - r * 0.45), r * 0.22, Paint()..color = const Color(0x55FFFFFF));
    }

    for (var i = 0; i < 4; i++) {
      tree(-10 + rnd.nextDouble() * 40, h * (0.04 + i * 0.27), 34 + rnd.nextDouble() * 10);
      tree(w + 10 - rnd.nextDouble() * 40, h * (0.14 + i * 0.27), 34 + rnd.nextDouble() * 10);
    }
    final grass = Paint()..color = const Color(0xFFF7B95A);
    for (var i = 0; i < 40; i++) {
      final x = rnd.nextDouble() * w, y = rnd.nextDouble() * h;
      canvas.drawOval(Rect.fromCenter(center: Offset(x, y), width: 26, height: 10), grass);
    }
  }

  @override
  bool shouldRepaint(covariant _FestivalBackground old) => false;
}
