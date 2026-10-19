import 'package:flutter_test/flutter_test.dart';
import 'package:inktide/game/event.dart';
import 'package:inktide/game/sim/skins.dart';
import 'package:inktide/game/world.dart';
import 'package:inktide/services/progress_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProgressStore> openWith([Map<String, Object> values = const {}]) async {
  SharedPreferences.setMockInitialValues(Map<String, Object>.of(values));
  return ProgressStore.open();
}

Future<ProgressStore> reopen() async => ProgressStore(await SharedPreferences.getInstance());

MatchResult result({double percent = 20, bool won = false, int kills = 0, int country = 0}) =>
    MatchResult(level: 1, won: won, percent: percent, kills: kills, seconds: 30, country: country);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var now = DateTime.utc(2026, 10, 19, 12);
  setUp(() {
    now = DateTime.utc(2026, 10, 19, 12);
    ProgressStore.clock = () => now;
  });
  tearDown(() => ProgressStore.clock = DateTime.now);

  group('world progression', () {
    test('only the first country starts unlocked', () async {
      final s = await openWith();
      expect(s.isCountryUnlocked(0), isTrue);
      for (var i = 1; i < kCountries.length; i++) {
        expect(s.isCountryUnlocked(i), isFalse);
      }
      expect(s.currentCountry, 0);
      await s.selectCountry(3);
      expect(s.selectedCountry, 0, reason: 'locked countries cannot be selected');
    });

    test('matches fill the country and persist', () async {
      final s = await openWith();
      final r = await s.recordMatch(result(percent: 20));
      expect(r.country, 0);
      expect(r.countryBefore, 0);
      expect(r.countryAfter, closeTo(countryGain(percent: 20, won: false), 1e-9));
      final again = await reopen();
      expect(again.countryProgress[0], closeTo(r.countryAfter, 1e-3));
    });

    test('a win fills faster than a loss', () {
      expect(countryGain(percent: 20, won: true), greaterThan(countryGain(percent: 20, won: false)));
      expect(countryGain(percent: 0, won: false), greaterThan(0), reason: 'every run moves forward');
    });

    test('completion pays once, caps at 100, unlocks and selects the next country', () async {
      final s = await openWith({
        'countryProgress': ['95.0'],
      });
      final coins0 = s.coins, gems0 = s.gems;
      final r = await s.recordMatch(result(percent: 30, won: true));
      expect(r.countryCompleted, isTrue);
      expect(s.countryProgress[0], 100);
      expect(r.countryCoins, kCountries[0].coins);
      expect(s.gems, gems0 + kCountries[0].gems);
      expect(s.coins, coins0 + r.totalCoins);
      expect(s.isCountryUnlocked(1), isTrue);
      expect(s.selectedCountry, 1);
      expect(s.currentCountry, 1);

      // Playing the finished country again never pays the reward twice.
      await s.selectCountry(0);
      final again = await s.recordMatch(result(percent: 30, won: true, country: 0));
      expect(again.countryCompleted, isFalse);
      expect(again.countryCoins, 0);
      expect(s.countryProgress[0], 100);
    });

    test('a match in a locked country does not count', () async {
      final s = await openWith();
      final r = await s.recordMatch(result(country: 5));
      expect(r.country, -1);
      expect(s.countryProgress[5], 0);
    });

    test('corrupt stored progress is clamped; a locked stored selection falls back', () async {
      final s = await openWith({
        'countryProgress': ['250', 'x', '-3'],
        'selectedCountry': 2,
      });
      expect(s.countryProgress[0], 100);
      expect(s.countryProgress[1], 0);
      expect(s.countryProgress[2], 0);
      expect(s.selectedCountry, 1, reason: 'country 2 is locked, fall back to the current one');
    });
  });

  group('event windows', () {
    test('windows are contiguous 7-day blocks', () {
      final a = eventAt(DateTime.utc(2026, 10, 19));
      expect(a.end.difference(a.start), kEventLength);
      final b = eventAt(a.end);
      expect(b.id, a.id + 1);
      expect(b.start, a.end);
      expect(eventAt(a.end.subtract(const Duration(seconds: 1))).id, a.id);
      expect(a.remaining(a.end.add(const Duration(hours: 1))), Duration.zero);
    });

    test('remaining time formatting', () {
      expect(formatRemaining(const Duration(days: 1, hours: 23, minutes: 5)), '1d 23h');
      expect(formatRemaining(const Duration(hours: 5, minutes: 12)), '5h 12m');
      expect(formatRemaining(const Duration(minutes: 42)), '42m');
    });
  });

  group('event rewards', () {
    test('matches add tokens; milestones claim once', () async {
      final s = await openWith();
      final r = await s.recordMatch(result(percent: 30, kills: 2, won: true));
      expect(r.eventTokens, tokensForMatch(percent: 30, kills: 2, won: true));
      expect(s.eventTokens, r.eventTokens);
      expect(s.eventTokens, greaterThanOrEqualTo(kMilestones[0].goal));
      final coins0 = s.coins;
      expect(s.canClaim(0), isTrue);
      expect(s.canClaim(1), isFalse, reason: 'not enough tokens');
      expect(await s.claimMilestone(1), isNull);
      final m = await s.claimMilestone(0);
      expect(m, isNotNull);
      expect(s.coins, coins0 + kMilestones[0].amount);
      expect(await s.claimMilestone(0), isNull, reason: 'no duplicate claims');
      expect(s.coins, coins0 + kMilestones[0].amount);
      final again = await reopen();
      expect(again.eventClaimed, {0});
      expect(again.canClaim(0), isFalse, reason: 'claimed state persists');
    });

    test('skin milestone grants the event skin; a second copy pays gems', () async {
      final skinIndex = kMilestones.indexWhere((m) => m.kind == RewardKind.skin);
      final id = kMilestones[skinIndex].skinId!;
      final s = await openWith({'eventId': eventAt(now).id, 'eventTokens': 999});
      expect(s.isUnlocked(skinById(id)), isFalse, reason: 'event skins are not free');
      await s.claimMilestone(skinIndex);
      expect(s.isUnlocked(skinById(id)), isTrue);

      final t = await openWith({
        'eventId': eventAt(now).id,
        'eventTokens': 999,
        'ownedSkins': ['sunny', id],
      });
      final gems0 = t.gems;
      await t.claimMilestone(skinIndex);
      expect(t.gems, gems0 + 30);
    });

    test('expired event resets tokens and claims; old milestones cannot be claimed', () async {
      final s = await openWith({'eventId': eventAt(now).id, 'eventTokens': 80, 'eventClaimed': ['0']});
      expect(s.canClaim(1), isTrue);
      now = s.currentEvent.end.add(const Duration(minutes: 1));
      expect(s.canClaim(1), isFalse, reason: 'window ended');
      expect(await s.claimMilestone(1), isNull);
      expect(s.eventTokens, 0);
      expect(s.eventClaimed, isEmpty);
      expect(s.eventId, eventAt(now).id);
    });

    test('turning the device clock back does not reset or reopen the event', () async {
      final s = await openWith({'eventId': eventAt(now).id, 'eventTokens': 40});
      final id = s.eventId;
      final left = s.currentEvent.remaining(s.now);
      now = now.subtract(const Duration(days: 9));
      expect(s.currentEvent.id, id);
      expect(await s.refreshEvent(), isFalse);
      expect(s.eventTokens, 40);
      expect(s.currentEvent.remaining(s.now), left, reason: 'countdown does not grow back');
      // Also after a restart: the last seen time is saved.
      await s.update((_) {});
      final again = await reopen();
      expect(again.eventId, id);
      expect(again.eventTokens, 40);
    });

    test('opening the app in a new event week starts a fresh track', () async {
      final old = eventAt(now).id - 1;
      final s = await openWith({'eventId': old, 'eventTokens': 150, 'eventClaimed': ['0', '1']});
      expect(s.eventId, eventAt(now).id);
      expect(s.eventTokens, 0);
      expect(s.eventClaimed, isEmpty);
    });
  });

  group('gem skins', () {
    test('gem skins can only be bought with gems', () async {
      final aurora = skinById('aurora');
      final s = await openWith({'coins': 99999, 'gems': aurora.gemCost - 1});
      expect(s.isUnlocked(aurora), isFalse);
      expect(s.canBuy(aurora), isFalse);
      expect(await s.buySkinWithGems(aurora), isFalse);
      await s.update((st) => st.gems += 1);
      expect(await s.buySkinWithGems(aurora), isTrue);
      expect(s.gems, 0);
      expect(s.selectedSkin, 'aurora');
    });
  });
}
