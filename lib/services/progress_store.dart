import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:math' as math;

import '../game/event.dart';
import '../game/progression.dart';
import '../game/sim/levels.dart';
import '../game/sim/skins.dart';
import '../game/world.dart';

/// Result of one match, used to update persistent progress.
class MatchResult {
  const MatchResult({
    required this.level,
    required this.won,
    required this.percent,
    required this.kills,
    required this.seconds,
    this.country = -1,
    this.bonusCoins = 0,
    this.bonusGems = 0,
  });

  final int level;

  /// Loot collected in the bonus round (before the multiplier).
  final int bonusCoins;
  final int bonusGems;

  /// Index into [kCountries] the match was played in (-1 = none).
  final int country;
  final bool won;
  final double percent;
  final int kills;
  final double seconds;

  int get coins =>
      (percent * 2).round() + kills * 15 + (won ? 40 + level * 10 : 0);

  int get xp => xpForMatch(percent: percent, kills: kills, won: won, level: level);
}

/// Everything a match granted, for the results screen.
class MatchRewards {
  const MatchRewards({
    required this.coins,
    required this.xp,
    required this.rankBefore,
    required this.rankAfter,
    required this.rankCoins,
    required this.achievements,
    required this.unlockedSkins,
    this.country = -1,
    this.countryBefore = 0,
    this.countryAfter = 0,
    this.countryCompleted = false,
    this.countryCoins = 0,
    this.countryGems = 0,
    this.eventTokens = 0,
    this.bonusCoins = 0,
    this.bonusGems = 0,
  });

  /// Bonus-round loot waiting for the multiplier (see [ProgressStore.claimBonus]).
  final int bonusCoins;
  final int bonusGems;

  /// Country progress (0..100) before/after this match.
  final int country;
  final double countryBefore;
  final double countryAfter;

  /// True only for the match that took the country to 100%.
  final bool countryCompleted;
  final int countryCoins;
  final int countryGems;
  final int eventTokens;

  /// Coins for the match itself (see [MatchResult.coins]).
  final int coins;
  final int xp;
  final int rankBefore;
  final int rankAfter;

  /// Coins granted for the rank-ups.
  final int rankCoins;
  final List<Achievement> achievements;
  final List<Skin> unlockedSkins;

  bool get rankedUp => rankAfter > rankBefore;
  int get achievementCoins => achievements.fold(0, (a, b) => a + b.reward);
  int get totalCoins => coins + rankCoins + achievementCoins + countryCoins;
}

/// Settings + progression persisted with SharedPreferences.
class ProgressStore extends ChangeNotifier {
  ProgressStore(this._prefs) {
    _load();
  }

  static Future<ProgressStore> open() async {
    final store = ProgressStore(await SharedPreferences.getInstance());
    // Loot from a bonus round the app was closed during is paid out at x1.
    if (store.hasPendingBonus) await store.claimBonus(1);
    return store;
  }

  /// Clock used for timed events; replaced in tests.
  static DateTime Function() clock = DateTime.now;

  final SharedPreferences _prefs;

  // Settings
  bool sound = true;
  bool music = true;
  bool haptics = true;
  bool showFps = false;
  SpeedSetting speed = SpeedSetting.normal;
  double sfxVolume = 1;
  double musicVolume = 1;
  // Online identity: nickname, a random guest id (never leaves the device
  // except to the game server), the Play Games player if signed in, and an
  // optional server address override.
  String onlineName = '';
  String guestId = '';
  String playGamesId = '';
  String playGamesName = '';
  String serverUrl = '';
  bool notificationsEnabled = true;
  bool notifPermissionAsked = false;
  bool notifPermissionGranted = false;

  // Progress
  int level = 1;
  int coins = 0;
  double bestPercent = 0;
  int totalKills = 0;
  int gamesPlayed = 0;
  int wins = 0;
  bool tutorialSeen = false;
  String selectedSkin = kSkins.first.id;
  Set<String> ownedSkins = {kSkins.first.id};
  int xp = 0;
  int bestKills = 0;
  Set<String> achievements = {};
  int gems = 0;

  /// Highest rank the player has acknowledged (drives the RANK UP! badge).
  int seenRank = 1;
  bool get hasUnseenRankUp => rank > seenRank;

