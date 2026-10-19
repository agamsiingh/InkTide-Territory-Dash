// ignore_for_file: avoid_relative_lib_imports, avoid_print
// Headless stand-in for another human player (not shipped): joins a room over
// WebSocket, wanders around and tries to paint land. For testing online play.
//   dart run tool/remote_player.dart ws://127.0.0.1:8080 [quick|create|CODE] [name]
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import '../lib/game/net/protocol.dart';

Future<void> main(List<String> args) async {
  final url = args.isNotEmpty ? args[0] : 'ws://127.0.0.1:8080';
  final what = args.length > 1 ? args[1] : 'quick';
  final name = args.length > 2 ? args[2] : 'Robo';
  final mode = what == 'quick' ? JoinMode.quick : (what == 'create' ? JoinMode.create : JoinMode.join);
  final ws = await WebSocket.connect(url);
  ws.add(encodeClient(HelloMsg(name: name, playerId: 'robo-$name', skin: 'panda', mode: mode, code: mode == JoinMode.join ? what : null)));
  var you = 0;
  var x = 0.0, y = 0.0;
  var alive = true;
  final rng = math.Random(name.hashCode);
  var heading = 0.0;
  var leg = 0;
  Timer? brain;
  ws.listen((data) {
    final m = decodeServer(data);
    if (m is WelcomeMsg) {
      you = m.you;
      print('$name joined room ${m.code} as slot $you (${m.slots.length} players)');
    } else if (m is ErrorMsg) {
      print('error ${m.code}: ${m.message}');
      exit(1);
    } else if (m is SnapshotMsg) {
      for (final p in m.players) {
        if (p.id == you) {
          x = p.x;
          y = p.y;
          alive = p.alive;
        }
      }
    }
  }, onDone: () {
    print('server closed');
    brain?.cancel();
    exit(0);
  });
  // Walk square-ish loops and steer away from the walls.
  brain = Timer.periodic(const Duration(milliseconds: 250), (_) {
    if (you == 0 || !alive) return;
    leg++;
    if (leg % 14 == 0) heading += (rng.nextBool() ? 1 : -1) * math.pi / 2;
    if (x < 6) heading = 0;
    if (x > 74) heading = math.pi;
    if (y < 6) heading = math.pi / 2;
    if (y > 74) heading = -math.pi / 2;
    ws.add(encodeClient(SteerMsg(heading)));
  });
  await ProcessSignal.sigint.watch().first;
  ws.add(jsonEncode({'t': 'leave'}));
  await ws.close();
}
