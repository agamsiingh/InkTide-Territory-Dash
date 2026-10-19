import 'package:flutter_test/flutter_test.dart';
import 'package:inktide/game/sim/levels.dart';
import 'package:inktide/game/sim/skins.dart';
import 'package:inktide/services/progress_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../helpers/pin_clock.dart';

Future<ProgressStore> openWith([Map<String, Object> values = const {}]) async {
  SharedPreferences.setMockInitialValues(Map<String, Object>.of(values));
  return ProgressStore.open();
}

/// A second store reading the same (mocked) preferences, as after an app restart.
Future<ProgressStore> reopen() async => ProgressStore(await SharedPreferences.getInstance());

MatchResult result({int level = 1, bool won = false, double percent = 10, int kills = 0, double seconds = 30}) =>
    MatchResult(level: level, won: won, percent: percent, kills: kills, seconds: seconds);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(pinClockAwayFromDeals);
  tearDown(unpinClock);

  group('defaults', () {
    test('fresh install', () async {
      final s = await openWith();
      expect(s.sound, isTrue);
      expect(s.music, isTrue);
      expect(s.haptics, isTrue);
      expect(s.showFps, isFalse);
      expect(s.speed, SpeedSetting.normal);
      expect(s.level, 1);
      expect(s.coins, 0);
      expect(s.bestPercent, 0);
      expect(s.totalKills, 0);
      expect(s.gamesPlayed, 0);
      expect(s.wins, 0);
      expect(s.tutorialSeen, isFalse);
      expect(s.selectedSkin, 'sunny');
      expect(s.ownedSkins, {'sunny'});
      expect(s.isUnlocked(skinById('sunny')), isTrue);
      expect(s.isUnlocked(skinById('bubbles')), isFalse);
    });

    test('corrupt / out-of-range stored values are sanitised', () async {
      final s = await openWith({
        'speed': 99,
        'level': 0,
        'selectedSkin': 'royal', // locked at level 1
        'ownedSkins': <String>['frost'],
      });
      expect(s.speed, SpeedSetting.fast);
      expect(s.level, 1);
      expect(s.selectedSkin, 'sunny');
      expect(s.ownedSkins, containsAll(<String>['sunny', 'frost']));
    });

    test('unknown skin id falls back to the first skin', () async {
      final s = await openWith({'selectedSkin': 'does-not-exist'});
      expect(s.selectedSkin, 'sunny');
      expect(skinById('does-not-exist').id, 'sunny');
    });
  });

  group('persistence', () {
    test('settings and progress survive a restart', () async {
      final s = await openWith();
      await s.update((st) {
        st.sound = false;
        st.music = false;
        st.haptics = false;
        st.showFps = true;
        st.speed = SpeedSetting.slow;
        st.coins = 321;
        st.level = 4;
        st.tutorialSeen = true;
      });
      final again = await reopen();
      expect(again.sound, isFalse);
      expect(again.music, isFalse);
      expect(again.haptics, isFalse);
      expect(again.showFps, isTrue);
      expect(again.speed, SpeedSetting.slow);
      expect(again.coins, 321);
      expect(again.level, 4);
      expect(again.tutorialSeen, isTrue);
    });

    test('update notifies listeners', () async {
      final s = await openWith();
      var notified = 0;
      s.addListener(() => notified++);
      await s.update((st) => st.coins = 5);
      expect(notified, 1);
    });

    test('stored values are written to SharedPreferences', () async {
      final s = await openWith();
      await s.update((st) => st.coins = 77);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('coins'), 77);
      expect(prefs.getStringList('ownedSkins'), contains('sunny'));
    });
  });

  group('MatchResult.coins', () {
    test('loss: 2 per percent (rounded) + 15 per kill', () {
      expect(result(percent: 12.3, kills: 2).coins, 25 + 30);
      expect(result(percent: 0, kills: 0).coins, 0);
      expect(result(percent: 0.25).coins, 1); // 0.5 rounds away from zero
    });

    test('win adds 40 + 10 per level', () {
      expect(result(level: 3, won: true, percent: 30, kills: 1).coins, 60 + 15 + 70);
      expect(result(level: 1, won: true, percent: 15).coins, 30 + 50);
    });
  });

  group('recordMatch', () {
    test('loss adds coins/stats but does not level up', () async {
      final s = await openWith();
      final unlocked = (await s.recordMatch(result(percent: 8.0, kills: 2))).unlockedSkins;
      expect(unlocked, isEmpty);
      // Match coins plus the "First Splash" (20) and "First Splat" (40) achievements.
      expect(s.coins, 16 + 30 + 20 + 40);
      expect(s.totalKills, 2);
      expect(s.gamesPlayed, 1);
      expect(s.wins, 0);
      expect(s.level, 1);
      expect(s.bestPercent, 8.0);
    });

    test('win levels up and counts the win', () async {
      final s = await openWith();
      await s.recordMatch(result(level: 1, won: true, percent: 16));
      expect(s.level, 2);
      expect(s.wins, 1);
      // Match (32 + 50) + rank 2 reward (80) + "First Splash" (20) + "Winner!" (60).
      expect(s.coins, 32 + 50 + 80 + 20 + 60);
      final again = await reopen();
      expect(again.level, 2);
      expect(again.coins, 242);
    });

    test('winning an older level does not change the current level', () async {
      final s = await openWith({'level': 5});
      await s.recordMatch(result(level: 2, won: true, percent: 30));
      expect(s.level, 5);
      expect(s.wins, 1);
    });

    test('bestPercent keeps the maximum', () async {
      final s = await openWith();
      await s.recordMatch(result(percent: 20));
      await s.recordMatch(result(percent: 5));
      expect(s.bestPercent, 20);
      await s.recordMatch(result(percent: 33.3));
      expect(s.bestPercent, 33.3);
      expect(s.gamesPlayed, 3);
    });

    test('reaching level 3 unlocks Grape; level 6 unlocks Royal Ruby', () async {
      final s = await openWith({'level': 2});
      expect(s.isUnlocked(skinById('grape')), isFalse);
      final unlocked = (await s.recordMatch(result(level: 2, won: true, percent: 25))).unlockedSkins;
      expect(s.level, 3);
      expect(unlocked.map((k) => k.id), ['grape']);
      expect(s.isUnlocked(skinById('grape')), isTrue);
      expect(s.isUnlocked(skinById('royal')), isFalse);

      await s.update((st) => st.level = 5);
      final more = (await s.recordMatch(result(level: 5, won: true, percent: 40))).unlockedSkins;
      expect(more.map((k) => k.id), ['royal']);
    });
  });

  group('skins', () {
    test('buying without enough coins fails and changes nothing', () async {
      final s = await openWith({'coins': 100});
      final bubbles = skinById('bubbles');
      expect(s.canBuy(bubbles), isFalse);
      expect(await s.buySkin(bubbles), isFalse);
      expect(s.coins, 100);
      expect(s.ownedSkins, isNot(contains('bubbles')));
      expect(s.selectedSkin, 'sunny');
    });

    test('buying with enough coins deducts, owns and selects', () async {
      final s = await openWith({'coins': 500});
      final bubbles = skinById('bubbles');
      expect(s.canBuy(bubbles), isTrue);
      expect(await s.buySkin(bubbles), isTrue);
      expect(s.coins, 500 - bubbles.cost);
      expect(s.ownedSkins, contains('bubbles'));
      expect(s.selectedSkin, 'bubbles');
      expect(s.isUnlocked(bubbles), isTrue);
      // Cannot buy twice.
      expect(s.canBuy(bubbles), isFalse);
      expect(await s.buySkin(bubbles), isFalse);
      expect(s.coins, 500 - bubbles.cost);
      final again = await reopen();
      expect(again.selectedSkin, 'bubbles');
      expect(again.ownedSkins, contains('bubbles'));
      expect(again.coins, 380);
    });

    test('level-unlock skins cannot be bought', () async {
      final s = await openWith({'coins': 9999});
      final grape = skinById('grape');
      expect(grape.cost, 0);
      expect(s.canBuy(grape), isFalse);
      expect(await s.buySkin(grape), isFalse);
      expect(s.coins, 9999);
    });

    test('selectSkin ignores locked skins', () async {
      final s = await openWith();
      await s.selectSkin(skinById('frost'));
      expect(s.selectedSkin, 'sunny');
      await s.update((st) => st.level = 3);
      await s.selectSkin(skinById('grape'));
      expect(s.selectedSkin, 'grape');
    });
  });

  test('resetProgress clears progress but keeps settings', () async {
    final s = await openWith({
      'coins': 900,
      'level': 7,
      'bestPercent': 44.0,
      'totalKills': 12,
      'gamesPlayed': 30,
      'wins': 6,
      'tutorialSeen': true,
      'ownedSkins': <String>['sunny', 'frost'],
      'selectedSkin': 'frost',
      'sound': false,
      'speed': SpeedSetting.fast.index,
    });
    expect(s.level, 7);
    expect(s.selectedSkin, 'frost');
    await s.resetProgress();
    for (final st in [s, await reopen()]) {
      expect(st.level, 1);
      expect(st.coins, 0);
      expect(st.bestPercent, 0);
      expect(st.totalKills, 0);
      expect(st.gamesPlayed, 0);
      expect(st.wins, 0);
      expect(st.tutorialSeen, isFalse);
      expect(st.selectedSkin, 'sunny');
      expect(st.ownedSkins, {'sunny'});
      expect(st.sound, isFalse, reason: 'settings are not progress');
      expect(st.speed, SpeedSetting.fast);
    }
  });
}