  // World map: fill % per campaign country, the selected country, and which
  // completion rewards were already paid.
  List<double> countryProgress = List.filled(kCountries.length, 0);
  int selectedCountry = 0;
  Set<String> countryRewarded = {};

  // Timed event: tokens and claimed milestones belong to [eventId].
  int eventId = -1;
  int eventTokens = 0;
  Set<int> eventClaimed = {};

  /// Unlocked skins the player has already looked at (others show "NEW").
  Set<String> seenSkins = {};

  /// Completed countries whose celebration already played on the map.
  Set<String> celebratedCountries = {};
  bool powersIntroSeen = false;

  // Bonus-round loot saved until the multiplier is chosen, so it is paid
  // exactly once even if the app closes in between.
  int pendingBonusCoins = 0;
  int pendingBonusGems = 0;
  bool get hasPendingBonus => pendingBonusCoins > 0 || pendingBonusGems > 0;

  /// The Ink Splash power unlocks at this level.
  static const int powersLevel = 3;
  bool get powersUnlocked => level >= powersLevel;

  int get countriesCompleted => countryProgress.where((v) => v >= 100).length;

  /// The id sent to online servers: the Play Games id when signed in,
  /// otherwise a random guest id (created on first use).
  Future<String> ensurePlayerId() async {
    if (playGamesId.isNotEmpty) return playGamesId;
    if (guestId.isEmpty) {
      final r = math.Random.secure();
      final id = 'g-${List.generate(16, (_) => r.nextInt(16).toRadixString(16)).join()}';
      await update((st) => st.guestId = id);
    }
    return guestId;
  }

  int get rank => rankForXp(xp);

  /// XP earned inside the current rank, and XP needed for the next one.
  int get rankXp => xp - xpForRank(rank);
  int get rankXpNeeded => xpToNextRank(rank);

  void _load() {
    final p = _prefs;
    sound = p.getBool('sound') ?? true;
    music = p.getBool('music') ?? true;
    haptics = p.getBool('haptics') ?? true;
    showFps = p.getBool('showFps') ?? false;
    onlineName = p.getString('onlineName') ?? '';
    guestId = p.getString('guestId') ?? '';
    playGamesId = p.getString('playGamesId') ?? '';
    playGamesName = p.getString('playGamesName') ?? '';
    serverUrl = p.getString('serverUrl') ?? '';
    notificationsEnabled = p.getBool('notificationsEnabled') ?? true;
    notifPermissionAsked = p.getBool('notifPermissionAsked') ?? false;
    notifPermissionGranted = p.getBool('notifPermissionGranted') ?? false;
    sfxVolume = (p.getDouble('sfxVolume') ?? 1).clamp(0.0, 1.0).toDouble();
    musicVolume = (p.getDouble('musicVolume') ?? 1).clamp(0.0, 1.0).toDouble();
    final si = p.getInt('speed') ?? SpeedSetting.normal.index;
    speed = SpeedSetting
        .values[si.clamp(0, SpeedSetting.values.length - 1).toInt()];
    level = (p.getInt('level') ?? 1).clamp(1, 999).toInt();
    coins = p.getInt('coins') ?? 0;
    bestPercent = p.getDouble('bestPercent') ?? 0;
    totalKills = p.getInt('totalKills') ?? 0;
    gamesPlayed = p.getInt('gamesPlayed') ?? 0;
    wins = p.getInt('wins') ?? 0;
    tutorialSeen = p.getBool('tutorialSeen') ?? false;
    xp = (p.getInt('xp') ?? 0).clamp(0, 1 << 30).toInt();
    bestKills = (p.getInt('bestKills') ?? 0).clamp(0, 9999).toInt();
    achievements = (p.getStringList('achievements') ?? const <String>[])
        .where((id) => achievementById(id) != null)
        .toSet();
    gems = (p.getInt('gems') ?? 0).clamp(0, 1 << 30).toInt();
    seenRank = (p.getInt('seenRank') ?? 1).clamp(1, 9999).toInt();
    final cp = p.getStringList('countryProgress') ?? const <String>[];
    countryProgress = List.generate(kCountries.length,
        (i) => i < cp.length ? (double.tryParse(cp[i]) ?? 0).clamp(0.0, 100.0).toDouble() : 0.0);
    countryRewarded = (p.getStringList('countryRewarded') ?? const <String>[])
        .where((iso) => countryIndex(iso) >= 0)
        .toSet();
    selectedCountry = (p.getInt('selectedCountry') ?? 0).clamp(0, kCountries.length - 1).toInt();
    if (!isCountryUnlocked(selectedCountry)) selectedCountry = currentCountry;
    _lastSeen = DateTime.fromMillisecondsSinceEpoch(p.getInt('lastSeenMs') ?? 0, isUtc: true);
    eventId = p.getInt('eventId') ?? -1;
    eventTokens = (p.getInt('eventTokens') ?? 0).clamp(0, 1 << 30).toInt();
    eventClaimed = (p.getStringList('eventClaimed') ?? const <String>[])
        .map(int.tryParse)
        .whereType<int>()
        .where((i) => i >= 0 && i < kMilestones.length)
        .toSet();
    _rollEvent();
    ownedSkins = (p.getStringList('ownedSkins') ?? [kSkins.first.id]).toSet()
      ..add(kSkins.first.id);
    celebratedCountries = (p.getStringList('celebratedCountries') ?? const <String>[]).toSet();
    powersIntroSeen = p.getBool('powersIntroSeen') ?? false;
    seenFeaturedDay = p.getInt('seenFeaturedDay') ?? -1;
    pendingBonusCoins = (p.getInt('pendingBonusCoins') ?? 0).clamp(0, 1 << 24).toInt();
    pendingBonusGems = (p.getInt('pendingBonusGems') ?? 0).clamp(0, 1 << 24).toInt();
    final seen = p.getStringList('seenSkins');
    // First run with this feature: everything already unlocked counts as seen.
    seenSkins = seen == null ? kSkins.where(isUnlocked).map((s) => s.id).toSet() : seen.toSet();
    // skinById falls back to the first skin for unknown ids.
    selectedSkin = skinById(p.getString('selectedSkin') ?? kSkins.first.id).id;
    if (!isUnlocked(skinById(selectedSkin))) selectedSkin = kSkins.first.id;
  }

