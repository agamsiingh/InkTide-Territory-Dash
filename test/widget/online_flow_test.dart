import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inktide/app.dart';
import 'package:inktide/game/inktide_game.dart';
import 'package:inktide/game/net/protocol.dart';
import 'package:inktide/services/auth_service.dart';
import 'package:inktide/services/feedback.dart';
import 'package:inktide/services/online_session.dart';
import 'package:inktide/services/progress_store.dart';
import 'package:inktide/services/reminders.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/pin_clock.dart';

const _frame = Duration(milliseconds: 50);

Future<void> pumpFor(WidgetTester tester, Duration total) async {
  for (var t = Duration.zero; t < total; t += _frame) {
    await tester.pump(_frame);
  }
}

class FakeAuth implements AuthService {
  PlayerIdentity? result = const PlayerIdentity(id: 'pg-42', name: 'Zara');
  int calls = 0;
  @override
  Future<PlayerIdentity?> signIn() async {
    calls++;
    return result;
  }
}

/// One scripted connection: answers hello like the real server would.
class FakeConn implements OnlineTransport {
  FakeConn(this.server);
  final FakeServer server;
  final StreamController<Object?> _in = StreamController<Object?>();
  final List<ClientMsg> got = [];

  @override
  Stream<Object?> get frames => _in.stream;

  @override
  void send(String text) {
    final m = decodeClient(text);
    if (m == null) return;
    got.add(m);
    if (m is HelloMsg) {
      scheduleMicrotask(() => _answer(m));
    }
  }

  void _answer(HelloMsg h) {
    if (h.mode == JoinMode.join && h.code != 'BCDF') {
      push(const ErrorMsg('room_not_found', 'No room with that code.'));
      return;
    }
    server.lastHello = h;
    push(WelcomeMsg(
      you: 2,
      code: 'BCDF',
      size: 40,
      owners: Uint8List(40 * 40)..fillRange(0, 25, 1)..fillRange(40 * 20, 40 * 20 + 25, 2),
      slots: [
        const SlotInfo(1, 'Nugget', 'froggy', false),
        SlotInfo(2, h.name, h.skin, true),
        const SlotInfo(3, 'Zoe', 'panda', true),
      ],
    ));
  }

  void push(ServerMsg m) {
    if (!_in.isClosed) _in.add(encodeServer(m));
  }

  void drop() => _in.close();

  @override
  Future<void> close() async {
    if (!_in.isClosed) await _in.close();
  }
}

class FakeServer {
  final List<FakeConn> conns = [];
  HelloMsg? lastHello;
  bool unreachable = false;
  Future<OnlineTransport> open(Uri url) async {
    lastUrl = url;
    if (unreachable) throw Exception('refused');
    final c = FakeConn(this);
    conns.add(c);
    return c;
  }

  Uri? lastUrl;
  FakeConn get conn => conns.last;
}

Future<ProgressStore> launch(
  WidgetTester tester,
  FakeServer server,
  FakeAuth auth, {
  Map<String, Object> prefs = const {},
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(<String, Object>{'tutorialSeen': true, ...prefs});
  final store = await ProgressStore.open();
  await tester.pumpWidget(InkTideApp(
    store: store,
    skipSplash: true,
    reminderBackend: NoopReminderBackend(),
    authService: auth,
    transport: server.open,
  ));
  await pumpFor(tester, const Duration(milliseconds: 800));
  return store;
}

Future<void> tapKey(WidgetTester tester, String key, {Duration settle = const Duration(milliseconds: 400)}) async {
  final f = find.byKey(Key(key));
  expect(f, findsOneWidget, reason: 'expected one widget with key $key');
  await tester.ensureVisible(f);
  await tester.pump(_frame);
  await tester.tap(f);
  await pumpFor(tester, settle);
}

Future<void> openOnline(WidgetTester tester) async {
  await tapKey(tester, 'onlineButton', settle: const Duration(milliseconds: 900));
  expect(find.byKey(const Key('onlineScreen')), findsOneWidget);
}

Future<void> enter(WidgetTester tester, String key, String text) async {
  final f = find.byKey(Key(key));
  await tester.ensureVisible(f);
  await tester.pump(_frame);
  await tester.enterText(f, text);
  await tester.pump(_frame);
}

Future<void> tearDownApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(_frame);
}

