import 'dart:math' as math;

/// Campaign countries and the rules for filling them. Pure Dart.
class CountryDef {
  const CountryDef(this.iso, this.name, this.coins, this.gems, this.continent);
  final String iso;
  final String name;
  final String continent;

  /// Granted once when the country reaches 100%.
  final int coins;
  final int gems;
}

/// Campaign order; matches the playable countries in assets/data/world.json.
const List<CountryDef> kCountries = [
  CountryDef('CAN', 'Canada', 1000, 5, 'North America'),
  CountryDef('USA', 'United States', 1200, 5, 'North America'),
  CountryDef('MEX', 'Mexico', 1400, 8, 'North America'),
  CountryDef('BRA', 'Brazil', 1600, 8, 'South America'),
  CountryDef('GBR', 'United Kingdom', 1800, 10, 'Europe'),
  CountryDef('FRA', 'France', 2000, 10, 'Europe'),
  CountryDef('DEU', 'Germany', 2200, 12, 'Europe'),
  CountryDef('ITA', 'Italy', 2400, 12, 'Europe'),
  CountryDef('EGY', 'Egypt', 2600, 15, 'Africa'),
  CountryDef('IND', 'India', 2800, 15, 'Asia'),
  CountryDef('JPN', 'Japan', 3000, 20, 'Asia'),
  CountryDef('AUS', 'Australia', 3500, 25, 'Oceania'),
];

int countryIndex(String iso) => kCountries.indexWhere((c) => c.iso == iso);

/// Country fill (in %) earned by one match: the territory you held, boosted
/// for a win. Always at least 1% so every run moves the country forward.
double countryGain({required double percent, required bool won}) =>
    math.max(1.0, percent * (won ? 1.6 : 0.7));


/// Continents in campaign order (countries of one continent are contiguous).
List<String> get kContinents {
  final out = <String>[];
  for (final c in kCountries) {
    if (out.isEmpty || out.last != c.continent) out.add(c.continent);
  }
  return out;
}

/// Indices of the countries in [continent].
List<int> countriesOf(String continent) =>
    [for (var i = 0; i < kCountries.length; i++) if (kCountries[i].continent == continent) i];
