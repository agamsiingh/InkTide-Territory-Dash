/// Cosmetic definitions. Colors are stored as ARGB ints so the simulation
/// stays free of Flutter imports.
enum Accessory {
  none,
  bunnyEars,
  horns,
  crown,
  leaf,
  antenna,
  catEars,
  star,
  fin,
  spikes,
  stem, // fruit stem with a leaf
  calyx, // strawberry leaf crown
  pineCrown, // pineapple spikes
  bananaTip,
  thor, // winged helmet, hair and cape
  unicorn, // spiral horn
  bearEars,
  pandaEars,
  pig, // ears + snout
  frog, // eye domes on top
  chick, // feather tuft + beak
  koala, // fluffy ears + big nose
  fox, // pointy ears with white tips
  penguin, // beak + flippers
  bow,
}

/// Markings painted on the body, clipped to its silhouette.
enum SkinPattern { none, stripes, seeds, belly, crosshatch, ribs, muzzle, pandaPatches, foxCheeks }

/// Collection tier, shown on capsules and skin cards.
enum Rarity { common, rare, epic, legendary }

/// Body silhouette drawn by the character painter.
enum BodyShape { cube, round, ghost, bean }

class Skin {
  const Skin({
    required this.id,
    required this.name,
    required this.color,
    required this.dark,
    required this.light,
    required this.accessory,
    required this.cost,
    this.unlockLevel = 0,
    this.unlockRank = 0,
    this.unlockAchievement,
    this.shape = BodyShape.cube,
    this.gemCost = 0,
    this.eventReward = false,
    this.unlockCountries = 0,
    this.pattern = SkinPattern.none,
  });

  final String id;
  final String name;
  final int color;
  final int dark;
  final int light;
  final Accessory accessory;

  /// Coin price. 0 = free / unlocked by a requirement below.
  final int cost;

  /// Level that must be reached to unlock (0 = none).
  final int unlockLevel;

  /// Player rank (from XP) that must be reached to unlock (0 = none).
  final int unlockRank;

  /// Achievement id that unlocks this skin (null = none).
  final String? unlockAchievement;

  final BodyShape shape;

  /// Gem price (0 = not sold for gems).
  final int gemCost;

  /// Only obtainable from an event reward track.
  final bool eventReward;

  /// Number of completed world-map countries needed (0 = none).
  final int unlockCountries;

  final SkinPattern pattern;

  Rarity get rarity {
    if (eventReward || gemCost > 0) return Rarity.legendary;
    if (unlockCountries > 0 || unlockAchievement != null || cost >= 500) return Rarity.epic;
    if (unlockLevel > 0 || unlockRank > 0 || cost >= 250) return Rarity.rare;
    return Rarity.common;
  }

  bool get isFree =>
      cost == 0 &&
      gemCost == 0 &&
      !eventReward &&
      unlockLevel == 0 &&
      unlockRank == 0 &&
      unlockAchievement == null &&
      unlockCountries == 0;
}