void main() {
  setUp(() {
    GameFeedback.enabled = false;
    InkTideGame.current = null;
    pinClockAwayFromDeals();
  });
  tearDown(unpinClock);

  group('lobby', () {
    testWidgets('the menu has an online button that opens the lobby', (tester) async {
      await launch(tester, FakeServer(), FakeAuth());
      await openOnline(tester);
      expect(find.text('PLAY ONLINE'), findsOneWidget);
      expect(find.byKey(const Key('quickPlayButton')), findsOneWidget);
      expect(find.byKey(const Key('createRoomButton')), findsOneWidget);
      expect(find.byKey(const Key('joinRoomButton')), findsOneWidget);
      expect(find.byKey(const Key('signInButton')), findsOneWidget);
      await tearDownApp(tester);
    });

    testWidgets('without a server address the player is asked for one, and a nickname is required', (tester) async {
      final server = FakeServer();
      await launch(tester, server, FakeAuth());
      await openOnline(tester);
      expect(find.byKey(const Key('serverField')), findsOneWidget, reason: 'no build-time default configured');
      await tapKey(tester, 'quickPlayButton');
      expect(find.text('Pick a nickname with at least 2 characters.'), findsOneWidget);
      await enter(tester, 'nicknameField', 'Zed');
      await tapKey(tester, 'quickPlayButton');
      expect(find.textContaining('Enter the server address'), findsOneWidget);
      expect(server.conns, isEmpty, reason: 'nothing was dialled');
      await enter(tester, 'serverField', 'not a url');
      await tapKey(tester, 'quickPlayButton');
      expect(find.textContaining('Enter the server address'), findsOneWidget);
      await tearDownApp(tester);
    });

    testWidgets('quick play joins, saves the nickname and server, and opens the live arena', (tester) async {
      final server = FakeServer();
      final store = await launch(tester, server, FakeAuth());
      await openOnline(tester);
      await enter(tester, 'nicknameField', 'Zed');
      await enter(tester, 'serverField', '192.168.1.5:8080');
      await tapKey(tester, 'quickPlayButton', settle: const Duration(milliseconds: 1500));
      expect(server.lastUrl.toString(), 'ws://192.168.1.5:8080');
      expect(server.lastHello!.name, 'Zed');
      expect(server.lastHello!.mode, JoinMode.quick);
      expect(server.lastHello!.playerId, startsWith('g-'), reason: 'guest id');
      expect(store.onlineName, 'Zed');
      expect(store.serverUrl, '192.168.1.5:8080');
      expect(find.byKey(const Key('pauseButton')), findsOneWidget, reason: 'the match screen is up');
      expect(find.byKey(const Key('onlineChip')), findsOneWidget);
      expect(find.textContaining('BCDF'), findsWidgets);
      expect(find.byKey(const Key('countdown')), findsNothing);
      await tearDownApp(tester);
    });

    testWidgets('create room and join by code send the right messages; bad codes show an error', (tester) async {
      final server = FakeServer();
      await launch(tester, server, FakeAuth(), prefs: {'serverUrl': '10.0.0.7:9000', 'onlineName': 'Zed'});
      await openOnline(tester);
      expect(find.byKey(const Key('serverField')), findsNothing, reason: 'saved address is not shown');
      expect(find.textContaining('10.0.0.7:9000'), findsOneWidget);

      await enter(tester, 'joinCodeField', 'zz');
      await tapKey(tester, 'joinRoomButton');
      expect(find.text('Room codes are 4 letters, like BCDF.'), findsOneWidget);
      expect(server.conns, isEmpty);

      await enter(tester, 'joinCodeField', 'wxyz');
      await tapKey(tester, 'joinRoomButton', settle: const Duration(milliseconds: 800));
      expect(server.conn.got.whereType<HelloMsg>().single.code, 'WXYZ', reason: 'upper-cased');
      expect(find.text('No room with that code. Check the letters and try again.'), findsOneWidget);
      expect(find.byKey(const Key('pauseButton')), findsNothing, reason: 'stayed in the lobby');

      await enter(tester, 'joinCodeField', 'bcdf');
      await tapKey(tester, 'joinRoomButton', settle: const Duration(milliseconds: 1500));
      expect(find.byKey(const Key('pauseButton')), findsOneWidget);
      await tearDownApp(tester);
    });

    testWidgets('an unreachable server explains itself and lets the player retry', (tester) async {
      final server = FakeServer()..unreachable = true;
      await launch(tester, server, FakeAuth(), prefs: {'serverUrl': 'wss://nope.example', 'onlineName': 'Zed'});
      await openOnline(tester);
      await tapKey(tester, 'quickPlayButton', settle: const Duration(milliseconds: 600));
      expect(find.byKey(const Key('onlineError')), findsOneWidget);
      expect(find.textContaining("Can't reach the server"), findsOneWidget);
      expect(find.byKey(const Key('onlineBusy')), findsNothing);
      server.unreachable = false;
      await tapKey(tester, 'quickPlayButton', settle: const Duration(milliseconds: 1500));
      expect(find.byKey(const Key('pauseButton')), findsOneWidget);
      await tearDownApp(tester);
    });

    testWidgets('Play Games sign-in: success shows the name and sends the Play Games id; failure falls back to guest', (tester) async {
      final auth = FakeAuth();
      final server = FakeServer();
      final store = await launch(tester, server, auth, prefs: {'serverUrl': 'x.example:1'});
      await openOnline(tester);
      auth.result = null;
      await tapKey(tester, 'signInButton');
      expect(find.textContaining('sign-in is not available'), findsOneWidget);
      expect(find.byKey(const Key('signInButton')), findsOneWidget);
      expect(store.playGamesId, isEmpty);

      auth.result = const PlayerIdentity(id: 'pg-42', name: 'Zara');
      await tapKey(tester, 'signInButton');
      expect(auth.calls, 2);
      expect(find.byKey(const Key('playGamesStatus')), findsOneWidget);
      expect(find.textContaining('Zara'), findsWidgets);
      expect(store.playGamesId, 'pg-42');
      expect(find.byKey(const Key('signInButton')), findsNothing);

      await tapKey(tester, 'quickPlayButton', settle: const Duration(milliseconds: 1500));
      expect(server.lastHello!.playerId, 'pg-42');
      expect(server.lastHello!.name, 'Zara', reason: 'nickname defaults to the Play Games name');
      await tearDownApp(tester);
    });
  });

  group('in the match', () {
    Future<(FakeServer, ProgressStore)> intoMatch(WidgetTester tester) async {
      final server = FakeServer();
      final store = await launch(tester, server, FakeAuth(), prefs: {'serverUrl': 'x.example:1', 'onlineName': 'Zed'});
      await openOnline(tester);
      await tapKey(tester, 'quickPlayButton', settle: const Duration(milliseconds: 1500));
      expect(find.byKey(const Key('pauseButton')), findsOneWidget);
      return (server, store);
    }

    testWidgets('steering is streamed to the server', (tester) async {
      final (server, _) = await intoMatch(tester);
      final surface = find.byKey(const Key('gameSurface'));
      final g = tester.getCenter(surface);
      final gesture = await tester.startGesture(g);
      // A finger sends many small moves, not one jump.
      for (var i = 0; i < 8; i++) {
        await gesture.moveBy(const Offset(10, 0));
        await tester.pump(_frame);
      }
      await pumpFor(tester, const Duration(milliseconds: 300));
      await gesture.up();
      await pumpFor(tester, const Duration(milliseconds: 300));
      final steers = server.conn.got.whereType<SteerMsg>().toList();
      expect(steers, isNotEmpty);
      expect(steers.last.angle, closeTo(0, 0.3), reason: 'dragged to the right');
      await tearDownApp(tester);
    });

    testWidgets('the server\'s snapshots move other players and show the room chip count', (tester) async {
      final (server, _) = await intoMatch(tester);
      server.conn.push(SnapshotMsg(1, const [
        PlayerState(1, 10, 10, 0, true, 0, []),
        PlayerState(2, 20, 25, 0, true, 0, []),
        PlayerState(3, 30, 30, 0, true, 2, [30, 30, 31, 30, 32, 30]),
      ], [for (var i = 0; i < 30; i++) ...[600 + i, 3]], const []));
      await pumpFor(tester, const Duration(milliseconds: 400));
      final g = InkTideGame.current!;
      expect(g.sim.byId(3)!.trailPoints.length, 6);
      expect(g.sim.arena.counts[3], 30);
      expect(g.hud.value.online, isTrue);
      expect(g.hud.value.roomCode, 'BCDF');
      expect(g.hud.value.players, 3);
      expect(g.hud.value.kills, 0);
      await tearDownApp(tester);
    });

    testWidgets('the camera follows the local player, wherever the server puts them', (tester) async {
      final (server, _) = await intoMatch(tester);
      final g = InkTideGame.current!;
      // Before any snapshot we are at the origin: the camera must not stay there.
      server.conn.push(const SnapshotMsg(1, [PlayerState(2, 30, 12, 0, true, 0, [])], [], []));
      await pumpFor(tester, const Duration(milliseconds: 1500));
      var cam = g.camera.viewfinder.position;
      expect(cam.x, closeTo(30 * 32, 80), reason: 'camera x follows slot 2');
      expect(cam.y, closeTo(12 * 32, 80), reason: 'camera y follows slot 2');
      server.conn.push(const SnapshotMsg(2, [PlayerState(2, 10, 50, 1.57, true, 0, [])], [], []));
      await pumpFor(tester, const Duration(milliseconds: 1500));
      cam = g.camera.viewfinder.position;
      expect(cam.x, closeTo(10 * 32, 80));
      expect(cam.y, closeTo(50 * 32, 90));
      await tearDownApp(tester);
    });

    testWidgets('on a slow device (5 fps) the camera still keeps up with a fast-moving player', (tester) async {
      final (server, _) = await intoMatch(tester);
      final g = InkTideGame.current!;
      server.conn.push(const SnapshotMsg(1, [PlayerState(2, 12, 40, 0, true, 0, [])], [], []));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));
      // First position from the server: the camera jumps straight there.
      expect(g.camera.viewfinder.position.x, closeTo(12 * 32, 60));
      expect(g.camera.viewfinder.position.y, closeTo(40 * 32, 60));
      // The player then races across at 6.3 cells/s while frames arrive every 200 ms.
      var x = 12.0;
      for (var i = 0; i < 20; i++) {
        x += 6.3 * 0.2;
        server.conn.push(SnapshotMsg(2 + i, [PlayerState(2, x, 40, 0, true, 0, const [])], const [], const []));
        await tester.pump(const Duration(milliseconds: 200));
      }
      final lagCells = (x * 32 - g.camera.viewfinder.position.x) / 32;
      expect(lagCells, lessThan(1.5), reason: 'camera is ${lagCells.toStringAsFixed(1)} cells behind the player');
      await tearDownApp(tester);
    });

    testWidgets('the local player is actually drawn at the centre of the screen', (tester) async {
      final (server, _) = await intoMatch(tester);
      final g = InkTideGame.current!;
      server.conn.push(SnapshotMsg(1, const [
        PlayerState(2, 30, 25, 0, true, 0, [27.0, 25.5, 28.0, 25.5, 29.0, 25.5, 30.0, 25.5]),
        PlayerState(3, 36, 25, 0, true, 0, []),
      ], [for (var y = 22; y < 29; y++) for (var x = 27; x < 33; x++) ...[y * 40 + x, 2]], const []));
      await pumpFor(tester, const Duration(milliseconds: 1500));
      final rec = ui.PictureRecorder();
      g.render(Canvas(rec));
      final pic = rec.endRecording();
      final w = g.size.x.round(), h = g.size.y.round();
      final img = await tester.runAsync(() => pic.toImage(w, h));
      final data = (await tester.runAsync(() => img!.toByteData()))!;
      // Count dark outline pixels (the character outline is near-black navy) around the centre.
      var dark = 0;
      final cx = w ~/ 2, cy = h ~/ 2;
      for (var y = cy - 45; y < cy + 45; y++) {
        for (var x = cx - 45; x < cx + 45; x++) {
          final i = (y * w + x) * 4;
          final r = data.getUint8(i), gr = data.getUint8(i + 1), b = data.getUint8(i + 2), a = data.getUint8(i + 3);
          if (a > 200 && r < 70 && gr < 70 && b < 110) dark++;
        }
      }
      expect(dark, greaterThan(80), reason: 'a character outline should be drawn at the centre (found $dark dark pixels)');
      await tearDownApp(tester);
    });

    testWidgets('the round timer shows in the chip and a round-over banner announces the winner', (tester) async {
      final (server, _) = await intoMatch(tester);
      server.conn.push(const SnapshotMsg(1, [PlayerState(2, 20, 25, 0, true, 0, [])], [], [], roundLeft: 125));
      await pumpFor(tester, const Duration(milliseconds: 400));
      expect(find.textContaining('2:05'), findsOneWidget);
      server.conn.push(const RoundMsg(
        winnerSlot: 3,
        winnerName: 'Zoe',
        percent: 51.4,
        top: [Score('Zoe', 51.4), Score('Zed', 22), Score('Nugget', 9)],
      ));
      await pumpFor(tester, const Duration(milliseconds: 700));
      expect(find.byKey(const Key('roundBanner')), findsOneWidget);
      expect(find.text('ROUND OVER!'), findsOneWidget);
      expect(find.textContaining('Zoe took 51% of the map'), findsOneWidget);
      expect(find.text('2nd'), findsOneWidget);
      // It goes away on its own after a few seconds.
      for (var i = 0; i < 16; i++) {
        server.conn.push(SnapshotMsg(2 + i, const [PlayerState(2, 20, 25, 0, true, 0, [])], const [], const []));
        await pumpFor(tester, const Duration(milliseconds: 500));
      }
      expect(find.byKey(const Key('roundBanner')), findsNothing);
      await tearDownApp(tester);
    });

    testWidgets('winning a round says so and pays a bonus when you leave', (tester) async {
      final (server, store) = await intoMatch(tester);
      server.conn.push(const SnapshotMsg(1, [PlayerState(2, 20, 25, 0, true, 0, [])], [], [], roundLeft: 50));
      await pumpFor(tester, const Duration(milliseconds: 300));
      server.conn.push(const RoundMsg(winnerSlot: 2, winnerName: 'Zed', percent: 55, top: [Score('Zed', 55)]));
      await pumpFor(tester, const Duration(milliseconds: 700));
      expect(find.text('YOU WON THE ROUND!'), findsOneWidget);
      final coins0 = store.coins;
      await tapKey(tester, 'pauseButton');
      await tapKey(tester, 'leaveOnlineButton', settle: const Duration(milliseconds: 900));
      expect(find.byKey(const Key('resultsPanel')), findsOneWidget);
      expect(store.coins - coins0, greaterThanOrEqualTo(100), reason: '100 coins for the round win');
      await tearDownApp(tester);
    });

    testWidgets('being splatted shows a respawn banner that disappears when you are back', (tester) async {
      final (server, _) = await intoMatch(tester);
      server.conn.push(const SnapshotMsg(1, [PlayerState(2, 20, 25, 0, false, 0, [])], [], [NetEvent('d', 2, 3, 0, 20, 25)]));
      await pumpFor(tester, const Duration(milliseconds: 700));
      expect(find.byKey(const Key('respawnBanner')), findsOneWidget);
      expect(find.text('SPLATTED!'), findsOneWidget);
      server.conn.push(const SnapshotMsg(2, [PlayerState(2, 8, 8, 0, true, 0, [])], [], [NetEvent('s', 2, 0, 0, 0, 0)]));
      await pumpFor(tester, const Duration(milliseconds: 700));
      expect(find.byKey(const Key('respawnBanner')), findsNothing);
      await tearDownApp(tester);
    });

    testWidgets('pause opens a Leave menu without freezing the match; leaving pays out and shows results', (tester) async {
      final (server, store) = await intoMatch(tester);
      server.conn.push(const SnapshotMsg(1, [PlayerState(2, 20, 25, 0, true, 3, [])], [], []));
      await pumpFor(tester, const Duration(milliseconds: 300));
      final coins0 = store.coins, games0 = store.gamesPlayed;
      await tapKey(tester, 'pauseButton');
      expect(find.byKey(const Key('onlineMenu')), findsOneWidget);
      expect(find.textContaining('BCDF'), findsWidgets);
      expect(InkTideGame.current!.paused, isFalse, reason: 'the world keeps running online');
      await tapKey(tester, 'resumeButton');
      expect(find.byKey(const Key('onlineMenu')), findsNothing);
      await tapKey(tester, 'pauseButton');
      await tapKey(tester, 'leaveOnlineButton', settle: const Duration(milliseconds: 900));
      expect(server.conn.got.last, isA<LeaveMsg>());
      expect(find.byKey(const Key('resultsPanel')), findsOneWidget);
      expect(find.text('GOOD FIGHT!'), findsOneWidget);
      expect(find.text('PLAY AGAIN'), findsOneWidget);
      expect(find.byKey(const Key('nextLevelButton')), findsNothing);
      expect(store.gamesPlayed, games0 + 1);
      expect(store.coins, greaterThan(coins0), reason: '3 kills earn coins');
      expect(store.wins, 0, reason: 'online matches do not count as campaign wins');
      // Play again goes back to the lobby.
      await tapKey(tester, 'retryButton');
      expect(find.byKey(const Key('onlineScreen')), findsOneWidget);
      await tearDownApp(tester);
    });

    testWidgets('losing the connection shows a Disconnected card with a way back', (tester) async {
      final (server, _) = await intoMatch(tester);
      server.conn.drop();
      await pumpFor(tester, const Duration(milliseconds: 500));
      expect(find.byKey(const Key('disconnectedPanel')), findsOneWidget);
      expect(find.text('Connection lost.'), findsOneWidget);
      await tapKey(tester, 'disconnectedBack');
      expect(find.byKey(const Key('onlineScreen')), findsOneWidget);
      await tearDownApp(tester);
    });

    testWidgets('backing out of the match leaves the room', (tester) async {
      final (server, _) = await intoMatch(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(_frame);
      expect(server.conn.got.any((m) => m is LeaveMsg), isTrue);
    });
  });
}
