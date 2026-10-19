import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:inktide/game/net/protocol.dart';
import 'package:inktide/game/sim/simulation.dart';
import 'package:inktide/services/online_session.dart';

/// A scripted server: tests push frames in and read what the client sent.
class FakeTransport implements OnlineTransport {
  final StreamController<Object?> _in = StreamController<Object?>();
  final List<String> sent = [];
  bool closed = false;

  @override
  Stream<Object?> get frames => _in.stream;
  @override
  void send(String text) => sent.add(text);
  @override
  Future<void> close() async {
    closed = true;
    if (!_in.isClosed) await _in.close();
  }

  void push(ServerMsg m) => _in.add(encodeServer(m));
  void pushRaw(Object? raw) => _in.add(raw);
  void drop() => _in.close();

  List<ClientMsg> get messages => [for (final s in sent) decodeClient(s)].whereType<ClientMsg>().toList();
}

const hello = HelloMsg(name: 'Me', playerId: 'g1', skin: 'sunny', mode: JoinMode.quick);
final url = Uri.parse('ws://test');

WelcomeMsg welcome({int you = 2, int size = 40, List<SlotInfo>? slots, String code = 'BCDF'}) {
  final owners = Uint8List(size * size);
  // Slot 1 owns a block, slot 2 (us) another.
  for (var i = 0; i < 25; i++) {
    owners[i] = 1;
    owners[size * 20 + i] = 2;
  }
  return WelcomeMsg(
    you: you,
    code: code,
    size: size,
    slots: slots ??
        const [
          SlotInfo(1, 'Nugget', 'froggy', false),
          SlotInfo(2, 'Me', 'sunny', true),
          SlotInfo(3, 'Zoe', 'panda', true),
        ],
    owners: owners,
  );
}

PlayerState ps(int id, double x, double y, {double h = 0, bool alive = true, int kills = 0, List<double> trail = const []}) =>
    PlayerState(id, x, y, h, alive, kills, trail);

Future<(OnlineSession, FakeTransport)> joined({WelcomeMsg? w}) async {
  final t = FakeTransport();
  final s = OnlineSession(factory: (_) async => t);
  final f = s.join(url, hello);
  await Future<void>.delayed(Duration.zero);
  t.push(w ?? welcome());
  await f;
  return (s, t);
}

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 5));

