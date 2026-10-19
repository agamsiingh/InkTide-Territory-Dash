// ignore_for_file: avoid_relative_lib_imports, avoid_print
// Does one player snowball in a long-running online arena?
//   dart run tool/bench_snowball.dart [minutes] [seed]
import '../lib/game/net/protocol.dart';
import '../server/lib/lobby.dart';

class _Null implements ClientConn {
  @override
  void send(String text) {}
  @override
  void close() {}
}

void main(List<String> args) {
  final minutes = int.tryParse(args.isNotEmpty ? args[0] : '') ?? 20;
  final seed = int.tryParse(args.length > 1 ? args[1] : '') ?? 1;
  final lobby = Lobby(seed: seed);
  final c = _Null();
  lobby.connect(c);
  lobby.onFrame(c, encodeClient(const HelloMsg(name: 'Idle', playerId: 'x', skin: 'sunny', mode: JoinMode.quick)));
  final room = lobby.rooms.values.single;
  final cells = room.sim.arena.cellCount;
  for (var m = 1; m <= minutes; m++) {
    for (var i = 0; i < 30 * 60; i++) {
      lobby.tick(1 / 30);
    }
    final owners = <MapEntry<String, double>>[];
    for (final p in room.sim.players) {
      if (p.vacant) continue;
      owners.add(MapEntry(p.name, room.sim.arena.counts[p.id] * 100 / cells));
    }
    owners.sort((a, b) => b.value.compareTo(a.value));
    final unclaimed = room.sim.arena.counts[0] * 100 / cells;
    if (m <= 3 || m % 5 == 0) {
      print('min $m: top ${owners.first.key} ${owners.first.value.toStringAsFixed(1)}%  2nd ${owners[1].value.toStringAsFixed(1)}%  unclaimed ${unclaimed.toStringAsFixed(0)}%');
    }
  }
}
