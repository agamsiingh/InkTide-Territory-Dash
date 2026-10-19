// ignore_for_file: avoid_relative_lib_imports
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inktide/game/net/protocol.dart' as client;
import 'package:inktide/services/online_session.dart';

import '../../server/lib/lobby.dart';
import '../../server/lib/ws_server.dart';

// NOTE: plain test() (no widget binding) so real sockets are allowed.

late GameServer server;
late Lobby lobby;

Uri get url => Uri.parse('ws://127.0.0.1:${server.port}');

client.HelloMsg hello(String name, {client.JoinMode mode = client.JoinMode.quick, String? code, String skin = 'sunny'}) =>
    client.HelloMsg(name: name, playerId: 'id-$name', skin: skin, mode: mode, code: code);

/// Runs [seconds] of game time: server ticks, frames cross the real sockets,
/// then every session updates.
Future<void> play(List<OnlineSession> sessions, double seconds) async {
  for (var t = 0.0; t < seconds; t += 1 / 30) {
    lobby.tick(1 / 30);
    await Future<void>.delayed(const Duration(milliseconds: 3));
    for (final s in sessions) {
      s.update(1 / 30);
    }
  }
  await Future<void>.delayed(const Duration(milliseconds: 20));
}

void main() {
  setUp(() async {
    lobby = Lobby(seed: 21);
    server = GameServer(lobby);
    await server.start(host: '127.0.0.1', port: 0, autoTick: false);
  });
  tearDown(() async => server.stop());

  test('a client joins over a real socket and gets a live arena', () async {
    final a = OnlineSession();
    await a.join(url, hello('Ann'));
    expect(a.state, OnlineState.playing);
    expect(a.code, matches(RegExp(r'^[A-Z]{4}$')));
    expect(a.mirror!.arena.width, 80);
    expect(a.playerCount, 8);
    expect(a.me!.name, 'Ann');
    expect(a.mirror!.arena.counts[a.you], greaterThan(10));
    await play([a], 1);
    expect(a.mirror!.players.where((p) => !p.vacant && p.alive).length, greaterThan(5));
    await a.leave();
  });

  test('two players see each other, steer independently, and their arenas match the server', () async {
    final a = OnlineSession(), b = OnlineSession();
    await a.join(url, hello('Ann'));
    await b.join(url, hello('Bo', skin: 'panda'));
    expect(a.code, b.code, reason: 'quick play puts them in the same room');
    await play([a, b], 0.5);
    expect(a.mirror!.players.any((p) => p.name == 'Bo' && p.skin.id == 'panda'), isTrue);
    expect(b.mirror!.players.any((p) => p.name == 'Ann'), isTrue);
    expect(a.humanCount, 2);

    a.mirror!.human.desiredHeading = 0;
    a.sendSteer(0);
    b.mirror!.human.desiredHeading = 3.14;
    b.sendSteer(3.14);
    await play([a, b], 0.3);
    final ax0 = a.me!.x, bx0 = b.me!.x;
    await play([a, b], 1.5);
    expect(a.me!.x, greaterThan(ax0 + 4), reason: 'Ann moves right');
    expect(b.me!.x, lessThan(bx0 - 4).or(equals(0.0)), reason: 'Bo moves left');
    // Ann sees Bo where the server has him.
    final room = lobby.rooms.values.single;
    final serverBo = room.sim.players.firstWhere((p) => p.name == 'Bo');
    final seenBo = a.mirror!.players.firstWhere((p) => p.name == 'Bo');
    expect((seenBo.x - serverBo.x).abs(), lessThan(2.5));
    expect((seenBo.y - serverBo.y).abs(), lessThan(2.5));

    // Let things settle and compare the whole arena.
    await play([a, b], 20);
    lobby.tick(1 / 30);
    lobby.tick(1 / 30);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final serverGrid = room.sim.arena.owner.toList();
    final mine = a.mirror!.arena.owner.toList();
    var diff = 0;
    for (var i = 0; i < serverGrid.length; i++) {
      if (serverGrid[i] != mine[i]) diff++;
    }
    expect(diff, lessThan(40), reason: 'only in-flight cells differ ($diff)');
    await a.leave();
    await b.leave();
  });

  test('create a private room, join it by code, and bad codes are refused', () async {
    final host = OnlineSession();
    await host.join(url, hello('Host', mode: client.JoinMode.create));
    final friend = OnlineSession();
    await friend.join(url, hello('Pal', mode: client.JoinMode.join, code: host.code));
    expect(friend.code, host.code);
    await play([host, friend], 0.4);
    expect(host.humanCount, 2);

    final stranger = OnlineSession();
    await expectLater(
      stranger.join(url, hello('Nope', mode: client.JoinMode.join, code: 'ZZZZ')),
      throwsA(isA<OnlineException>().having((e) => e.code, 'code', 'room_not_found')),
    );
    expect(lobby.rooms.length, 1);
    await host.leave();
    await friend.leave();
  });

  test('leaving tells the others and an empty room is closed', () async {
    final a = OnlineSession(), b = OnlineSession();
    await a.join(url, hello('Ann'));
    await b.join(url, hello('Bo'));
    await play([a, b], 0.4);
    await b.leave();
    await play([a], 0.4);
    expect(a.humanCount, 1);
    expect(a.mirror!.players.where((p) => !p.vacant && p.name == 'Bo'), isEmpty);
    await a.leave();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(lobby.rooms, isEmpty);
  });

  test('if the server goes away the client reports a lost connection', () async {
    final a = OnlineSession();
    await a.join(url, hello('Ann'));
    await server.stop();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(a.state, OnlineState.closed);
    expect(a.lostReason?.code, 'connection_lost');
  });

  test('an unreachable address fails with connect_failed', () async {
    final s = OnlineSession();
    await expectLater(
      s.join(Uri.parse('ws://127.0.0.1:1'), hello('Ann')),
      throwsA(isA<OnlineException>().having((e) => e.code, 'code', 'connect_failed')),
    );
  });

  test('/health answers for hosting platforms and unknown paths 404', () async {
    final http = HttpClient();
    final ok = await (await http.getUrl(Uri.parse('http://127.0.0.1:${server.port}/health'))).close();
    expect(ok.statusCode, 200);
    final nope = await (await http.getUrl(Uri.parse('http://127.0.0.1:${server.port}/nope'))).close();
    expect(nope.statusCode, 404);
    http.close(force: true);
  });

  test('a raw socket sending junk is ignored and never crashes the server', () async {
    final ws = await WebSocket.connect(url.toString());
    for (final junk in ['', 'zzz', '{"t":"steer","a":"x"}', '[1,2,3]', 'x' * 5000]) {
      ws.add(junk);
    }
    ws.add([1, 2, 3]); // binary frame
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(lobby.rooms, isEmpty);
    // The server is still fine.
    final a = OnlineSession();
    await a.join(url, hello('Ann'));
    expect(a.state, OnlineState.playing);
    await a.leave();
    await ws.close();
  });
}

extension on Matcher {
  Matcher or(Matcher other) => anyOf(this, other);
}
