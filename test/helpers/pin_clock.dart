import 'package:inktide/game/sim/skins.dart';
import 'package:inktide/services/progress_store.dart';

/// Pins the store clock to a day on which the 50%-off skin is Thor, so tests
/// that buy other skins see their normal prices. Call [unpinClock] in tearDown.
void pinClockAwayFromDeals() {
  var t = DateTime.utc(2026, 10, 19, 12);
  while (featuredSkin(t).id != 'thor') {
    t = t.add(const Duration(days: 1));
  }
  ProgressStore.clock = () => t;
}

void unpinClock() => ProgressStore.clock = DateTime.now;
