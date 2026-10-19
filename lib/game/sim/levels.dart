import 'dart:math' as math;

/// Difficulty curve. Every value is derived from the level number so any
/// level can be generated.
class LevelConfig {
  const LevelConfig({
    required this.level,
    required this.arenaSize,
    required this.bots,
    required this.targetPercent,
    required this.botSkill,
  });

  factory LevelConfig.forLevel(int level) {
    final l = math.max(1, level);
    return LevelConfig(
      level: l,
      arenaSize: 56 + 4 * math.min(l, 10),
      bots: math.min(2 + l, 9),
      targetPercent: math.min(10.0 + 5.0 * l, 55.0),
      // Rivals start sharp and get ruthless quickly.
      botSkill: math.min(0.32 + 0.09 * l, 0.97),
    );
  }

  final int level;
  final int arenaSize;
  final int bots;
  final double targetPercent;

  /// 0..1: affects how far bots roam, how aggressively they chase trails and
  /// how early they notice danger.
  final double botSkill;
}

enum SpeedSetting { slow, normal, fast }

double speedCellsPerSecond(SpeedSetting s) => switch (s) {
      SpeedSetting.slow => 5.0,
      SpeedSetting.normal => 6.3,
      SpeedSetting.fast => 7.6,
    };
