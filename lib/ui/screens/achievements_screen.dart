import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app.dart';
import '../../game/progression.dart';
import '../palette.dart';
import '../widgets.dart';

class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({super.key});

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _intro =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 600));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_intro.status != AnimationStatus.dismissed) return;
    if (reduceMotion(context)) {
      _intro.value = 1;
    } else {
      _intro.forward();
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = Services.of(context);
    final store = s.store;
    final stats = store.stats;
    final done = kAchievements.where((a) => store.achievements.contains(a.id)).length;
    // Completed first, then by progress.
    final list = [...kAchievements]..sort((a, b) {
        final da = store.achievements.contains(a.id), db = store.achievements.contains(b.id);
        if (da != db) return da ? -1 : 1;
        return b.progress(stats).compareTo(a.progress(stats));
      });
    return Scaffold(
      body: Stack(fit: StackFit.expand, children: [
        const PaintBackground(animate: false),
        SafeArea(
          child: Column(children: [
            StaggerIn(
              animation: _intro,
              end: 0.5,
              offset: const Offset(0, -24),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
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
                  const SizedBox(width: 14),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text('AWARDS', style: kTitle.copyWith(fontSize: 34)),
                    ),
                  ),
                  StatPill(icon: Icons.emoji_events_rounded, value: '$done/${kAchievements.length}'),
                ]),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                itemCount: list.length,
                itemBuilder: (context, i) {
                  final a = list[i];
                  final delay = math.min(i, 8) * 0.05;
                  return StaggerIn(
                    animation: _intro,
                    start: delay,
                    end: delay + 0.5,
                    child: _AchievementTile(
                      key: Key('achievement_${a.id}'),
                      achievement: a,
                      done: store.achievements.contains(a.id),
                      progress: a.progress(stats),
                      value: a.value(stats),
                    ),
                  );
                },
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _AchievementTile extends StatelessWidget {
  const _AchievementTile({
    super.key,
    required this.achievement,
    required this.done,
    required this.progress,
    required this.value,
  });
  final Achievement achievement;
  final bool done;
  final double progress;
  final num value;

  @override
  Widget build(BuildContext context) {
    final a = achievement;
    final shown = math.min(value, a.goal);
    final valueText = a.goal is int || a.goal == a.goal.roundToDouble()
        ? '${shown.floor()}/${a.goal.round()}'
        : '${shown.toStringAsFixed(1)}/${a.goal}';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: done ? const Color(Palette.gold) : const Color(0x00000000), width: 3),
        boxShadow: const [BoxShadow(color: Color(0x5516204A), offset: Offset(0, 5))],
      ),
      child: Row(children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: Color(done ? Palette.gold : 0xFFDDE3EE),
            shape: BoxShape.circle,
          ),
          child: Icon(done ? Icons.emoji_events_rounded : Icons.lock_outline_rounded,
              color: done ? Colors.white : const Color(0xFF8A93AD), size: 30),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(a.title, style: kTitle.copyWith(fontSize: 20, color: const Color(Palette.ink), shadows: [])),
            Text(a.description, style: bodyStyle(14, color: const Color(0xFF6A7393))),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: done ? 1 : progress,
                minHeight: 8,
                backgroundColor: const Color(0xFFE6EAF2),
                color: Color(done ? Palette.gold : Palette.skyDeep),
              ),
            ),
          ]),
        ),
        const SizedBox(width: 10),
        Column(children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.monetization_on_rounded, size: 18, color: Color(Palette.yellow)),
            const SizedBox(width: 2),
            Text('${a.reward}', style: kTitle.copyWith(fontSize: 17, color: const Color(Palette.ink), shadows: [])),
          ]),
          Text(done ? 'DONE' : valueText, style: bodyStyle(12, color: const Color(0xFF6A7393))),
        ]),
      ]),
    );
  }
}
