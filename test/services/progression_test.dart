import 'package:flutter_test/flutter_test.dart';
import 'package:inktide/game/progression.dart';
import 'package:inktide/game/sim/skins.dart';
import 'package:inktide/services/progress_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../helpers/pin_clock.dart';

Future<ProgressStore> openWith([Map<String, Object> values = const {}]) async {
  SharedPreferences.setMockInitialValues(Map<String, Object>.of(values));
  return ProgressStore.open();
}

MatchResult result({int level = 1, bool won = false, double percent = 10, int kills = 0}) =>
    MatchResult(level: level, won: won, percent: percent, kills: kills, seconds: 30);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(pinClockAwayFromDeals);
  tearDown(unpinClock);

  group('ranks', () {
    test('rank thresholds are consistent', () {
      expect(rankForXp(0), 1);
      expect(rankForXp(xpToNextRank(1) - 1), 1);
      expect(rankForXp(xpToNextRank(1)), 2);
      for (var r = 1; r < 30; r++) {
        expect(rankForXp(xpForRank(r)), r);
        expect(rankForXp(xpForRank(r + 1) - 1), r);
        expect(xpToNextRank(r + 1), greaterThan(xpToNextRank(r)), reason: 'ranks get harder');
      }
    });

    test('match XP rewards territory, splats and wins', () {
      final base = xpForMatch(percent: 10, kills: 0, won: false, level: 1);
      expect(xpForMatch(percent: 20, kills: 0, won: false, level: 1), greaterThan(base));
      expect(xpForMatch(percent: 10, kills: 1, won: false, level: 1), greaterThan(base));
      expect(xpForMatch(percent: 10, kills: 0, won: true, level: 1), greaterThan(base));
      expect(xpForMatch(percent: 0, kills: 0, won: false, level: 1), greaterThan(0), reason: 'playing always gives XP');
    });
  });

  group('recordMatch rewards', () {
    test('XP accumulates and a rank-up grants coins', () async {
      final s = await openWith({'tutorialSeen': true});
      expect(s.rank, 1);
      final r = await s.recordMatch(result(level: 1, won: true, percent: 30, kills: 1));
      expect(r.xp, s.xp);
      expect(r.rankBefore, 1);
      expect(r.rankAfter, s.rank);
      expect(r.rankedUp, isTrue, reason: '${r.xp} XP should pass rank 1');
      expect(r.rankCoins, rankReward(2));
      expect(s.coins, r.totalCoins);
    });

    test('achievements are granted once, pay coins and persist', () async {
      final s = await openWith();
      final first = await s.recordMatch(result(kills: 1, percent: 5));
      expect(first.achievements.map((a) => a.id), containsAll(['first_game', 'first_splat']));
      expect(s.achievements, containsAll(['first_game', 'first_splat']));
      final second = await s.recordMatch(result(kills: 1, percent: 5));
      expect(second.achievements.map((a) => a.id), isNot(contains('first_splat')));

      final again = ProgressStore(await SharedPreferences.getInstance());
      expect(again.achievements, s.achievements);
      expect(again.xp, s.xp);
      expect(again.bestKills, 1);
    });

    test('three splats in one match unlocks Triple Splat; spread over matches does not', () async {
      final s = await openWith();
      await s.recordMatch(result(kills: 2));
      await s.recordMatch(result(kills: 2));
      expect(s.achievements, isNot(contains('combo_3')));
      final r = await s.recordMatch(result(kills: 3));
      expect(r.achievements.map((a) => a.id), contains('combo_3'));
    });

    test('achievement-locked skin unlocks when the achievement is earned', () async {
      final boo = skinById('boo');
      expect(boo.unlockAchievement, 'hunter');
      final s = await openWith({'totalKills': 24});
      expect(s.isUnlocked(boo), isFalse);
      expect(s.canBuy(boo), isFalse, reason: 'achievement skins cannot be bought');
      final r = await s.recordMatch(result(kills: 1));
      expect(r.achievements.map((a) => a.id), contains('hunter'));
      expect(r.unlockedSkins.map((k) => k.id), contains('boo'));
      expect(s.isUnlocked(boo), isTrue);
      await s.selectSkin(boo);
      expect(s.selectedSkin, 'boo');
    });

    test('rank-locked skin unlocks on reaching the rank', () async {
      final jelly = skinById('jelly');
      final s = await openWith({'xp': xpForRank(jelly.unlockRank) - 1});
      expect(s.isUnlocked(jelly), isFalse);
      final r = await s.recordMatch(result(percent: 5));
      expect(s.rank, greaterThanOrEqualTo(jelly.unlockRank));
      expect(r.unlockedSkins.map((k) => k.id), contains('jelly'));
    });

    test('Collector counts skins and can be completed by unlocks in the same match', () async {
      // Owns 4 skins; the "hunter" achievement unlocks Boo as the 5th.
      final s = await openWith({
        'ownedSkins': ['sunny', 'bubbles', 'frost', 'lime'],
        'totalKills': 24,
      });
      final r = await s.recordMatch(result(kills: 1));
      expect(r.achievements.map((a) => a.id), containsAll(['hunter', 'collector']));
    });

    test('requirement text describes each unlock type', () async {
      final s = await openWith();
      expect(s.requirementText(skinById('grape')), 'Reach level 3');
      expect(s.requirementText(skinById('jelly')), 'Reach rank 4');
      expect(s.requirementText(skinById('boo')), 'Achievement: Ink Hunter');
      expect(s.requirementText(skinById('bubbles')), '120 coins');
    });

    test('unknown stored achievement ids are dropped; reset clears progression', () async {
      final s = await openWith({'achievements': ['first_game', 'bogus'], 'xp': 500});
      expect(s.achievements, {'first_game'});
      await s.resetProgress();
      expect(s.xp, 0);
      expect(s.rank, 1);
      expect(s.achievements, isEmpty);
    });

    test('volumes persist and are clamped', () async {
      final s = await openWith({'sfxVolume': 3.0, 'musicVolume': -1.0});
      expect(s.sfxVolume, 1.0);
      expect(s.musicVolume, 0.0);
      await s.update((st) => st.sfxVolume = 0.4);
      final again = ProgressStore(await SharedPreferences.getInstance());
      expect(again.sfxVolume, closeTo(0.4, 1e-9));
    });
  });

  test('every skin id is unique and every achievement-locked skin points at a real achievement', () {
    expect(kSkins.map((s) => s.id).toSet(), hasLength(kSkins.length));
    for (final s in kSkins) {
      if (s.unlockAchievement != null) expect(achievementById(s.unlockAchievement!), isNotNull, reason: s.id);
    }
  });
}
