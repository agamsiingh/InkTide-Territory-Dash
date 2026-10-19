/// Timed "Ink Festival" event with a milestone reward track. Pure Dart.
///
/// Events run back to back in fixed 7-day windows starting [kEventEpoch]
/// (UTC), so every device agrees on the current event without a server.
library;

final DateTime kEventEpoch = DateTime.utc(2026, 1, 5); // a Monday
const Duration kEventLength = Duration(days: 7);

class EventWindow {
  const EventWindow(this.id, this.start, this.end);
  final int id;
  final DateTime start;
  final DateTime end;

  Duration remaining(DateTime now) {
    final r = end.difference(now.toUtc());
    return r.isNegative ? Duration.zero : r;
  }
}

EventWindow eventAt(DateTime now) {
  final since = now.toUtc().difference(kEventEpoch);
  final id = since.isNegative ? 0 : since.inSeconds ~/ kEventLength.inSeconds;
  final start = kEventEpoch.add(kEventLength * id);
  return EventWindow(id, start, start.add(kEventLength));
}

enum RewardKind { coins, gems, skin }

class Milestone {
  const Milestone(this.goal, this.kind, this.amount, {this.skinId});
  final int goal;
  final RewardKind kind;
  final int amount;
  final String? skinId;
}

/// Reward track, bottom to top.
const List<Milestone> kMilestones = [
  Milestone(5, RewardKind.coins, 500),
  Milestone(25, RewardKind.coins, 2000),
  Milestone(75, RewardKind.gems, 50),
  Milestone(140, RewardKind.coins, 4000),
  Milestone(200, RewardKind.skin, 1, skinId: 'ember'),
];

/// Event tokens ("ink drops") earned by one match.
int tokensForMatch({required double percent, required int kills, required bool won}) =>
    1 + kills + percent ~/ 10 + (won ? 2 : 0);

/// "1d 23h", "5h 12m" or "42m" (never negative).
String formatRemaining(Duration d) {
  if (d.inDays > 0) return '${d.inDays}d ${d.inHours % 24}h';
  if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m';
  return '${d.inMinutes}m';
}
