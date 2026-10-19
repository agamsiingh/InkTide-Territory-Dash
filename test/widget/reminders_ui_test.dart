import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inktide/game/inktide_game.dart';
import 'package:inktide/services/feedback.dart';

import '../helpers/pin_clock.dart';
import 'app_flow_test.dart' show launchApp, pumpFor, tapKey, tearDownApp;

void main() {
  setUp(() {
    GameFeedback.enabled = false;
    InkTideGame.current = null;
    pinClockAwayFromDeals();
  });
  tearDown(unpinClock);

  testWidgets('settings: the Reminders switch is on by default and saves when toggled', (tester) async {
    final store = await launchApp(tester);
    expect(store.notificationsEnabled, isTrue);
    await tapKey(tester, 'settingsButton', settle: const Duration(milliseconds: 700));
    await tester.scrollUntilVisible(find.byKey(const Key('notificationsToggle')), 200,
        scrollable: find.byType(Scrollable).first);
    await pumpFor(tester, const Duration(milliseconds: 200));
    await tester.tap(find.byKey(const Key('notificationsToggle')));
    await pumpFor(tester, const Duration(milliseconds: 300));
    expect(store.notificationsEnabled, isFalse);
    await tester.tap(find.byKey(const Key('notificationsToggle')));
    await pumpFor(tester, const Duration(milliseconds: 300));
    expect(store.notificationsEnabled, isTrue);
    await tearDownApp(tester);
  });
}
