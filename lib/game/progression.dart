import 'dart:math' as math;

/// XP, ranks and achievements. Pure Dart so the rules are unit-testable.

/// XP earned by one match.
int xpForMatch({required double percent, required int kills, required bool won, required int level}) =>
    (percent * 4).round() + kills * 25 + (won ? 60 + level * 10 : 10);

/// XP needed to go from [rank] to [rank] + 1.
int xpToNextRank(int rank) => 120 + (math.max(1, rank) - 1) * 80;

/// Total XP at which [rank] starts (rank 1 starts at 0).
int xpForRank(int rank) {
  var total = 0;
  for (var r = 1; r < rank; r++) {
    total += xpToNextRank(r);
  }
  return total;
}

int rankForXp(int xp) {
  var rank = 1, left = math.max(0, xp);
  while (left >= xpToNextRank(rank)) {
    left -= xpToNextRank(rank);
    rank++;
  }
  return rank;
}

/// Coins granted for reaching [rank].
int rankReward(int rank) => 40 + rank * 20;

/// Snapshot used to evaluate achievements after a match.
class StatsSnapshot {
  const StatsSnapshot({
    required this.gamesPlayed,
    required this.wins,
    required this.totalKills,
    required this.bestPercent,
    required this.bestKills,
    required this.level,
    required this.rank,
    required this.skinsOwned,
  });

  final int gamesPlayed;
  final int wins;
  final int totalKills;
  final double bestPercent;
  final int bestKills;
  final int level;
  final int rank;
  final int skinsOwned;
}

class Achievement {
  const Achievement(this.id, this.title, this.description, this.reward, this.goal, this.value);
  final String id;
  final String title;
  final String description;
  final int reward;

  /// Target for [value]; the achievement completes when value >= goal.
  final num goal;
  final num Function(StatsSnapshot s) value;

  bool test(StatsSnapshot s) => value(s) >= goal;

  /// 0..1 progress toward [goal].
  double progress(StatsSnapshot s) => (value(s) / goal).clamp(0.0, 1.0).toDouble();
}

final List<Achievement> kAchievements = [
  Achievement('first_game', 'First Splash', 'Play your first match', 20, 1, (s) => s.gamesPlayed),
  Achievement('first_splat', 'First Splat', 'Splat a rival', 40, 1, (s) => s.totalKills),
  Achievement('first_win', 'Winner!', 'Clear a level', 60, 1, (s) => s.wins),
  Achievement('painter_20', 'Painter', 'Own 20% of an arena', 60, 20, (s) => s.bestPercent),
  Achievement('painter_35', 'Muralist', 'Own 35% of an arena', 100, 35, (s) => s.bestPercent),
  Achievement('painter_50', 'Ink Tycoon', 'Own 50% of an arena', 200, 50, (s) => s.bestPercent),
  Achievement('combo_3', 'Triple Splat', 'Splat 3 rivals in one match', 120, 3, (s) => s.bestKills),
  Achievement('hunter', 'Ink Hunter', 'Splat 25 rivals in total', 150, 25, (s) => s.totalKills),
  Achievement('level_5', 'Explorer', 'Reach level 5', 100, 5, (s) => s.level),
  Achievement('level_10', 'Conqueror', 'Reach level 10', 250, 10, (s) => s.level),
  Achievement('games_25', 'Regular', 'Play 25 matches', 120, 25, (s) => s.gamesPlayed),
  Achievement('rank_5', 'Rising Star', 'Reach rank 5', 150, 5, (s) => s.rank),
  Achievement('collector', 'Collector', 'Own 5 skins', 150, 5, (s) => s.skinsOwned),
];

Achievement? achievementById(String id) {
  for (final a in kAchievements) {
    if (a.id == id) return a;
  }
  return null;
}
