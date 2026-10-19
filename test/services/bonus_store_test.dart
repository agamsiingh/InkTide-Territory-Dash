import 'package:flutter_test/flutter_test.dart';
import 'package:inktide/game/sim/skins.dart';
import 'package:inktide/game/world.dart';
import 'package:inktide/services/progress_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProgressStore> openWith([Map<String, Object> values = const {}]) async {
  SharedPreferences.setMockInitialValues(Map<String, Object>.of(values));
  return ProgressStore.open();
}

MatchResult win({int bonusCoins = 0, int bonusGems = 0}) => MatchResult(
    level: 1, won: true, percent: 20, kills: 0, seconds: 30, bonusCoins: bonusCoins, bonusGems: bonusGems);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('bonus loot', () {
    test('is held after the match and paid exactly once with the multiplier', () async {
      final s = await openWith();
      final rw = await s.recordMatch(win(bonusCoins: 60, bonusGems: 2));
      expect(rw.bonusCoins, 60);
      expect(rw.bonusGems, 2);
      final coins = s.coins, gems = s.gems;
      expect(s.hasPendingBonus, isTrue);
      expect(await s.claimBonus(3), (180, 6));
      expect(s.coins, coins + 180);
      expect(s.gems, gems + 6);
      expect(s.hasPendingBonus, isFalse);
      expect(await s.claimBonus(4), isNull, reason: 'no double claim');
      expect(s.coins, coins + 180);
    });

    test('multiplier is clamped to 1..4', () async {
      final s = await openWith();
      await s.recordMatch(win(bonusCoins: 10));
      final c0 = s.coins;
      expect(await s.claimBonus(99), (40, 0));
      expect(s.coins, c0 + 40);
    });

    test('loot left unclaimed when the app closed is paid at x1 on next start', () async {
      final s = await openWith();
      await s.recordMatch(win(bonusCoins: 25, bonusGems: 1));
      final coins = s.coins, gems = s.gems;
      final again = await ProgressStore.open();
      expect(again.hasPendingBonus, isFalse);
      expect(again.coins, coins + 25);
      expect(again.gems, gems + 1);
      // And it does not pay a second time on the start after that.
      final third = await ProgressStore.open();
      expect(third.coins, coins + 25);
    });

    test('a newer bonus pays any older unclaimed one first', () async {
      final s = await openWith();
      await s.recordMatch(win(bonusCoins: 10));
      final c0 = s.coins;
      final rw = await s.recordMatch(win(bonusCoins: 20));
      expect(s.coins, c0 + rw.totalCoins + 10);
      expect(await s.claimBonus(2), (40, 0));
    });

    test('a match without bonus loot leaves pending loot alone', () async {
      final s = await openWith();
      await s.recordMatch(win(bonusCoins: 10));
      await s.recordMatch(const MatchResult(level: 1, won: false, percent: 5, kills: 0, seconds: 9));
      expect(s.pendingBonusCoins, 10);
    });
  });

  group('skins collection', () {
    test('newly unlocked skins are NEW until seen', () async {
      final s = await openWith({'coins': 500});
      expect(s.newSkinCount, 0, reason: 'starting skin counts as seen');
      final bubbles = skinById('bubbles');
      expect(await s.buySkin(bubbles), isTrue);
      expect(s.isNewSkin(bubbles), isTrue);
      await s.markSkinSeen(bubbles);
      expect(s.isNewSkin(bubbles), isFalse);
      final again = await ProgressStore.open();
      expect(again.isNewSkin(bubbles), isFalse);
    });

    test('unequip goes back to the default character', () async {
      final s = await openWith({'coins': 500});
      await s.buySkin(skinById('bubbles'));
      expect(s.selectedSkin, 'bubbles');
      await s.unequipSkin();
      expect(s.selectedSkin, kSkins.first.id);
    });

    test('Dino unlocks after completing 3 countries', () async {
      final s = await openWith();
      final dino = skinById('dino');
      expect(dino.id, 'dino');
      expect(s.isUnlocked(dino), isFalse);
      expect(s.requirementText(dino), 'Complete 3 countries');
      final done = await openWith({'countryProgress': ['100', '100', '100']});
      expect(done.countriesCompleted, 3);
      expect(done.isUnlocked(dino), isTrue);
    });

    test('a skin unlocked by a match is worn in the next game', () async {
      // Sweetie unlocks at level 2: win level 1 and she is equipped.
      final s = await openWith();
      expect(s.selectedSkin, kSkins.first.id);
      final rw = await s.recordMatch(win());
      expect(rw.unlockedSkins.map((k) => k.id), contains('sweetie'));
      expect(s.selectedSkin, rw.unlockedSkins.last.id);
      final again = await ProgressStore.open();
      expect(again.selectedSkin, rw.unlockedSkins.last.id, reason: 'saved for the next launch');
    });

    test('cute animal skins exist', () {
      for (final id in ['sweetie', 'teddy', 'bubblegum', 'panda', 'piggy', 'froggy', 'chick', 'koala', 'foxy', 'pengu']) {
        expect(kSkins.map((k) => k.id), contains(id));
      }
    });

    test('rarity tiers', () {
      expect(kSkins.first.rarity, Rarity.common);
      expect(skinById('grape').rarity, Rarity.rare);
      expect(skinById('dino').rarity, Rarity.epic);
      expect(skinById('ember').rarity, Rarity.legendary);
      expect(skinById('aurora').rarity, Rarity.legendary);
    });
  });

  group('world map', () {
    test('continents follow campaign order', () {
      expect(kContinents.first, 'North America');
      expect(kContinents[1], 'South America');
      expect(countriesOf('North America'), [0, 1, 2]);
      final all = [for (final c in kContinents) ...countriesOf(c)];
      expect(all, List.generate(kCountries.length, (i) => i));
    });

    test('each completed country is celebrated once', () async {
      final s = await openWith({'countryProgress': ['100', '30']});
      expect(await s.takeUncelebratedCountries(), [0]);
      expect(await s.takeUncelebratedCountries(), isEmpty);
      final again = await ProgressStore.open();
      expect(await again.takeUncelebratedCountries(), isEmpty);
    });

    test('powers unlock at level 3', () async {
      expect((await openWith()).powersUnlocked, isFalse);
      expect((await openWith({'level': 3})).powersUnlocked, isTrue);
    });
  });
}
