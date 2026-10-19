import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inktide/app.dart';
import 'package:inktide/game/event.dart';
import 'package:inktide/game/world.dart';
import 'package:inktide/game/world_map.dart';
import 'package:inktide/services/feedback.dart';
import 'package:inktide/services/progress_store.dart';
import 'package:inktide/ui/flags.dart';
import 'package:inktide/ui/screens/world_map_screen.dart';
import 'package:inktide/services/reminders.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _frame = Duration(milliseconds: 50);

Future<void> pumpFor(WidgetTester tester, Duration total) async {
  for (var t = Duration.zero; t < total; t += _frame) {
    await tester.pump(_frame);
  }
}

Future<ProgressStore> launch(WidgetTester tester, {Map<String, Object> prefs = const {}}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(<String, Object>{'tutorialSeen': true, ...prefs});
  final store = await ProgressStore.open();
  await tester.pumpWidget(InkTideApp(store: store, skipSplash: true, reminderBackend: NoopReminderBackend()));
  // Map JSON loads through the asset bundle (real async).
  await tester.runAsync(() => WorldMapData.load());
  await pumpFor(tester, const Duration(milliseconds: 800));
  return store;
}

Future<void> tearDownApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(_frame);
}

void main() {
  setUp(() => GameFeedback.enabled = false);

  group('map data', () {
    late WorldMapData data;
    setUpAll(() {
      data = WorldMapData.parse(File('assets/data/world.json').readAsStringSync());
    });

    test('campaign countries are present, in order, with real outlines', () {
      expect(data.playable.map((c) => c.iso).toList(), kCountries.map((c) => c.iso).toList());
      expect(data.countries.length, greaterThan(150), reason: 'decorative world land');
      for (final c in data.playable) {
        expect(c.bounds.width, greaterThan(5), reason: c.iso);
        expect(c.bounds.height, greaterThan(5), reason: c.iso);
        expect(data.size.contains(c.bounds.center), isTrue, reason: c.iso);
      }
    });

    test('rough geography: Canada north of the US, Brazil south, Japan east of India', () {
      MapCountry c(String iso) => data.playable.firstWhere((x) => x.iso == iso);
      expect(c('CAN').anchor.dy, lessThan(c('USA').anchor.dy));
      expect(c('BRA').anchor.dy, greaterThan(c('MEX').anchor.dy));
      expect(c('JPN').anchor.dx, greaterThan(c('IND').anchor.dx));
      expect(c('AUS').anchor.dy, greaterThan(c('IND').anchor.dy));
    });

    test('hit-testing finds each country at its anchor and nothing in the ocean', () {
      for (final c in data.playable) {
        expect(data.hitTest(c.anchor, slop: 10)?.iso, c.iso, reason: c.iso);
      }
      // Mid Pacific.
      expect(data.hitTest(const Offset(200, 800)), isNull);
    });

    test('every campaign flag paints without errors', () {
      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec);
      for (final c in kCountries) {
        paintFlag(canvas, const Rect.fromLTWH(0, 0, 60, 40), c.iso);
      }
      rec.endRecording().dispose();
    });
  });

  group('world map screen', () {
    testWidgets('opens from the home screen centred on the current country', (tester) async {
      await launch(tester);
      expect(find.byKey(const Key('countryPill')), findsOneWidget);
      expect(find.text('Canada'), findsWidgets);
      await tester.tap(find.byKey(const Key('mapButton')));
      await pumpFor(tester, const Duration(milliseconds: 800));
      expect(find.byKey(const Key('worldMap')), findsOneWidget);
      expect(find.text('Choose a country to fill!'), findsOneWidget);
      expect(find.byKey(const Key('countryName')), findsOneWidget);
      expect(find.byKey(const Key('mapPlayButton')), findsOneWidget);
      await tearDownApp(tester);
    });

    testWidgets('tapping a locked country shows its unlock requirement', (tester) async {
      await launch(tester);
      await tester.tap(find.byKey(const Key('mapButton')));
      await pumpFor(tester, const Duration(milliseconds: 800));
      final state = tester.state<WorldMapScreenState>(find.byType(WorldMapScreen));
      final usa = state.data!.playable[1];
      state.tapAt(usa.anchor);
      await pumpFor(tester, const Duration(milliseconds: 700));
      expect(state.selected, 1);
      expect(find.byKey(const Key('lockedRequirement')), findsOneWidget);
      expect(find.text('Fill Canada to unlock'), findsOneWidget);
      expect(find.byKey(const Key('mapPlayButton')), findsNothing);
      await tearDownApp(tester);
    });

    testWidgets('an unlocked country can be selected and played', (tester) async {
      final store = await launch(tester, prefs: {'countryProgress': ['100', '40']});
      expect(store.isCountryUnlocked(1), isTrue);
      await tester.tap(find.byKey(const Key('mapButton')));
      await pumpFor(tester, const Duration(milliseconds: 800));
      final state = tester.state<WorldMapScreenState>(find.byType(WorldMapScreen));
      state.tapAt(state.data!.playable[1].anchor);
      await pumpFor(tester, const Duration(milliseconds: 700));
      expect(find.text('United States'), findsWidgets);
      expect(find.text('40% filled'), findsOneWidget);
      await tester.tap(find.byKey(const Key('mapPlayButton')));
      await pumpFor(tester, const Duration(milliseconds: 900));
      expect(store.selectedCountry, 1);
      expect(find.byKey(const Key('pauseButton')), findsOneWidget, reason: 'the match started');
      await tearDownApp(tester);
    });
  });

  group('continents & celebration', () {
    testWidgets('continent progress chip, next pin and a one-time completion celebration', (tester) async {
      final store = await launch(tester, prefs: {'countryProgress': ['100']});
      await tester.tap(find.byKey(const Key('mapButton')));
      await pumpFor(tester, const Duration(milliseconds: 900));
      expect(find.byKey(const Key('continentProgress')), findsOneWidget);
      expect(find.text('Unlock SOUTH AMERICA'), findsOneWidget);
      expect(find.text('1/3'), findsOneWidget);
      expect(find.byKey(const Key('mapCelebration')), findsOneWidget);
      expect(find.byKey(const Key('nextPin')), findsOneWidget, reason: 'Mexico is next');
      await pumpFor(tester, const Duration(milliseconds: 2600));
      expect(find.byKey(const Key('mapCelebration')), findsNothing);
      expect(store.celebratedCountries, {'CAN'});
      await tester.tap(find.byKey(const Key('backButton')));
      await pumpFor(tester, const Duration(milliseconds: 600));
      await tester.tap(find.byKey(const Key('mapButton')));
      await pumpFor(tester, const Duration(milliseconds: 900));
      expect(find.byKey(const Key('mapCelebration')), findsNothing, reason: 'celebrated once');
      await tearDownApp(tester);
    });
  });

  group('event screen', () {
    testWidgets('claimable milestone can be claimed once and shows a reward card', (tester) async {
      final now = DateTime.now();
      final store = await launch(tester, prefs: {'eventId': eventAt(now).id, 'eventTokens': 30});
      final coins0 = store.coins;
      await tester.tap(find.byKey(const Key('eventButton')));
      await pumpFor(tester, const Duration(milliseconds: 800));
      expect(find.text('COLLECT'), findsOneWidget);
      expect(find.byKey(const Key('eventCountdown')), findsOneWidget);
      expect(find.text('CLAIM!'), findsNWidgets(2), reason: '5 and 25 reached with 30 tokens');
      await tester.tap(find.byKey(const Key('milestone_0')));
      await pumpFor(tester, const Duration(milliseconds: 600));
      expect(find.byKey(const Key('rewardCard')), findsOneWidget);
      expect(store.coins, coins0 + kMilestones[0].amount);
      await tester.tap(find.byKey(const Key('rewardOk')));
      await pumpFor(tester, const Duration(milliseconds: 400));
      expect(find.text('Claimed'), findsOneWidget);
      // Tapping a claimed tile does nothing.
      await tester.tap(find.byKey(const Key('milestone_0')));
      await pumpFor(tester, const Duration(milliseconds: 400));
      expect(find.byKey(const Key('rewardCard')), findsNothing);
      expect(store.coins, coins0 + kMilestones[0].amount);
      await tester.tap(find.byKey(const Key('closeEvent')));
      await pumpFor(tester, const Duration(milliseconds: 500));
      await tearDownApp(tester);
    });
  });
}
