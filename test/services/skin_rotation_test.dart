import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:inktide/game/sim/skins.dart';
import 'package:inktide/services/progress_store.dart';
import 'package:inktide/ui/blob_painter.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProgressStore> openWith([Map<String, Object> values = const {}]) async {
  SharedPreferences.setMockInitialValues(Map<String, Object>.of(values));
  return ProgressStore.open();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var now = DateTime.utc(2026, 10, 19, 12);
  setUp(() {
    now = DateTime.utc(2026, 10, 19, 12);
    ProgressStore.clock = () => now;
  });
  tearDown(() => ProgressStore.clock = DateTime.now);

  group('themed skins', () {
    test('whale, fruits and Thor exist with unique ids', () {
      final ids = kSkins.map((s) => s.id).toList();
      expect(ids.toSet().length, ids.length);
      for (final id in ['whale', 'apple', 'banana', 'strawberry', 'watermelon', 'cherry', 'pineapple', 'pumpkin', 'thor', 'unicorn']) {
        expect(ids, contains(id));
      }
      expect(skinById('unicorn').gemCost, 40);
      expect(skinById('whale').pattern, SkinPattern.belly);
      expect(skinById('thor').accessory, Accessory.thor);
    });

    test('every skin paints without errors, in every mood-free state', () {
      final rec = ui.PictureRecorder();
      final canvas = ui.Canvas(rec);
      for (final s in kSkins) {
        paintBlob(canvas, const ui.Offset(50, 50), 80, s);
        paintBlob(canvas, const ui.Offset(50, 50), 80, s, time: 1.3, seed: 4, squash: 0.2, stretch: 0.4, glow: 0.5);
      }
      rec.endRecording().dispose();
    });
  });

  group('daily featured skin', () {
    test('rotates every UTC day through coin-priced skins', () {
      final seen = <String>{};
      for (var d = 0; d < kRotation.length; d++) {
        seen.add(featuredSkin(now.add(Duration(days: d))).id);
      }
      expect(seen.length, kRotation.length, reason: 'a full cycle shows every skin once');
      expect(featuredSkin(now).id, featuredSkin(now.add(const Duration(hours: 5))).id);
      expect(featuredSkin(now).id, isNot(featuredSkin(now.add(const Duration(days: 1))).id));
      for (final s in kRotation) {
        expect(s.cost, greaterThan(0));
      }
    });

    test('countdown runs to the next UTC midnight', () {
      expect(featuredRemaining(DateTime.utc(2026, 10, 19, 23)), const Duration(hours: 1));
      expect(featuredRemaining(DateTime.utc(2026, 10, 19, 0)), const Duration(days: 1));
    });

    test('featured skin costs half and is bought at the half price', () async {
      final s = await openWith({'coins': 1000});
      final f = s.featured;
      expect(s.isFeatured(f), isTrue);
      expect(s.priceOf(f), (f.cost / 2).round());
      final other = kRotation.firstWhere((x) => x.id != f.id);
      expect(s.priceOf(other), other.cost);
      expect(await s.buySkin(f), isTrue);
      expect(s.coins, 1000 - (f.cost / 2).round());
      expect(s.isUnlocked(f), isTrue);
    });

    test('the deal changes with the day and cannot be afforded below its price', () async {
      final s = await openWith({'coins': 100});
      final f = s.featured;
      expect(s.canBuy(f), s.coins >= s.priceOf(f));
      final yesterday = f;
      now = now.add(const Duration(days: 1));
      expect(s.featured.id, isNot(yesterday.id));
      expect(s.priceOf(yesterday), yesterday.cost, reason: 'back to full price');
    });

    test('a new deal shows a badge until the shop is opened', () async {
      final s = await openWith();
      expect(s.hasNewFeatured, isTrue);
      await s.markFeaturedSeen();
      expect(s.hasNewFeatured, isFalse);
      now = now.add(const Duration(days: 1));
      expect(s.hasNewFeatured, isTrue);
      final again = await ProgressStore.open();
      expect(again.hasNewFeatured, isTrue);
    });

    test('an owned featured skin raises no badge', () async {
      final s = await openWith({'coins': 5000});
      await s.buySkin(s.featured);
      expect(s.hasNewFeatured, isFalse);
    });
  });
}