  Future<void> _save() async {
    final p = _prefs;
    await Future.wait([
      p.setBool('sound', sound),
      p.setBool('music', music),
      p.setBool('haptics', haptics),
      p.setBool('showFps', showFps),
      p.setString('onlineName', onlineName),
      p.setString('guestId', guestId),
      p.setString('playGamesId', playGamesId),
      p.setString('playGamesName', playGamesName),
      p.setString('serverUrl', serverUrl),
      p.setBool('notificationsEnabled', notificationsEnabled),
      p.setBool('notifPermissionAsked', notifPermissionAsked),
      p.setBool('notifPermissionGranted', notifPermissionGranted),
      p.setDouble('sfxVolume', sfxVolume),
      p.setDouble('musicVolume', musicVolume),
      p.setInt('xp', xp),
      p.setInt('bestKills', bestKills),
      p.setStringList('achievements', achievements.toList()),
      p.setInt('gems', gems),
      p.setInt('seenRank', seenRank),
      p.setStringList('countryProgress', [for (final v in countryProgress) v.toStringAsFixed(3)]),
      p.setStringList('countryRewarded', countryRewarded.toList()),
      p.setInt('selectedCountry', selectedCountry),
      p.setInt('eventId', eventId),
      p.setInt('lastSeenMs', now.millisecondsSinceEpoch),
      p.setInt('eventTokens', eventTokens),
      p.setStringList('eventClaimed', [for (final i in eventClaimed) '$i']),
      p.setInt('speed', speed.index),
      p.setInt('level', level),
      p.setInt('coins', coins),
      p.setDouble('bestPercent', bestPercent),
      p.setInt('totalKills', totalKills),
      p.setInt('gamesPlayed', gamesPlayed),
      p.setInt('wins', wins),
      p.setBool('tutorialSeen', tutorialSeen),
      p.setString('selectedSkin', selectedSkin),
      p.setStringList('ownedSkins', ownedSkins.toList()),
      p.setStringList('seenSkins', seenSkins.toList()),
      p.setStringList('celebratedCountries', celebratedCountries.toList()),
      p.setBool('powersIntroSeen', powersIntroSeen),
      p.setInt('seenFeaturedDay', seenFeaturedDay),
      p.setInt('pendingBonusCoins', pendingBonusCoins),
      p.setInt('pendingBonusGems', pendingBonusGems),
    ]);
  }

