import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inktide/app.dart';
import 'package:inktide/services/feedback.dart';
import 'package:inktide/services/progress_store.dart';
import 'package:inktide/services/reminders.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('app boots to the menu', (tester) async {
    GameFeedback.enabled = false;
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(<String, Object>{'tutorialSeen': true});
    final store = await ProgressStore.open();
    await tester.pumpWidget(InkTideApp(store: store, skipSplash: true, reminderBackend: NoopReminderBackend()));
    // The menu animates forever: pump fixed steps instead of pumpAndSettle.
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byKey(const Key('playButton')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
