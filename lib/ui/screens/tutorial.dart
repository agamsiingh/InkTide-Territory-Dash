import 'package:flutter/material.dart';

import '../../game/sim/skins.dart';
import '../blob_painter.dart';
import '../palette.dart';
import '../widgets.dart';

class _Step {
  const _Step(this.title, this.text, this.icon);
  final String title;
  final String text;
  final IconData icon;
}

const _steps = [
  _Step('Steer', 'Drag anywhere on the screen. Your cube follows the direction of your finger.',
      Icons.swipe_rounded),
  _Step('Paint a trail', 'Leave your colored zone and you leave a paint trail behind you.',
      Icons.brush_rounded),
  _Step('Capture!', 'Get back to your own zone to close the shape and claim everything it surrounds. '
      'Touching your own line does nothing - only coming home counts.', Icons.format_paint_rounded),
  _Step('Stay safe', 'If a rival touches your trail, you get splatted! '
      'Cut a rival\'s trail to splat them and take their land.', Icons.warning_rounded),
];

/// Multi-step tutorial card. [onDone] is called after the last step (or the
/// dialog is popped when used inside a dialog).
class TutorialCard extends StatefulWidget {
  const TutorialCard({super.key, this.onDone});
  final VoidCallback? onDone;

  @override
  State<TutorialCard> createState() => _TutorialCardState();
}

class _TutorialCardState extends State<TutorialCard> {
  int _i = 0;

  void _next() {
    if (_i < _steps.length - 1) {
      setState(() => _i++);
    } else if (widget.onDone != null) {
      widget.onDone!();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _steps[_i];
    final last = _i == _steps.length - 1;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380),
      child: GamePanel(
        title: 'HOW TO PLAY',
        headerColor: Palette.purple,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AnimatedSwitcher(
            duration: motion(context, const Duration(milliseconds: 250)),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, a) {
              final incoming = child.key == ValueKey(_i);
              return FadeTransition(
                opacity: a,
                child: SlideTransition(
                  position: Tween(begin: Offset(incoming ? 0.25 : -0.25, 0), end: Offset.zero).animate(a),
                  child: child,
                ),
              );
            },
            child: Column(
              key: ValueKey(_i),
              children: [
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  BlobAvatar(
                      skin: kSkins.first,
                      size: 64,
                      mood: _i == 3 ? Mood.worried : Mood.excited),
                  const SizedBox(width: 12),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.4, end: 1),
                    duration: motion(context, const Duration(milliseconds: 420)),
                    curve: Curves.elasticOut,
                    builder: (_, v, child) => Transform.scale(scale: v, child: child),
                    child: Icon(s.icon, size: 46, color: const Color(Palette.skyDeep)),
                  ),
                ]),
                const SizedBox(height: 8),
                Text(s.title, style: kTitle.copyWith(fontSize: 26, color: const Color(Palette.ink), shadows: [])),
                const SizedBox(height: 6),
                Text(s.text, textAlign: TextAlign.center, style: bodyStyle(17)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var k = 0; k < _steps.length; k++)
              AnimatedContainer(
                duration: motion(context, const Duration(milliseconds: 220)),
                curve: Curves.easeOutBack,
                width: k == _i ? 22 : 10,
                height: 10,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: Color(k == _i ? Palette.purple : 0xFFD5D9E6),
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
          ]),
          const SizedBox(height: 14),
          ChunkyButton(
            key: const Key('tutorialNext'),
            label: last ? "LET'S GO!" : 'NEXT',
            width: double.infinity,
            height: 54,
            fontSize: 22,
            onTap: _next,
          ),
        ]),
      ),
    );
  }
}