  Future<void> update(void Function(ProgressStore s) change) async {
    change(this);
    notifyListeners();
    await _save();
  }

  bool isUnlocked(Skin s) =>
      ownedSkins.contains(s.id) || (s.cost == 0 && s.gemCost == 0 && !s.eventReward && requirementsMet(s));

  bool canBuyWithGems(Skin s) => !isUnlocked(s) && s.gemCost > 0 && gems >= s.gemCost;

  /// Buys [s] for gems if affordable. Returns true on success.
  Future<bool> buySkinWithGems(Skin s) async {
    if (!canBuyWithGems(s)) return false;
    await update((st) {
      st.gems -= s.gemCost;
      st.ownedSkins.add(s.id);
      st.selectedSkin = s.id;
    });
    return true;
  }

  // ---- world map -------------------------------------------------------

  bool isCountryComplete(int i) => countryProgress[i] >= 100;

  /// The first country is open; each next one opens when the previous is full.
  bool isCountryUnlocked(int i) => i == 0 || (i > 0 && i < kCountries.length && isCountryComplete(i - 1));

  /// First unlocked country that is not complete (the last one when all are).
  int get currentCountry {
    for (var i = 0; i < kCountries.length; i++) {
      if (!isCountryComplete(i)) return i;
    }
    return kCountries.length - 1;
  }

  Future<void> selectCountry(int i) async {
    if (i < 0 || i >= kCountries.length || !isCountryUnlocked(i)) return;
    await update((st) => st.selectedCountry = i);
  }

  // ---- timed event -----------------------------------------------------

  /// Latest time seen (persisted). Event timing never goes backwards, so
  /// turning the device clock back cannot reopen or reset an event window.
  DateTime _lastSeen = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  DateTime get now {
    final n = clock();
    if (n.isAfter(_lastSeen)) _lastSeen = n;
    return _lastSeen;
  }

  EventWindow get currentEvent => eventAt(now);

  /// Starts a fresh track when the stored event has expired.
  void _rollEvent() {
    final id = currentEvent.id;
    if (eventId == id) return;
    eventId = id;
    eventTokens = 0;
    eventClaimed = {};
  }

  /// Re-checks the event window (e.g. when a screen opens). Returns true if a
  /// new event started.
  Future<bool> refreshEvent() async {
    if (eventId == currentEvent.id) return false;
    await update((st) => st._rollEvent());
    return true;
  }

  bool canClaim(int i) =>
      i >= 0 &&
      i < kMilestones.length &&
      eventId == currentEvent.id &&
      !eventClaimed.contains(i) &&
      eventTokens >= kMilestones[i].goal;

  /// Grants milestone [i] once. A skin that is already owned pays 30 gems
  /// instead. Returns the milestone, or null when it cannot be claimed.
  Future<Milestone?> claimMilestone(int i) async {
    await refreshEvent();
    if (!canClaim(i)) return null;
    final m = kMilestones[i];
    await update((st) {
      st.eventClaimed.add(i);
      switch (m.kind) {
        case RewardKind.coins:
          st.coins += m.amount;
        case RewardKind.gems:
          st.gems += m.amount;
        case RewardKind.skin:
          if (st.ownedSkins.add(m.skinId!)) {
            st.selectedSkin = m.skinId!;
          } else {
            st.gems += 30;
          }
      }
    });
    return m;
  }

  /// Level / rank / achievement requirements (coin price excluded).
  bool requirementsMet(Skin s) =>
      (s.unlockCountries == 0 || countriesCompleted >= s.unlockCountries) &&
      (s.unlockLevel == 0 || level >= s.unlockLevel) &&
      (s.unlockRank == 0 || rank >= s.unlockRank) &&
      (s.unlockAchievement == null || achievements.contains(s.unlockAchievement));

