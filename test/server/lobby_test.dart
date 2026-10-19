// ignore_for_file: avoid_relative_lib_imports
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

// The server and these tests share the game sources through relative imports.
import '../../lib/game/net/protocol.dart';
import '../../lib/game/sim/simulation.dart' show DeathCause;
import '../../server/lib/lobby.dart';

class FakeConn implements ClientConn {
  final List<ServerMsg> got = [];
  bool closed = false;

  @override
  void send(String text) {
    final m = decodeServer(text);
    if (m != null) got.add(m);
  }

  @override
  void close() => closed = true;

  T? last<T extends ServerMsg>() => got.whereType<T>().isEmpty ? null : got.whereType<T>().last;
  List<T> all<T extends ServerMsg>() => got.whereType<T>().toList();
}

String hello({String name = 'Ann', String id = 'g1', String skin = 'sunny', JoinMode mode = JoinMode.quick, String? code}) =>
    encodeClient(HelloMsg(name: name, playerId: id, skin: skin, mode: mode, code: code));

FakeConn join(Lobby lobby, {String name = 'Ann', String id = 'g1', JoinMode mode = JoinMode.quick, String? code}) {
  final c = FakeConn();
  lobby.connect(c);
  lobby.onFrame(c, hello(name: name, id: id, mode: mode, code: code));
  return c;
}

void run(Lobby lobby, double seconds) {
  for (var t = 0.0; t < seconds; t += 1 / 30) {
    lobby.tick(1 / 30);
  }
}