const List<Skin> kSkins = [
  Skin(
      id: 'sunny',
      name: 'Sunny',
      color: 0xFFFFC928,
      dark: 0xFFE89A00,
      light: 0xFFFFE680,
      accessory: Accessory.none,
      cost: 0),
  Skin(
      id: 'bubbles',
      name: 'Bubbles',
      color: 0xFFFF4FA3,
      dark: 0xFFC92A7A,
      light: 0xFFFFA8D2,
      accessory: Accessory.bunnyEars,
      cost: 120,
      shape: BodyShape.round),
  Skin(
      id: 'frost',
      name: 'Frost',
      color: 0xFF2EB7FF,
      dark: 0xFF1474C9,
      light: 0xFF9EDCFF,
      accessory: Accessory.horns,
      cost: 200),
  Skin(
      id: 'lime',
      name: 'Zesty',
      color: 0xFF7EDB3A,
      dark: 0xFF46A112,
      light: 0xFFC4F29A,
      accessory: Accessory.leaf,
      cost: 300,
      shape: BodyShape.bean),
  Skin(
      id: 'grape',
      name: 'Grape',
      color: 0xFF9B5CFF,
      dark: 0xFF6A2FD1,
      light: 0xFFCEB0FF,
      accessory: Accessory.antenna,
      cost: 0,
      unlockLevel: 3),
  Skin(
      id: 'tangerine',
      name: 'Tango',
      color: 0xFFFF8A2A,
      dark: 0xFFD45A00,
      light: 0xFFFFC294,
      accessory: Accessory.catEars,
      cost: 450),
  Skin(
      id: 'mint',
      name: 'Minty',
      color: 0xFF2FD9B0,
      dark: 0xFF119C7C,
      light: 0xFFA4F2DE,
      accessory: Accessory.star,
      cost: 600,
      shape: BodyShape.ghost),
  Skin(
      id: 'royal',
      name: 'Royal Ruby',
      color: 0xFFFF4757,
      dark: 0xFFC0202F,
      light: 0xFFFFA4AC,
      accessory: Accessory.crown,
      cost: 0,
      unlockLevel: 6),
  Skin(
      id: 'pebble',
      name: 'Pebble',
      color: 0xFF4FC3C9,
      dark: 0xFF22878C,
      light: 0xFFB2EEF0,
      accessory: Accessory.none,
      cost: 350,
      shape: BodyShape.round),
  Skin(
      id: 'jelly',
      name: 'Jelly Bean',
      color: 0xFFE84FD8,
      dark: 0xFFA8239B,
      light: 0xFFF7B3F0,
      accessory: Accessory.antenna,
      cost: 0,
      unlockRank: 4,
      shape: BodyShape.bean),
  Skin(
      id: 'boo',
      name: 'Boo',
      color: 0xFFE9E4FF,
      dark: 0xFF9C8FE0,
      light: 0xFFFFFFFF,
      accessory: Accessory.none,
      cost: 0,
      unlockAchievement: 'hunter',
      shape: BodyShape.ghost),
  Skin(
      id: 'splashy',
      name: 'Splashy',
      color: 0xFF5A8CFF,
      dark: 0xFF2F57C9,
      light: 0xFFBFD3FF,
      accessory: Accessory.fin,
      cost: 0,
      unlockAchievement: 'painter_50',
      shape: BodyShape.round),
  Skin(
      id: 'aurora',
      name: 'Aurora',
      color: 0xFF7C6CFF,
      dark: 0xFF4B3BD6,
      light: 0xFFC9C2FF,
      accessory: Accessory.star,
      cost: 0,
      gemCost: 60,
      shape: BodyShape.bean),
  Skin(
      id: 'ember',
      name: 'Ember',
      color: 0xFFFF7A1A,
      dark: 0xFFC24E00,
      light: 0xFFFFC08A,
      accessory: Accessory.horns,
      cost: 0,
      eventReward: true,
      shape: BodyShape.round),
  Skin(
      id: 'dino',
      name: 'Dino',
      color: 0xFF2F6BFF,
      dark: 0xFF1C3FB8,
      light: 0xFF9DBBFF,
      accessory: Accessory.spikes,
      cost: 0,
      unlockCountries: 3),
  Skin(
      id: 'whale',
      name: 'Whale',
      color: 0xFF3E7BD6,
      dark: 0xFF234E9C,
      light: 0xFFF2F8FF,
      accessory: Accessory.fin,
      cost: 450,
      shape: BodyShape.round,
      pattern: SkinPattern.belly),
  Skin(
      id: 'apple',
      name: 'Apple',
      color: 0xFFE8363D,
      dark: 0xFFA81D26,
      light: 0xFFFF9A9E,
      accessory: Accessory.stem,
      cost: 150,
      shape: BodyShape.round),
  Skin(
      id: 'banana',
      name: 'Banana',
      color: 0xFFFFE04A,
      dark: 0xFFD9A400,
      light: 0xFFFFF5A8,
      accessory: Accessory.bananaTip,
      cost: 150,
      shape: BodyShape.bean),
  Skin(
      id: 'strawberry',
      name: 'Strawberry',
      color: 0xFFFF4A5E,
      dark: 0xFFC22440,
      light: 0xFFFFE680,
      accessory: Accessory.calyx,
      cost: 220,
      shape: BodyShape.round,
      pattern: SkinPattern.seeds),
  Skin(
      id: 'watermelon',
      name: 'Melon',
      color: 0xFF4CC24E,
      dark: 0xFF1F7A2B,
      light: 0xFF9CE89B,
      accessory: Accessory.stem,
      cost: 260,
      shape: BodyShape.round,
      pattern: SkinPattern.stripes),
  Skin(
      id: 'cherry',
      name: 'Cherry',
      color: 0xFFC2123F,
      dark: 0xFF7E0A28,
      light: 0xFFFF7A9C,
      accessory: Accessory.stem,
      cost: 220,
      shape: BodyShape.round),
  Skin(
      id: 'pineapple',
      name: 'Pineapple',
      color: 0xFFFFC21F,
      dark: 0xFFC98A00,
      light: 0xFFFFE680,
      accessory: Accessory.pineCrown,
      cost: 320,
      shape: BodyShape.bean,
      pattern: SkinPattern.crosshatch),
  Skin(
      id: 'pumpkin',
      name: 'Pumpkin',
      color: 0xFFFF8A1F,
      dark: 0xFFC25A00,
      light: 0xFFFFC27A,
      accessory: Accessory.stem,
      cost: 280,
      shape: BodyShape.round,
      pattern: SkinPattern.ribs),
  Skin(
      id: 'thor',
      name: 'Thor',
      color: 0xFFF2C79B,
      dark: 0xFFC9945E,
      light: 0xFFFFE6CC,
      accessory: Accessory.thor,
      cost: 900),
  Skin(
      id: 'unicorn',
      name: 'Unicorn',
      color: 0xFFFFE3F4,
      dark: 0xFFD596BE,
      light: 0xFFFFFFFF,
      accessory: Accessory.unicorn,
      cost: 0,
      gemCost: 40,
      shape: BodyShape.bean),
  Skin(
      id: 'sweetie',
      name: 'Sweetie',
      color: 0xFFFF9FD2,
      dark: 0xFFE0609F,
      light: 0xFFFFE0F0,
      accessory: Accessory.bow,
      cost: 0,
      unlockLevel: 2),
  Skin(
      id: 'teddy',
      name: 'Teddy',
      color: 0xFFC08A5B,
      dark: 0xFF8A5A34,
      light: 0xFFF2D9BD,
      accessory: Accessory.bearEars,
      cost: 240,
      shape: BodyShape.round,
      pattern: SkinPattern.muzzle),
  Skin(
      id: 'bubblegum',
      name: 'Bubblegum',
      color: 0xFFFF7EB9,
      dark: 0xFFD6488A,
      light: 0xFFFFD6EA,
      accessory: Accessory.bearEars,
      cost: 300,
      shape: BodyShape.round,
      pattern: SkinPattern.muzzle),
  Skin(
      id: 'panda',
      name: 'Panda',
      color: 0xFFFAFAFA,
      dark: 0xFF34343F,
      light: 0xFFFFFFFF,
      accessory: Accessory.pandaEars,
      cost: 380,
      shape: BodyShape.round,
      pattern: SkinPattern.pandaPatches),
  Skin(
      id: 'piggy',
      name: 'Piggy',
      color: 0xFFFFADC8,
      dark: 0xFFE57A9E,
      light: 0xFFFFE3EC,
      accessory: Accessory.pig,
      cost: 200,
      shape: BodyShape.round),
  Skin(
      id: 'froggy',
      name: 'Froggy',
      color: 0xFF7ED957,
      dark: 0xFF3E9E2C,
      light: 0xFFD4F7B8,
      accessory: Accessory.frog,
      cost: 220,
      shape: BodyShape.bean),
  Skin(
      id: 'chick',
      name: 'Chick',
      color: 0xFFFFE45C,
      dark: 0xFFE0A800,
      light: 0xFFFFF6B8,
      accessory: Accessory.chick,
      cost: 180,
      shape: BodyShape.round),
  Skin(
      id: 'koala',
      name: 'Koala',
      color: 0xFFB4BDC8,
      dark: 0xFF7A8594,
      light: 0xFFE8EDF2,
      accessory: Accessory.koala,
      cost: 340,
      shape: BodyShape.round,
      pattern: SkinPattern.muzzle),
  Skin(
      id: 'foxy',
      name: 'Foxy',
      color: 0xFFFF8A3D,
      dark: 0xFFC85A14,
      light: 0xFFFFF4EA,
      accessory: Accessory.fox,
      cost: 360,
      pattern: SkinPattern.foxCheeks),
  Skin(
      id: 'pengu',
      name: 'Pengu',
      color: 0xFF3D4F78,
      dark: 0xFF243252,
      light: 0xFFFFFFFF,
      accessory: Accessory.penguin,
      cost: 420,
      shape: BodyShape.bean,
      pattern: SkinPattern.belly),
];