  /// Human-readable unlock requirement, e.g. "Reach level 3".
  String requirementText(Skin s) {
    if (s.unlockCountries > 0) return 'Complete ${s.unlockCountries} countries';
    if (s.unlockLevel > 0) return 'Reach level ${s.unlockLevel}';
    if (s.unlockRank > 0) return 'Reach rank ${s.unlockRank}';
    if (s.eventReward) return 'Ink Festival reward';
    if (s.gemCost > 0) return '${s.gemCost} gems';
    final a = s.unlockAchievement == null ? null : achievementById(s.unlockAchievement!);
    if (a != null) return 'Achievement: ${a.title}';
    return '${priceOf(s)} coins';
  }

  int get skinsOwned => kSkins.where(isUnlocked).length;

  StatsSnapshot get stats => StatsSnapshot(
        gamesPlayed: gamesPlayed,
        wins: wins,
        totalKills: totalKills,
        bestPercent: bestPercent,
        bestKills: bestKills,
        level: level,
        rank: rank,
        skinsOwned: skinsOwned,
      );

  /// Today's featured skin (changes at UTC midnight) and its half price.
  Skin get featured => featuredSkin(now);
  bool isFeatured(Skin s) => s.id == featured.id;

  /// Coins to buy [s] right now: half price while featured.
  int priceOf(Skin s) => isFeatured(s) ? (s.cost / 2).round() : s.cost;

  /// The featured deal the player has already looked at (a day index).
  int seenFeaturedDay = -1;
  bool get hasNewFeatured => seenFeaturedDay != dayIndex(now) && !isUnlocked(featured);

  Future<void> markFeaturedSeen() async {
    if (seenFeaturedDay == dayIndex(now)) return;
    await update((st) => st.seenFeaturedDay = dayIndex(now));
  }

  bool canBuy(Skin s) => !isUnlocked(s) && s.cost > 0 && coins >= priceOf(s);

  /// Buys [s] if affordable. Returns true on success.
  Future<bool> buySkin(Skin s) async {
    if (!canBuy(s)) return false;
    final price = priceOf(s);
    await update((st) {
      st.coins -= price;
      st.ownedSkins.add(s.id);
      st.selectedSkin = s.id;
    });
    return true;
  }

  Future<void> selectSkin(Skin s) async {
    if (!isUnlocked(s)) return;
    await update((st) => st.selectedSkin = s.id);
  }

  /// Takes the current skin off (back to the default character).
  Future<void> unequipSkin() => update((st) => st.selectedSkin = kSkins.first.id);

  bool isNewSkin(Skin s) => isUnlocked(s) && !seenSkins.contains(s.id);
  int get newSkinCount => kSkins.where(isNewSkin).length;

  Future<void> markSkinSeen(Skin s) async {
    if (!isNewSkin(s)) return;
    await update((st) => st.seenSkins.add(s.id));
  }

  /// Pays the saved bonus-round loot times [multiplier] (1..4) exactly once.
  /// Returns the coins and gems paid, or null when nothing is pending.
  Future<(int, int)?> claimBonus(int multiplier) async {
    if (!hasPendingBonus) return null;
    final m = multiplier.clamp(1, 4);
    final c = pendingBonusCoins * m, g = pendingBonusGems * m;
    await update((st) {
      st.coins += c;
      st.gems += g;
      st.pendingBonusCoins = 0;
      st.pendingBonusGems = 0;
    });
    return (c, g);
  }

  /// Completed countries not yet celebrated on the map; marks them done.
  Future<List<int>> takeUncelebratedCountries() async {
    final out = [
      for (var i = 0; i < kCountries.length; i++)
        if (isCountryComplete(i) && !celebratedCountries.contains(kCountries[i].iso)) i
    ];
    if (out.isNotEmpty) {
      await update((st) => st.celebratedCountries.addAll(out.map((i) => kCountries[i].iso)));
    }
    return out;
  }