void main() {
  group('joining', () {
    test('sends hello, mirrors the welcome and starts playing', () async {
      final (s, t) = await joined();
      expect((t.messages.first as HelloMsg).name, 'Me');
      expect(s.state, OnlineState.playing);
      expect(s.you, 2);
      expect(s.code, 'BCDF');
      final m = s.mirror!;
      expect(m.arena.width, 40);
      expect(m.arena.counts[1], 25);
      expect(m.arena.counts[2], 25);
      expect(m.human.id, 2, reason: 'the renderer follows our slot');
      expect(m.human.isHuman, isTrue);
      expect(m.byId(1)!.isHuman, isFalse, reason: 'everyone else is drawn like a rival with a name');
      expect(m.byId(3)!.name, 'Zoe');
      expect(m.byId(3)!.skin.id, 'panda');
      expect(s.humanCount, 2);
      expect(s.playerCount, 3);
    });

    test('an error reply (room not found) fails the join with its code', () async {
      final t = FakeTransport();
      final s = OnlineSession(factory: (_) async => t);
      final f = s.join(url, hello);
      final expectation = expectLater(f, throwsA(isA<OnlineException>().having((e) => e.code, 'code', 'room_not_found')));
      await Future<void>.delayed(Duration.zero);
      t.push(const ErrorMsg('room_not_found', 'No room with that code.'));
      await expectation;
      expect(s.state, OnlineState.closed);
    });

    test('a server that cannot be reached fails fast', () async {
      final s = OnlineSession(factory: (_) async => throw Exception('refused'));
      await expectLater(s.join(url, hello), throwsA(isA<OnlineException>().having((e) => e.code, 'code', 'connect_failed')));
      expect(s.state, OnlineState.closed);
    });

    test('a welcome with a bad arena is ignored and never starts the game', () async {
      final t = FakeTransport();
      final s = OnlineSession(factory: (_) async => t);
      final f = s.join(url, hello);
      await Future<void>.delayed(Duration.zero);
      t.pushRaw('{"t":"welcome","v":1,"you":2,"code":"A","size":40,"slots":[],"own":"AAAA"}');
      t.pushRaw('garbage');
      t.pushRaw(null);
      t.pushRaw(5);
      await settle();
      expect(s.state, OnlineState.joining);
      t.push(welcome());
      await f;
      expect(s.state, OnlineState.playing);
    });

    test('closing before the welcome fails the join', () async {
      final t = FakeTransport();
      final s = OnlineSession(factory: (_) async => t);
      final f = s.join(url, hello);
      final expectation = expectLater(f, throwsA(isA<OnlineException>()));
      await Future<void>.delayed(Duration.zero);
      t.drop();
      await expectation;
    });
  });

  group('snapshots', () {
    test('arena deltas are applied and bad ones are skipped', () async {
      final (s, t) = await joined();
      final m = s.mirror!;
      t.push(SnapshotMsg(1, [ps(2, 5, 5)], const [100, 2, 101, 2, 99999, 2, -4, 1, 102, 77], const []));
      await settle();
      expect(m.arena.owner[100], 2);
      expect(m.arena.owner[101], 2);
      expect(m.arena.owner[102], 0, reason: 'owner 77 is not a player');
      expect(m.arena.counts[2], 27);
    });

    test('old and duplicate snapshots are ignored', () async {
      final (s, t) = await joined();
      t.push(SnapshotMsg(5, [ps(2, 10, 10)], const [200, 2], const []));
      t.push(SnapshotMsg(5, [ps(2, 30, 30)], const [201, 2], const []));
      t.push(SnapshotMsg(3, [ps(2, 31, 31)], const [202, 2], const []));
      await settle();
      s.update(1);
      expect(s.me!.x, closeTo(10, 0.01));
      expect(s.mirror!.arena.owner[201], 0);
      expect(s.mirror!.arena.owner[202], 0);
    });

    test('others are smoothed between snapshots; the first snapshot places them exactly', () async {
      final (s, t) = await joined();
      t.push(SnapshotMsg(1, [ps(3, 10, 10)], const [], const []));
      await settle();
      s.update(0.001);
      expect(s.mirror!.byId(3)!.x, closeTo(10, 0.01));
      t.push(SnapshotMsg(2, [ps(3, 12, 10)], const [], const []));
      await settle();
      s.update(0.001);
      final start = s.mirror!.byId(3)!.x;
      expect(start, closeTo(10, 0.2), reason: 'starts from where it was drawn');
      s.update(1 / 30);
      final mid = s.mirror!.byId(3)!.x;
      expect(mid, greaterThan(start));
      expect(mid, lessThan(12));
      s.update(0.5);
      expect(s.mirror!.byId(3)!.x, closeTo(12, 0.001), reason: 'arrives and stops (no overshoot)');
    });

    test('a respawn or big jump snaps instead of sliding across the map', () async {
      final (s, t) = await joined();
      t.push(SnapshotMsg(1, [ps(3, 5, 5)], const [], const []));
      t.push(SnapshotMsg(2, [ps(3, 5, 5, alive: false)], const [], const []));
      t.push(SnapshotMsg(3, [ps(3, 30, 30)], const [], const []));
      await settle();
      expect(s.mirror!.byId(3)!.alive, isTrue);
      expect(s.mirror!.byId(3)!.x, 30, reason: 'respawned here, instantly');
      s.update(0.0001);
      expect(s.mirror!.byId(3)!.x, closeTo(30, 0.1));
    });

    test('trails, kills and alive state follow the server; dead players show no trail', () async {
      final (s, t) = await joined();
      t.push(SnapshotMsg(1, [ps(3, 5, 5, kills: 2, trail: const [1, 1, 2, 2, 3, 3])], const [], const []));
      await settle();
      final z = s.mirror!.byId(3)!;
      expect(z.kills, 2);
      expect(z.trailPoints, [1, 1, 2, 2, 3, 3]);
      expect(z.hasTrail, isTrue);
      t.push(SnapshotMsg(2, [ps(3, 5, 5, alive: false, trail: const [1, 1, 2, 2])], const [], const []));
      await settle();
      expect(z.trailPoints, isEmpty);
      expect(z.hasTrail, isFalse);
    });

    test('events become simulation events for effects, and our deaths are counted', () async {
      final (s, t) = await joined();
      t.push(const SnapshotMsg(1, [], [], [
        NetEvent('c', 3, 12, 0, 4, 5),
        NetEvent('d', 2, 3, 0, 6, 7),
        NetEvent('s', 2, 0, 0, 0, 0),
        NetEvent('d', 9, 1, 99, 0, 0), // invalid cause: dropped
        NetEvent('?', 1, 1, 1, 1, 1),
      ]));
      await settle();
      final ev = s.mirror!.drainEvents();
      expect(ev.length, 3);
      expect((ev[0] as CaptureEvent).cells, 12);
      expect((ev[1] as DeathEvent).victimId, 2);
      expect(ev[2], isA<SpawnEvent>());
      expect(s.deaths, 1);
      expect(s.mirror!.byId(3)!.sinceCapture, 0);
    });

    test('round end: banner data, win counted, kills added up across rounds, timer from snapshots', () async {
      final (s, t) = await joined();
      t.push(SnapshotMsg(1, [ps(2, 10, 10, kills: 3)], const [], const [], roundLeft: 120));
      await settle();
      expect(s.kills, 3);
      expect(s.roundLeft, 120);
      t.push(const RoundMsg(winnerSlot: 2, winnerName: 'Me', percent: 52, top: [Score('Me', 52), Score('Zoe', 20)]));
      await settle();
      final r = s.roundResult.value!;
      expect(r.youWon, isTrue);
      expect(r.winnerName, 'Me');
      expect(s.roundWins, 1);
      expect(s.kills, 3, reason: 'kills from the finished round are kept');
      t.push(SnapshotMsg(2, [ps(2, 8, 8, kills: 0)], const [], const [], roundLeft: 209));
      await settle();
      expect(s.kills, 3);
      t.push(SnapshotMsg(3, [ps(2, 9, 8, kills: 2)], const [], const []));
      await settle();
      expect(s.kills, 5, reason: '3 earlier + 2 now');
      t.push(const RoundMsg(winnerSlot: 1, winnerName: 'Nugget', percent: 50, top: [Score('Nugget', 50)]));
      await settle();
      expect(s.roundResult.value!.youWon, isFalse);
      expect(s.roundWins, 1);
      expect(s.kills, 5);
      for (var i = 0; i < 14; i++) {
        s.update(0.5);
        t.push(SnapshotMsg(10 + i, [ps(2, 9, 8, kills: 0)], const [], const []));
        await settle();
      }
      expect(s.roundResult.value, isNull, reason: 'the banner clears itself');
    });

    test('a round message before the welcome is ignored', () async {
      final t = FakeTransport();
      final s = OnlineSession(factory: (_) async => t);
      final f = s.join(url, hello);
      await Future<void>.delayed(Duration.zero);
      t.push(const RoundMsg(winnerSlot: 1, winnerName: 'X', percent: 50, top: []));
      await settle();
      expect(s.roundResult.value, isNull);
      t.push(welcome());
      await f;
    });

    test('players joining and leaving update the mirror', () async {
      final (s, t) = await joined();
      t.push(const SlotMsg(SlotInfo(4, 'Newbie', 'teddy', true), false));
      await settle();
      expect(s.mirror!.byId(4)!.name, 'Newbie');
      expect(s.humanCount, 3);
      t.push(const SlotMsg(SlotInfo(4, 'Newbie', 'teddy', true), true));
      await settle();
      expect(s.mirror!.byId(4)!.vacant, isTrue);
      expect(s.humanCount, 2);
      // We cannot be removed by a (forged) slot message about ourselves.
      t.push(const SlotMsg(SlotInfo(2, 'Me', 'sunny', true), true));
      await settle();
      expect(s.mirror!.byId(2)!.vacant, isFalse);
    });

    test('a snapshot that arrives before the welcome does nothing', () async {
      final t = FakeTransport();
      final s = OnlineSession(factory: (_) async => t);
      final f = s.join(url, hello);
      await Future<void>.delayed(Duration.zero);
      t.push(SnapshotMsg(1, [ps(2, 1, 1)], const [], const []));
      await settle();
      expect(s.mirror, isNull);
      t.push(welcome());
      await f;
    });
  });

  group('steering and upkeep', () {
    test('steering is queued and sent at a limited rate, only the latest angle', () async {
      final (s, t) = await joined();
      t.sent.clear();
      for (var i = 0; i < 20; i++) {
        s.sendSteer(i * 0.1);
      }
      s.update(0.02);
      expect(t.messages.whereType<SteerMsg>(), isEmpty, reason: 'throttled');
      s.update(0.03);
      final sent = t.messages.whereType<SteerMsg>().toList();
      expect(sent.length, 1);
      expect(sent.single.angle, closeTo(1.9, 0.01));
      s.update(0.05);
      expect(t.messages.whereType<SteerMsg>().length, 1, reason: 'nothing new to send');
      s.sendSteer(double.nan);
      s.update(0.1);
      expect(t.messages.whereType<SteerMsg>().length, 1, reason: 'NaN never leaves the phone');
    });

    test('our arrow turns toward the finger right away', () async {
      final (s, t) = await joined();
      t.push(SnapshotMsg(1, [ps(2, 10, 10, h: 0)], const [], const []));
      await settle();
      s.mirror!.human.desiredHeading = math.pi / 2;
      s.update(0.05);
      expect(s.me!.heading, greaterThan(0.3));
      s.update(0.5);
      expect(s.me!.heading, closeTo(math.pi / 2, 0.01));
    });

    test('pings go out periodically and a pong sets the ping time', () async {
      final (s, t) = await joined();
      t.sent.clear();
      for (var i = 0; i < 9; i++) {
        s.update(0.5);
      }
      final pings = t.messages.whereType<PingMsg>().toList();
      expect(pings, isNotEmpty);
      t.push(PongMsg(DateTime.now().millisecondsSinceEpoch - 40));
      await settle();
      expect(s.pingMs, inInclusiveRange(40, 120));
    });

    test('stats: best territory, time and kills are tracked for the results screen', () async {
      final (s, t) = await joined();
      t.push(SnapshotMsg(1, [ps(2, 10, 10, kills: 3)], [for (var i = 0; i < 60; i++) ...[300 + i, 2]], const []));
      await settle();
      s.update(2);
      expect(s.kills, 3);
      expect(s.seconds, closeTo(2, 0.01));
      expect(s.bestPercent, closeTo((25 + 60) * 100 / 1600, 0.01));
    });

    test('leaving says goodbye and closes; a server that vanishes is a lost connection', () async {
      final (s, t) = await joined();
      await s.leave();
      expect(t.messages.last, isA<LeaveMsg>());
      expect(t.closed, isTrue);
      expect(s.state, OnlineState.closed);
      expect(s.lostReason, isNull, reason: 'leaving on purpose is not an error');

      final (s2, t2) = await joined();
      t2.drop();
      await settle();
      expect(s2.state, OnlineState.closed);
      expect(s2.lostReason?.code, 'connection_lost');
    });

    test('hearing nothing for 8 seconds drops the connection', () async {
      final (s, _) = await joined();
      for (var i = 0; i < 20; i++) {
        s.update(0.5);
      }
      expect(s.state, OnlineState.closed);
      expect(s.lostReason?.code, 'connection_lost');
    });
  });

  test('client messages never exceed the server frame limit', () {
    final big = encodeClient(HelloMsg(name: 'N' * 14, playerId: 'p' * 64, skin: 's' * 32, mode: JoinMode.join, code: 'ABCD'));
    expect(big.length, lessThan(kMaxClientFrame));
    expect(jsonDecode(big), isA<Map>());
  });
}
