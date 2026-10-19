import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inktide/game/sim/skins.dart';
import 'package:inktide/services/feedback.dart';
import 'package:inktide/services/progress_store.dart';

import 'app_flow_test.dart' show launchApp, pumpFor, tapKey, tearDownApp;

void main() {
  setUp(() {
    GameFeedback.enabled = false;
    var t = DateTime.utc(2026, 10, 19, 12);
    while (featuredSkin(t).id != 'apple') {
      t = t.add(const Duration(days: 1));
    }
    ProgressStore.clock = () => t;
  });
  tearDown(() => ProgressStore.clock = DateTime.now);

  testWidgets('daily deal: banner, 50% OFF ribbon and half-price purchase', (tester) async {
    final store = await launchApp(tester, prefs: {'coins': 500});
    expect(find.byKey(const Key('skinsButton')), findsOneWidget);
    await tapKey(tester, 'skinsButton', settle: const Duration(milliseconds: 900));
    expect(find.byKey(const Key('featuredBanner')), findsOneWidget);
    expect(find.text('TODAY: APPLE'), findsOneWidget);
    expect(find.text('50% OFF  •  75 coins'), findsOneWidget);
    expect(find.byKey(const Key('featuredTimer')), findsOneWidget);
    expect(store.hasNewFeatured, isFalse, reason: 'opening the shop sees the deal');
    await tester.scrollUntilVisible(find.byKey(const Key('skin_apple')), 300,
        scrollable: find.byType(Scrollable).last);
    await pumpFor(tester, const Duration(milliseconds: 300));
    expect(find.byKey(const Key('deal_apple')), findsOneWidget);
    await tester.tap(find.byKey(const Key('skin_apple')));
    await pumpFor(tester, const Duration(milliseconds: 300));
    expect(find.text('Spend 75 coins?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirmBuy')));
    await pumpFor(tester, const Duration(milliseconds: 700));
    expect(store.coins, 425);
    expect(store.ownedSkins, contains('apple'));
    expect(find.byKey(const Key('capsuleRarity')), findsOneWidget, reason: 'new skin opens a capsule');
    await tearDownApp(tester);
  });
}