void main() {
  group('protocol', () {
    test('client messages round-trip', () {
      final h = decodeClient(hello(name: 'Zed', skin: 'panda', mode: JoinMode.join, code: 'ABCD')) as HelloMsg;
      expect((h.name, h.skin, h.mode, h.code), ('Zed', 'panda', JoinMode.join, 'ABCD'));
      expect((decodeClient(encodeClient(const SteerMsg(1.234))) as SteerMsg).angle, closeTo(1.23, 0.01));
      expect(decodeClient(encodeClient(const LeaveMsg())), isA<LeaveMsg>());
      expect((decodeClient(encodeClient(const PingMsg(42))) as PingMsg).stamp, 42);
    });

    test('garbage from a client is rejected, never thrown', () {
      for (final bad in [
        null,
        42,
        '',
        'not json',
        '[]',
        '{}',
        '{"t":"hello"}',
        '{"t":"hello","v":99,"name":"a","id":"b","skin":"c","mode":"quick"}',
        '{"t":"hello","v":1,"name":1,"id":"b","skin":"c","mode":"quick"}',
        '{"t":"hello","v":1,"name":"a","id":"","skin":"c","mode":"quick"}',
        '{"t":"hello","v":1,"name":"a","id":"b","skin":"c","mode":"nope"}',
        '{"t":"steer","a":"x"}',
        '{"t":"steer","a":null}',
        '{"t":"ping","s":"x"}',
        '{"t":"warp"}',
        'x' * 5000,
      ]) {
        expect(decodeClient(bad), isNull, reason: '$bad');
      }
    });

    test('server messages round-trip', () {
      const snap = SnapshotMsg(7, [
        PlayerState(2, 10.256, 20.5, 1.5, true, 3, [1.0, 2.0, 3.5, 4.5], reset: true),
      ], [5, 2, 6, 2], [NetEvent('d', 2, 1, 0, 3.0, 4.0)]);
      final back = decodeServer(encodeServer(snap)) as SnapshotMsg;
      expect(back.seq, 7);
      expect(back.players.single.x, closeTo(10.26, 0.01));
      expect(back.players.single.trail, [1.0, 2.0, 3.5, 4.5]);
      expect(back.players.single.reset, isTrue);
      expect(back.changes, [5, 2, 6, 2]);
      expect(back.events.single.kind, 'd');
      expect(decodeServer('{"t":"snap"}'), isNull);
      expect(decodeServer('{"t":"welcome","v":1,"you":1,"code":"A","size":8,"slots":[],"own":"AAAA"}'), isNull,
          reason: 'wrong arena byte count');
    });

    test('round messages round-trip and bad ones are rejected', () {
      const m = RoundMsg(winnerSlot: 3, winnerName: 'Zed', percent: 51.234, top: [Score('Zed', 51.2), Score('Ann', 20)]);
      final back = decodeServer(encodeServer(m)) as RoundMsg;
      expect((back.winnerSlot, back.winnerName), (3, 'Zed'));
      expect(back.percent, closeTo(51.23, 0.01));
      expect(back.top.map((s) => s.name), ['Zed', 'Ann']);
      expect(decodeServer('{"t":"round","w":"x","n":"a","p":1,"top":[]}'), isNull);
      expect(decodeServer('{"t":"round","w":1,"n":"a","p":1,"top":[[1,2]]}'), isNull);
      const snap = SnapshotMsg(1, [], [], [], roundLeft: 125);
      expect((decodeServer(encodeServer(snap)) as SnapshotMsg).roundLeft, 125);
    });

    test('slot info validates ranges', () {
      expect(SlotInfo.fromJson({'i': 0, 'n': 'a', 's': 'b', 'h': 1}), isNull);
      expect(SlotInfo.fromJson({'i': 17, 'n': 'a', 's': 'b', 'h': 1}), isNull);
      expect(SlotInfo.fromJson({'i': 3, 'n': 'a', 's': 'b', 'h': 1})!.human, isTrue);
    });
  });

  group('names', () {
    test('are cleaned, trimmed and capped', () {
      expect(sanitizeName('  Ann   Lee  ', 'x'), 'Ann Lee');
      expect(sanitizeName('A<b>c&d', 'x'), 'Abcd');
      expect(sanitizeName('ThisNameIsWayTooLongForTheGame', 'x').length, lessThanOrEqualTo(14));
      expect(sanitizeName('Ann_1.2-3', 'x'), 'Ann_1.2-3');
    });

    test('too short, empty or blocked names become Player###', () {
      for (final bad in ['', 'a', '   ', '###', 'f u c k', 'Sh1t', 'xxNazixx', 'K1LL']) {
        expect(sanitizeName(bad, 'id-77'), matches(RegExp(r'^Player\d{3}$')), reason: bad);
      }
      expect(sanitizeName('', 'id-77'), sanitizeName('', 'id-77'), reason: 'stable per player id');
    });
  });

  group('lobby', () {
    test('quick play seats you, welcomes you with the whole arena and fills seats with bots', () {
      final lobby = Lobby(seed: 1);
      final a = join(lobby);
      final w = a.last<WelcomeMsg>()!;
      expect(w.code, matches(RegExp(r'^[A-Z]{4}$')));
      expect(w.size, 80);
      expect(w.owners.length, 80 * 80);
      expect(w.slots.where((s) => s.human).length, 1);
      expect(w.slots.length, 8, reason: '1 human + 7 bots');
      expect(w.slots.firstWhere((s) => s.id == w.you).name, 'Ann');
      expect(w.owners.where((o) => o == w.you).length, greaterThan(10), reason: 'you start with land');
      expect(lobby.rooms.length, 1);
    });

    test('a second quick player lands in the same room and a bot steps aside', () {
      final lobby = Lobby(seed: 2);
      final a = join(lobby, name: 'Ann', id: 'a');
      final b = join(lobby, name: 'Bo', id: 'b');
      expect(lobby.rooms.length, 1);
      expect(b.last<WelcomeMsg>()!.code, a.last<WelcomeMsg>()!.code);
      final w = b.last<WelcomeMsg>()!;
      expect(w.slots.where((s) => s.human).map((s) => s.name).toSet(), {'Ann', 'Bo'});
      expect(w.slots.length, 8, reason: 'still 8 in the arena');
      // Ann is told about Bo joining.
      expect(a.all<SlotMsg>().any((m) => m.slot.name == 'Bo' && !m.left), isTrue);
      expect(a.all<SlotMsg>().any((m) => m.left && !m.slot.human), isTrue, reason: 'a bot left to make room');
    });

    test('duplicate names get a number', () {
      final lobby = Lobby(seed: 3);
      join(lobby, name: 'Ann', id: 'a');
      final b = join(lobby, name: 'Ann', id: 'b');
      final w = b.last<WelcomeMsg>()!;
      expect(w.slots.where((s) => s.human).map((s) => s.name).toSet(), {'Ann', 'Ann 2'});
    });

    test('the ninth human gets a new public room', () {
      final lobby = Lobby(seed: 4);
      final conns = [for (var i = 0; i < 9; i++) join(lobby, name: 'P$i', id: 'p$i')];
      expect(lobby.rooms.length, 2);
      final codes = conns.map((c) => c.last<WelcomeMsg>()!.code).toSet();
      expect(codes.length, 2);
      expect(lobby.rooms.values.map((r) => r.humanCount).toList()..sort(), [1, 8]);
    });

    test('create makes a private room that others can join by code, but quick play never lands there', () {
      final lobby = Lobby(seed: 5);
      final host = join(lobby, name: 'Host', id: 'h', mode: JoinMode.create);
      final code = host.last<WelcomeMsg>()!.code;
      final quick = join(lobby, name: 'Rando', id: 'r');
      expect(quick.last<WelcomeMsg>()!.code, isNot(code));
      final friend = join(lobby, name: 'Pal', id: 'f', mode: JoinMode.join, code: code.toLowerCase());
      expect(friend.last<WelcomeMsg>()!.code, code, reason: 'codes are case-insensitive');
      expect(friend.last<WelcomeMsg>()!.slots.where((s) => s.human).map((s) => s.name).toSet(), {'Host', 'Pal'});
    });

    test('unknown or full rooms answer with an error and let you try again', () {
      final lobby = Lobby(seed: 6);
      final c = FakeConn();
      lobby.connect(c);
      lobby.onFrame(c, hello(mode: JoinMode.join, code: 'ZZZZ'));
      expect(c.last<ErrorMsg>()!.code, 'room_not_found');
      // Same socket may try again.
      lobby.onFrame(c, hello(mode: JoinMode.create));
      expect(c.last<WelcomeMsg>(), isNotNull);

      final host = join(lobby, name: 'Host', id: 'h', mode: JoinMode.create);
      final code = host.last<WelcomeMsg>()!.code;
      for (var i = 0; i < 7; i++) {
        join(lobby, name: 'F$i', id: 'f$i', mode: JoinMode.join, code: code);
      }
      final late = join(lobby, name: 'Late', id: 'l', mode: JoinMode.join, code: code);
      expect(late.last<ErrorMsg>()!.code, 'room_full');
      expect(late.last<WelcomeMsg>(), isNull);
    });

    test('a second hello on a seated socket is ignored', () {
      final lobby = Lobby(seed: 7);
      final a = join(lobby);
      lobby.onFrame(a, hello(name: 'Hacker', id: 'x', mode: JoinMode.create));
      expect(lobby.rooms.length, 1);
      expect(a.all<WelcomeMsg>().length, 1);
    });

    test('leaving frees the seat, tells the others, and an empty room disappears', () {
      final lobby = Lobby(seed: 8);
      final a = join(lobby, name: 'Ann', id: 'a');
      final b = join(lobby, name: 'Bo', id: 'b');
      lobby.disconnect(b);
      expect(a.all<SlotMsg>().any((m) => m.left && m.slot.name == 'Bo'), isTrue);
      expect(lobby.rooms.values.single.humanCount, 1);
      expect(lobby.rooms.values.single.botCount, 7, reason: 'bots refill the empty seat');
      lobby.onFrame(a, encodeClient(const LeaveMsg()));
      expect(lobby.rooms, isEmpty);
      // The socket can join again after leaving.
      lobby.onFrame(a, hello(name: 'Ann', id: 'a'));
      expect(lobby.rooms.length, 1);
      expect(lobby.humans, 1);
    });

    test('ping answers pong', () {
      final lobby = Lobby(seed: 9);
      final c = FakeConn();
      lobby.connect(c);
      lobby.onFrame(c, encodeClient(const PingMsg(123)));
      expect(c.last<PongMsg>()!.stamp, 123);
    });

    test('garbage frames and frames from unknown sockets are ignored', () {
      final lobby = Lobby(seed: 10);
      final stranger = FakeConn();
      lobby.onFrame(stranger, hello());
      expect(lobby.rooms, isEmpty);
      final c = FakeConn();
      lobby.connect(c);
      for (final bad in ['', 'zzz', '{"t":"steer","a":1}', null, 7, List<int>.filled(3, 0)]) {
        lobby.onFrame(c, bad);
      }
      expect(lobby.rooms, isEmpty);
      expect(c.got, isEmpty);
    });
  });

  group('live play', () {
    test('snapshots stream at half the tick rate with every player and the arena changes', () {
      final lobby = Lobby(seed: 11);
      final a = join(lobby);
      run(lobby, 2);
      final snaps = a.all<SnapshotMsg>();
      expect(snaps.length, inInclusiveRange(28, 32), reason: '~15 per second');
      expect(snaps.map((s) => s.seq).toList(), List.generate(snaps.length, (i) => snaps.first.seq + i));
      expect(snaps.last.players.length, 8);
      expect(snaps.last.players.every((p) => p.x >= 0 && p.x < 80), isTrue);
    });

    test('steering moves your player and only yours', () {
      final lobby = Lobby(seed: 12);
      final a = join(lobby, name: 'Ann', id: 'a');
      final b = join(lobby, name: 'Bo', id: 'b');
      final ida = a.last<WelcomeMsg>()!.you, idb = b.last<WelcomeMsg>()!.you;
      run(lobby, 0.2);
      lobby.onFrame(a, encodeClient(const SteerMsg(0)));
      lobby.onFrame(b, encodeClient(const SteerMsg(math.pi)));
      final before = a.last<SnapshotMsg>()!;
      run(lobby, 1.0);
      final after = a.last<SnapshotMsg>()!;
      PlayerState of(SnapshotMsg s, int id) => s.players.firstWhere((p) => p.id == id);
      expect(of(after, ida).x, greaterThan(of(before, ida).x + 3), reason: 'Ann heads right');
      expect(of(after, idb).x, lessThan(of(before, idb).x - 3), reason: 'Bo heads left');
    });

    test('steering spam is rate-limited', () {
      final lobby = Lobby(seed: 13);
      final a = join(lobby);
      final room = lobby.rooms.values.single;
      final me = room.sim.players.firstWhere((p) => p.isHuman);
      for (var i = 0; i < 500; i++) {
        lobby.onFrame(a, encodeClient(SteerMsg(i * 0.001)));
      }
      // Only the burst allowance (40) got through, the rest were dropped.
      expect(me.desiredHeading, closeTo(39 * 0.001, 0.0011));
    });

    test('a splatted player respawns and keeps playing', () {
      final lobby = Lobby(seed: 14);
      final a = join(lobby);
      final id = a.last<WelcomeMsg>()!.you;
      final room = lobby.rooms.values.single;
      final me = room.sim.byId(id)!;
      room.sim.debugKill(me, 0, DeathCause.border);
      run(lobby, 0.2);
      expect(a.last<SnapshotMsg>()!.players.firstWhere((p) => p.id == id).alive, isFalse);
      expect(a.all<SnapshotMsg>().expand((s) => s.events).any((e) => e.kind == 'd' && e.a == id), isTrue);
      run(lobby, 5);
      expect(a.last<SnapshotMsg>()!.players.firstWhere((p) => p.id == id).alive, isTrue);
      expect(a.all<SnapshotMsg>().expand((s) => s.events).any((e) => e.kind == 's' && e.a == id), isTrue);
    });

    test('a client can rebuild the arena exactly from welcome + deltas', () {
      final lobby = Lobby(seed: 15);
      final a = join(lobby, name: 'Ann', id: 'a');
      final w = a.last<WelcomeMsg>()!;
      final grid = List<int>.of(w.owners);
      run(lobby, 25);
      for (final s in a.all<SnapshotMsg>()) {
        for (var i = 0; i + 1 < s.changes.length; i += 2) {
          grid[s.changes[i]] = s.changes[i + 1];
        }
      }
      final room = lobby.rooms.values.single;
      expect(grid, room.sim.arena.owner.toList(), reason: 'deltas reproduce the server arena');
    });

    test('trail updates are deltas: appended points rebuild every trail exactly, resets restart it', () {
      final lobby = Lobby(seed: 22);
      final a = join(lobby, name: 'Ann', id: 'a');
      final room = lobby.rooms.values.single;
      final trails = <int, List<double>>{};
      void apply(SnapshotMsg s) {
        for (final p in s.players) {
          final t = trails.putIfAbsent(p.id, () => []);
          if (!p.alive) {
            t.clear();
          } else {
            if (p.reset) t.clear();
            t.addAll(p.trail);
          }
        }
      }

      var seen = 0, resets = 0, appends = 0;
      for (var step = 0; step < 900; step++) {
        if (step % 20 == 0) lobby.onFrame(a, encodeClient(SteerMsg((step * 0.37) % 6.28)));
        lobby.tick(1 / 30);
        for (final s in a.all<SnapshotMsg>().skip(seen)) {
          apply(s);
          resets += s.players.where((p) => p.reset && p.trail.isNotEmpty).length;
          appends += s.players.where((p) => !p.reset && p.trail.isNotEmpty).length;
        }
        seen = a.all<SnapshotMsg>().length;
        // After each snapshot the client copy equals the server's trails (within 0.05 cell: wire rounding).
        if (step % 2 == 1) {
          for (final p in room.sim.players.where((p) => !p.vacant)) {
            final mine = trails[p.id] ?? [];
            final real = p.alive ? p.trailPoints : <double>[];
            expect(mine.length, real.length, reason: 'step $step slot ${p.id}');
            for (var i = 0; i < real.length; i++) {
              expect((mine[i] - real[i]).abs(), lessThan(0.06));
            }
          }
        }
      }
      expect(appends, greaterThan(resets), reason: 'mostly cheap appends, not full resends');
      expect(resets, greaterThan(0));
    });

    test('a player joining mid-match gets everyone trails in full once', () {
      final lobby = Lobby(seed: 23);
      final a = join(lobby, name: 'Ann', id: 'a');
      run(lobby, 12);
      final room = lobby.rooms.values.single;
      final withTrail = room.sim.players.where((p) => p.alive && p.trailPoints.length >= 4).map((p) => p.id).toSet();
      expect(withTrail, isNotEmpty, reason: 'someone is out on a trail');
      final b = join(lobby, name: 'Bo', id: 'b');
      lobby.tick(1 / 30);
      lobby.tick(1 / 30);
      final first = b.all<SnapshotMsg>().first;
      for (final id in withTrail.where((id) => room.sim.byId(id)!.alive && !room.sim.byId(id)!.vacant)) {
        final ps = first.players.where((p) => p.id == id);
        if (ps.isEmpty) continue;
        expect(ps.single.reset, isTrue, reason: 'slot $id sent in full to the newcomer');
      }
      expect(a.all<SnapshotMsg>(), isNotEmpty);
    });

    test('bandwidth stays small: well under 20 KB/s per player in a full 8-human room', () {
      final lobby = Lobby(seed: 24);
      final rng = math.Random(9);
      final conns = [for (var i = 0; i < 8; i++) join(lobby, name: 'P$i', id: 'p$i')];
      var bytes = 0;
      final sizes = <int>[];
      const seconds = 30;
      for (var step = 0; step < seconds * 30; step++) {
        if (step % 6 == 0) {
          for (final c in conns) {
            if (rng.nextDouble() < 0.3) lobby.onFrame(c, encodeClient(SteerMsg(rng.nextDouble() * 6.28)));
          }
        }
        final before = conns.first.got.length;
        lobby.tick(1 / 30);
        for (final m in conns.first.got.skip(before)) {
          if (m is SnapshotMsg) {
            final n = encodeServer(m).length;
            bytes += n;
            sizes.add(n);
          }
        }
      }
      final perSecond = bytes / seconds;
      expect(perSecond, lessThan(20 * 1024), reason: '${(perSecond / 1024).toStringAsFixed(1)} KB/s');
      sizes.sort();
      expect(sizes[(sizes.length * 0.99).floor()], lessThan(12 * 1024), reason: 'even the biggest snapshots are small');
    });

    test('a round ends on time: winner announced to everyone, arena wiped, everyone back in', () {
      final lobby = Lobby(seed: 30, config: const ServerConfig(roundSeconds: 6, winPercent: 90));
      final a = join(lobby, name: 'Ann', id: 'a');
      final b = join(lobby, name: 'Bo', id: 'b');
      final room = lobby.rooms.values.single;
      run(lobby, 5.5);
      expect(a.all<RoundMsg>(), isEmpty, reason: 'not yet');
      final left = a.last<SnapshotMsg>()!.roundLeft;
      expect(left, inInclusiveRange(1, 2));
      run(lobby, 1.5);
      final ra = a.all<RoundMsg>(), rb = b.all<RoundMsg>();
      expect(ra.length, 1);
      expect(rb.length, 1, reason: 'everybody hears about it');
      final r = ra.single;
      expect(r.top.length, 3);
      expect(r.top.first.percent, closeTo(r.percent, 0.01));
      expect(r.top[0].percent, greaterThanOrEqualTo(r.top[1].percent));
      expect(r.top[1].percent, greaterThanOrEqualTo(r.top[2].percent));
      expect(r.winnerName, isNotEmpty);
      expect(room.roundsPlayed, 1);
      final cells = room.sim.arena.cellCount;
      var owned = 0;
      for (final p in room.sim.players.where((p) => !p.vacant)) {
        expect(p.alive, isTrue);
        expect(p.kills, 0);
        owned += room.sim.arena.counts[p.id];
      }
      expect(owned / cells * 100, lessThan(15), reason: 'a wiped arena');
      expect(room.roundLeft, greaterThan(4));
    });

    test('a round ends early when someone owns half the map', () {
      final lobby = Lobby(seed: 31);
      final a = join(lobby, name: 'Ann', id: 'a');
      final room = lobby.rooms.values.single;
      final me = room.sim.byId(a.last<WelcomeMsg>()!.you)!;
      final cells = room.sim.arena.cellCount;
      for (var i = 0; i < cells * 0.52; i++) {
        room.sim.arena.setOwner(i, me.id);
      }
      run(lobby, 0.2);
      final r = a.last<RoundMsg>()!;
      expect(r.winnerSlot, me.id);
      expect(r.winnerName, 'Ann');
      expect(r.percent, greaterThanOrEqualTo(50));
      expect(room.roundLeft, greaterThan(200), reason: 'fresh 3.5 minute round');
    });

    test('clients stay in sync with the server across round resets', () {
      final lobby = Lobby(seed: 32, config: const ServerConfig(roundSeconds: 8, winPercent: 90));
      final a = join(lobby, name: 'Ann', id: 'a');
      final grid = List<int>.of(a.last<WelcomeMsg>()!.owners);
      run(lobby, 40);
      expect(a.all<RoundMsg>().length, greaterThanOrEqualTo(4));
      for (final s in a.all<SnapshotMsg>()) {
        for (var i = 0; i + 1 < s.changes.length; i += 2) {
          grid[s.changes[i]] = s.changes[i + 1];
        }
      }
      expect(grid, lobby.rooms.values.single.sim.arena.owner.toList());
    });

    test('a long match never degenerates: nobody owns it all, nobody stays stuck dead', () {
      final lobby = Lobby(seed: 33);
      join(lobby, name: 'Idle', id: 'x');
      final room = lobby.rooms.values.single;
      final cells = room.sim.arena.cellCount;
      var worst = 0.0;
      for (var sec = 0; sec < 600; sec++) {
        run(lobby, 1);
        for (final p in room.sim.players.where((p) => !p.vacant)) {
          worst = math.max(worst, room.sim.arena.counts[p.id] * 100 / cells);
        }
        if (sec > 30 && sec % 20 == 0) {
          final seated = room.sim.players.where((p) => !p.vacant).toList();
          final dead = seated.where((p) => !p.alive).length;
          expect(dead, lessThan(seated.length), reason: 'at least someone is alive at t=$sec');
        }
      }
      expect(worst, lessThan(62), reason: 'the round ends before anyone can run away with it');
      expect(room.roundsPlayed, greaterThanOrEqualTo(3));
    });

    test('empty rooms stop costing CPU and bots keep fighting while a human is there', () {
      final lobby = Lobby(seed: 16);
      final a = join(lobby);
      run(lobby, 20);
      final room = lobby.rooms.values.single;
      final botLand = room.sim.players.where((p) => !p.vacant && !p.isHuman).fold<int>(0, (n, p) => n + room.sim.arena.counts[p.id]);
      expect(botLand, greaterThan(50), reason: 'bots spread out on their own');
      lobby.disconnect(a);
      expect(lobby.rooms, isEmpty);
    });

    test('a long soak with joins, leaves and steering stays consistent', () {
      final lobby = Lobby(seed: 17);
      final rng = math.Random(5);
      final conns = <FakeConn>[];
      for (var step = 0; step < 900; step++) {
        if (rng.nextDouble() < 0.02 && conns.length < 10) {
          conns.add(join(lobby, name: 'P$step', id: 'p$step', mode: rng.nextBool() ? JoinMode.quick : JoinMode.create));
        }
        if (rng.nextDouble() < 0.015 && conns.isNotEmpty) {
          lobby.disconnect(conns.removeAt(rng.nextInt(conns.length)));
        }
        for (final c in conns) {
          if (rng.nextDouble() < 0.2) lobby.onFrame(c, encodeClient(SteerMsg(rng.nextDouble() * 6.28)));
        }
        lobby.tick(1 / 30);
        for (final r in lobby.rooms.values) {
          final counts = List.filled(17, 0);
          for (final o in r.sim.arena.owner) {
            counts[o]++;
          }
          for (var i = 0; i < 17; i++) {
            expect(counts[i], r.sim.arena.counts[i], reason: 'step $step room ${r.code} owner $i');
          }
          expect(r.humanCount, lessThanOrEqualTo(8));
          expect(r.humanCount + r.botCount, lessThanOrEqualTo(16));
        }
      }
      expect(jsonEncode({'rooms': lobby.rooms.length}), isNotEmpty);
    });
  });
}