  /// Applies a match result: coins, XP/rank-ups, achievements (which may
  /// cascade, e.g. a rank-up completing "Rising Star") and skin unlocks.
  Future<MatchRewards> recordMatch(MatchResult r) async {
    final before = kSkins.where(isUnlocked).map((s) => s.id).toSet();
    final rankBefore = rank;
    final earned = <Achievement>[];
    var rankCoins = 0;
    final ci = r.country;
    final hasCountry = ci >= 0 && ci < kCountries.length && isCountryUnlocked(ci);
    final countryBefore = hasCountry ? countryProgress[ci] : 0.0;
    var countryCompleted = false;
    var countryCoins = 0, countryGems = 0;
    _rollEvent();
    final tokens = tokensForMatch(percent: r.percent, kills: r.kills, won: r.won);
    await update((st) {
      st.eventTokens += tokens;
      if (r.bonusCoins > 0 || r.bonusGems > 0) {
        // Any older unclaimed loot is paid first so nothing is lost.
        st.coins += st.pendingBonusCoins;
        st.gems += st.pendingBonusGems;
        st.pendingBonusCoins = r.bonusCoins;
        st.pendingBonusGems = r.bonusGems;
      }
      if (hasCountry) {
        st.countryProgress[ci] = math.min(100.0, countryBefore + countryGain(percent: r.percent, won: r.won));
        final def = kCountries[ci];
        if (st.countryProgress[ci] >= 100 && st.countryRewarded.add(def.iso)) {
          countryCompleted = true;
          countryCoins = def.coins;
          countryGems = def.gems;
          st.coins += countryCoins;
          st.gems += countryGems;
          // Move on to the newly opened country.
          if (ci + 1 < kCountries.length) st.selectedCountry = ci + 1;
        }
      }
      st.gamesPlayed++;
      st.coins += r.coins;
      st.totalKills += r.kills;
      if (r.kills > st.bestKills) st.bestKills = r.kills;
      if (r.percent > st.bestPercent) st.bestPercent = r.percent;
      if (r.won) {
        st.wins++;
        if (r.level >= st.level) st.level = r.level + 1;
      }
      st.xp += r.xp;
      for (var k = rankBefore + 1; k <= st.rank; k++) {
        rankCoins += rankReward(k);
      }
      st.coins += rankCoins;
      // Achievements can unlock skins, which can complete "Collector".
      var changed = true;
      while (changed) {
        changed = false;
        final snap = st.stats;
        for (final a in kAchievements) {
          if (!st.achievements.contains(a.id) && a.test(snap)) {
            st.achievements.add(a.id);
            st.coins += a.reward;
            earned.add(a);
            changed = true;
          }
        }
      }
    });
    final unlocked = kSkins.where((s) => isUnlocked(s) && !before.contains(s.id)).toList();
    // A freshly unlocked skin is worn straight away in the next game.
    if (unlocked.isNotEmpty) await update((st) => st.selectedSkin = unlocked.last.id);
    return MatchRewards(
      coins: r.coins,
      xp: r.xp,
      rankBefore: rankBefore,
      rankAfter: rank,
      rankCoins: rankCoins,
      achievements: earned,
      unlockedSkins: unlocked,
      country: hasCountry ? ci : -1,
      countryBefore: countryBefore,
      countryAfter: hasCountry ? countryProgress[ci] : 0,
      countryCompleted: countryCompleted,
      countryCoins: countryCoins,
      countryGems: countryGems,
      eventTokens: tokens,
      bonusCoins: r.bonusCoins,
      bonusGems: r.bonusGems,
    );
  }

  Future<void> resetProgress() async {
    await update((st) {
      st.level = 1;
      st.coins = 0;
      st.bestPercent = 0;
      st.totalKills = 0;
      st.gamesPlayed = 0;
      st.wins = 0;
      st.tutorialSeen = false;
      st.selectedSkin = kSkins.first.id;
      st.ownedSkins = {kSkins.first.id};
      st.xp = 0;
      st.bestKills = 0;
      st.achievements = {};
      st.gems = 0;
      st.seenRank = 1;
      st.countryProgress = List.filled(kCountries.length, 0);
      st.countryRewarded = {};
      st.selectedCountry = 0;
      st.eventTokens = 0;
      st.eventClaimed = {};
      st.seenSkins = {kSkins.first.id};
      st.celebratedCountries = {};
      st.powersIntroSeen = false;
      st.seenFeaturedDay = -1;
      st.pendingBonusCoins = 0;
      st.pendingBonusGems = 0;
    });
  }
}
