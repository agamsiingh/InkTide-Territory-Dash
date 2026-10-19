// ignore_for_file: avoid_relative_lib_imports, avoid_print
// How many rooms can one server core tick in real time?
//   dart run tool/bench_server.dart [rooms]
import 'dart:math' as math;

import '../lib/game/net/protocol.dart';
import '../server/lib/lobby.dart';

class _Null implements ClientConn {
  int bytes = 0;
  @override
  void send(String text) => bytes += text.length;
  @override
  void close() {}
}

void main(List<String> args) {
  final rooms = int.tryParse(args.isNotEmpty ? args[0] : '') ?? 25;
  final lobby = Lobby(seed: 1, config: const ServerConfig(maxRooms: 1000));
  final rng = math.Random(3);
  final conns = <_Null>[];
  for (var r = 0; r < rooms; r++) {
    String? code;
    for (var i = 0; i < 8; i++) {
      final c = _Null();
      conns.add(c);
      lobby.connect(c);
      lobby.onFrame(c, encodeClient(HelloMsg(name: 'P$r$i', playerId: 'p$r$i', skin: 'sunny', mode: i == 0 ? JoinMode.create : JoinMode.join, code: code)));
      if (i == 0) code = lobby.rooms.keys.last;
    }
  }
  print('rooms=${lobby.rooms.length} humans=${lobby.humans}');
  // Warm up, then time 600 ticks (20 s of game time).
  for (var i = 0; i < 90; i++) {
    lobby.tick(1 / 30);
  }
  final sw = Stopwatch()..start();
  var worst = 0;
  const ticks = 600;
  for (var i = 0; i < ticks; i++) {
    if (i % 5 == 0) {
      for (final c in conns) {
        if (rng.nextDouble() < 0.3) lobby.onFrame(c, encodeClient(SteerMsg(rng.nextDouble() * 6.28)));
      }
    }
    final t = sw.elapsedMicroseconds;
    lobby.tick(1 / 30);
    worst = math.max(worst, sw.elapsedMicroseconds - t);
  }
  sw.stop();
  final avg = sw.elapsedMicroseconds / ticks / 1000;
  final bytes = conns.fold<int>(0, (a, c) => a + c.bytes);
  print('avg tick ${avg.toStringAsFixed(2)} ms (budget 33.3), worst ${(worst / 1000).toStringAsFixed(1)} ms');
  print('cpu use at 30 Hz: ${(avg / 33.3 * 100).toStringAsFixed(0)}% of one core');
  print('outgoing: ${(bytes / 20 / conns.length / 1024).toStringAsFixed(1)} KB/s per player');
}