/// Skins that can take turns as the daily featured deal (coin-priced ones).
List<Skin> get kRotation => [for (final s in kSkins) if (s.cost > 0) s];

/// Day index (UTC) since the epoch.
int dayIndex(DateTime t) => t.toUtc().millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;

/// The skin on offer today at half price. Changes every UTC midnight.
Skin featuredSkin(DateTime now) {
  final r = kRotation;
  return r[dayIndex(now) % r.length];
}

/// Time left until the featured skin changes.
Duration featuredRemaining(DateTime now) {
  final n = now.toUtc();
  final next = DateTime.utc(n.year, n.month, n.day).add(const Duration(days: 1));
  return next.difference(n);
}

String rarityName(Rarity r) => switch (r) {
      Rarity.common => 'Common',
      Rarity.rare => 'Rare',
      Rarity.epic => 'Epic',
      Rarity.legendary => 'Legendary',
    };

Skin skinById(String id) =>
    kSkins.firstWhere((s) => s.id == id, orElse: () => kSkins.first);

const List<String> kBotNames = [
  'Splotch', 'Drizzle', 'Gloop', 'Pixel', 'Mochi', 'Zippy', 'Blot', 'Squish',
  'Nova', 'Jelly', 'Comet', 'Puddle', 'Fizz', 'Dash', 'Nugget', 'Smudge',
  'Tofu', 'Rocket', 'Biscuit', 'Wobble',
];
