import 'package:flutter/material.dart';

import '../../app.dart';
import '../../services/feedback.dart';
import '../../game/sim/levels.dart';
import '../palette.dart';
import '../widgets.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  static const String version = '1.6.0';

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with SingleTickerProviderStateMixin {
  static const version = SettingsScreen.version;
  late final AnimationController _intro =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 520));

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

  Widget _enter(int i, Widget child) =>
      StaggerIn(animation: _intro, start: i * 0.12, end: 0.5 + i * 0.12, offset: const Offset(0, 36), child: child);

  @override
  Widget build(BuildContext context) {
    final s = Services.of(context);
    final store = s.store;
    return Scaffold(
      body: Stack(fit: StackFit.expand, children: [
        const PaintBackground(animate: false),
        SafeArea(
          child: AnimatedBuilder(
            animation: store,
            builder: (context, _) => ListView(
              padding: const EdgeInsets.all(18),
              children: [
                _enter(0, Row(children: [
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
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text('SETTINGS', style: kTitle.copyWith(fontSize: 34)),
                    ),
                  ),
                ])),
                const SizedBox(height: 18),
                _enter(1, GamePanel(
                  title: 'AUDIO & FEEL',
                  child: Column(children: [
                    _Toggle(
                      key: const Key('soundToggle'),
                      label: 'Sound effects',
                      icon: Icons.volume_up_rounded,
                      value: store.sound,
                      onChanged: (v) {
                        store.update((st) => st.sound = v);
                        s.fx.tap();
                      },
                    ),
                    _VolumeSlider(
                      key: const Key('sfxVolume'),
                      value: store.sfxVolume,
                      enabled: store.sound,
                      onChangeEnd: (v) async {
                        await store.update((st) => st.sfxVolume = v);
                        s.fx.play(Sfx.coin);
                      },
                    ),
                    _Toggle(
                      key: const Key('musicToggle'),
                      label: 'Music',
                      icon: Icons.music_note_rounded,
                      value: store.music,
                      onChanged: (v) async {
                        await store.update((st) => st.music = v);
                        await s.fx.syncMusic();
                      },
                    ),
                    _VolumeSlider(
                      key: const Key('musicVolume'),
                      value: store.musicVolume,
                      enabled: store.music,
                      onChanged: (v) {
                        store.musicVolume = v;
                        s.fx.applyMusicVolume();
                      },
                      onChangeEnd: (v) => store.update((st) => st.musicVolume = v),
                    ),
                    _Toggle(
                      key: const Key('hapticsToggle'),
                      label: 'Vibration',
                      icon: Icons.vibration_rounded,
                      value: store.haptics,
                      onChanged: (v) {
                        store.update((st) => st.haptics = v);
                        s.fx.hapticLight();
                      },
                    ),
                    _Toggle(
                      key: const Key('notificationsToggle'),
                      label: 'Reminders',
                      icon: Icons.notifications_active_rounded,
                      value: store.notificationsEnabled,
                      onChanged: (v) => s.reminders.setEnabled(v),
                    ),
                    _Toggle(
                      key: const Key('fpsToggle'),
                      label: 'Show FPS',
                      icon: Icons.speed_rounded,
                      value: store.showFps,
                      onChanged: (v) => store.update((st) => st.showFps = v),
                    ),
                  ]),
                )),
                const SizedBox(height: 18),
                _enter(2, GamePanel(
                  title: 'GAME SPEED',
                  headerColor: Palette.pink,
                  child: SegmentedButton<SpeedSetting>(
                    key: const Key('speedSelector'),
                    segments: const [
                      ButtonSegment(value: SpeedSetting.slow, label: Text('Chill')),
                      ButtonSegment(value: SpeedSetting.normal, label: Text('Normal')),
                      ButtonSegment(value: SpeedSetting.fast, label: Text('Turbo')),
                    ],
                    selected: {store.speed},
                    showSelectedIcon: false,
                    onSelectionChanged: (sel) {
                      s.fx.tap();
                      store.update((st) => st.speed = sel.first);
                    },
                  ),
                )),
                const SizedBox(height: 18),
                _enter(3, GamePanel(
                  title: 'MORE',
                  headerColor: Palette.purple,
                  child: Column(children: [
                    ListTile(
                      leading: const Icon(Icons.description_rounded),
                      title: Text('Licenses', style: bodyStyle(17)),
                      onTap: () => showLicensePage(
                        context: context,
                        applicationName: 'InkTide: Territory Dash',
                        applicationVersion: version,
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.privacy_tip_rounded),
                      title: Text('Privacy', style: bodyStyle(17)),
                      subtitle: Text('Solo play is offline and collects nothing. Online play shares only your nickname, skin and moves with the game server. '
                          'Reminders are scheduled on this device only. Progress is stored only on this device.',
                          style: bodyStyle(13, color: const Color(0xFF6A7393))),
                    ),
                    ListTile(
                      key: const Key('resetProgress'),
                      leading: const Icon(Icons.restart_alt_rounded, color: Color(0xFFE53950)),
                      title: Text('Reset progress', style: bodyStyle(17, color: const Color(0xFFE53950))),
                      onTap: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Reset progress?'),
                            content: const Text('Coins, level, skins and stats will be erased.'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                              TextButton(
                                  key: const Key('confirmReset'),
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('Reset')),
                            ],
                          ),
                        );
                        if (ok == true) await store.resetProgress();
                      },
                    ),
                  ]),
                )),
                const SizedBox(height: 14),
                _enter(4, Center(
                  child: Text('InkTide v$version  •  AGMIEX Technologies',
                      style: bodyStyle(13, color: Colors.white)),
                )),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({super.key, required this.label, required this.icon, required this.value, required this.onChanged});
  final String label;
  final IconData icon;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      secondary: Icon(icon, color: const Color(Palette.skyDeep)),
      title: Text(label, style: bodyStyle(17)),
      value: value,
      onChanged: onChanged,
    );
  }
}

/// Volume slider that keeps its own drag value and only saves on release.
class _VolumeSlider extends StatefulWidget {
  const _VolumeSlider({super.key, required this.value, required this.enabled, required this.onChangeEnd, this.onChanged});
  final double value;
  final bool enabled;
  final ValueChanged<double> onChangeEnd;
  final ValueChanged<double>? onChanged;

  @override
  State<_VolumeSlider> createState() => _VolumeSliderState();
}

class _VolumeSliderState extends State<_VolumeSlider> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final v = _drag ?? widget.value;
    return Row(children: [
      const SizedBox(width: 40),
      Expanded(
        child: Slider(
          value: v,
          divisions: 10,
          label: '${(v * 100).round()}%',
          activeColor: const Color(Palette.skyDeep),
          onChanged: widget.enabled
              ? (x) {
                  setState(() => _drag = x);
                  widget.onChanged?.call(x);
                }
              : null,
          onChangeEnd: (x) {
            setState(() => _drag = null);
            widget.onChangeEnd(x);
          },
        ),
      ),
      SizedBox(width: 44, child: Text('${(v * 100).round()}%', style: bodyStyle(14))),
    ]);
  }
}
