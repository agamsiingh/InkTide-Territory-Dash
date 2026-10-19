import 'dart:convert';
import 'dart:typed_data';

import '../sim/simulation.dart';

/// Wire protocol between the game client and the room server.
///
/// Plain Dart (no Flutter) so the server can import this very file. Messages
/// are JSON text frames. Everything coming from the other side is untrusted:
/// the decoders return null instead of throwing on anything malformed.
const int kProtocolVersion = 1;

/// Longest text frame the server will read.
const int kMaxClientFrame = 2048;

enum JoinMode { quick, create, join }

// ---- client -> server --------------------------------------------------------

sealed class ClientMsg {
  const ClientMsg();
}

class HelloMsg extends ClientMsg {
  const HelloMsg({
    required this.name,
    required this.playerId,
    required this.skin,
    required this.mode,
    this.code,
  });
  final String name;

  /// Stable id of the player (Play Games id or a random guest id).
  final String playerId;
  final String skin;
  final JoinMode mode;

  /// Room code for [JoinMode.join].
  final String? code;
}

class SteerMsg extends ClientMsg {
  const SteerMsg(this.angle);
  final double angle;
}

class LeaveMsg extends ClientMsg {
  const LeaveMsg();
}

class PingMsg extends ClientMsg {
  const PingMsg(this.stamp);
  final int stamp;
}

String encodeClient(ClientMsg m) => jsonEncode(switch (m) {
      HelloMsg() => {
          't': 'hello',
          'v': kProtocolVersion,
          'name': m.name,
          'id': m.playerId,
          'skin': m.skin,
          'mode': m.mode.name,
          if (m.code != null) 'code': m.code,
        },
      SteerMsg() => {'t': 'steer', 'a': _r2(m.angle)},
      LeaveMsg() => {'t': 'leave'},
      PingMsg() => {'t': 'ping', 's': m.stamp},
    });

/// Parses a frame from a client. Returns null for anything invalid.
ClientMsg? decodeClient(Object? frame) {
  if (frame is! String || frame.length > kMaxClientFrame) return null;
  final Object? j;
  try {
    j = jsonDecode(frame);
  } catch (_) {
    return null;
  }
  if (j is! Map) return null;
  switch (j['t']) {
    case 'hello':
      if (j['v'] != kProtocolVersion) return null;
      final name = j['name'], id = j['id'], skin = j['skin'], mode = j['mode'], code = j['code'];
      if (name is! String || id is! String || skin is! String || mode is! String) return null;
      if (id.isEmpty || id.length > 64 || skin.length > 32) return null;
      final jm = JoinMode.values.where((m) => m.name == mode);
      if (jm.isEmpty) return null;
      if (code != null && code is! String) return null;
      return HelloMsg(name: name, playerId: id, skin: skin, mode: jm.first, code: code as String?);
    case 'steer':
      final a = j['a'];
      if (a is! num || !a.isFinite) return null;
      return SteerMsg(a.toDouble());
    case 'leave':
      return const LeaveMsg();
    case 'ping':
      final s = j['s'];
      return s is int ? PingMsg(s) : null;
  }
  return null;
}

// ---- server -> client ----------------------------------------------------------

/// Who sits in an arena slot.
class SlotInfo {
  const SlotInfo(this.id, this.name, this.skin, this.human);
  final int id;
  final String name;
  final String skin;
  final bool human;

  Map<String, Object> toJson() => {'i': id, 'n': name, 's': skin, 'h': human ? 1 : 0};

  static SlotInfo? fromJson(Object? j) {
    if (j is! Map) return null;
    final i = j['i'], n = j['n'], s = j['s'], h = j['h'];
    if (i is! int || i < 1 || i > 16 || n is! String || s is! String || h is! int) return null;
    return SlotInfo(i, n, s, h == 1);
  }
}

class PlayerState {
  const PlayerState(this.id, this.x, this.y, this.heading, this.alive, this.kills, this.trail, {this.reset = false});
  final int id;
  final double x, y, heading;
  final bool alive;
  final int kills;

  /// Trail polyline points x0,y0,x1,y1,... in cells. With [reset] this is the
  /// whole trail (replace what you had); otherwise only the points added since
  /// the previous snapshot (append them). Sending only new points is what keeps
  /// the bandwidth small.
  final List<double> trail;
  final bool reset;
}

/// What the server last told clients about each trail, so snapshots can carry
/// just the new points.
class TrailSync {
  final Map<int, int> _gen = {};
  final Map<int, int> _len = {};

  /// Next snapshot sends every trail in full (a player just joined).
  void forgetAll() {
    _gen.clear();
    _len.clear();
  }

  void forget(int slot) {
    _gen.remove(slot);
    _len.remove(slot);
  }
}

class NetEvent {
  const NetEvent(this.kind, this.a, this.b, this.c, this.x, this.y);

  /// 'c' capture(a=player, b=cells), 'd' death(a=victim, b=killer, c=cause), 's' spawn(a=player).
  final String kind;
  final int a, b, c;
  final double x, y;
}

sealed class ServerMsg {
  const ServerMsg();
}

class WelcomeMsg extends ServerMsg {
  const WelcomeMsg({required this.you, required this.code, required this.size, required this.slots, required this.owners});
  final int you;
  final String code;
  final int size;
  final List<SlotInfo> slots;

  /// Full ownership grid, row-major, one byte per cell.
  final Uint8List owners;
}

class SlotMsg extends ServerMsg {
  const SlotMsg(this.slot, this.left);
  final SlotInfo slot;

  /// True when this player left (the slot is now empty).
  final bool left;
}

class SnapshotMsg extends ServerMsg {
  const SnapshotMsg(this.seq, this.players, this.changes, this.events, {this.roundLeft = 0});
  final int seq;

  /// Whole seconds until this round ends (0 = unknown).
  final int roundLeft;
  final List<PlayerState> players;

  /// Flat list idx0, owner0, idx1, owner1, ... of changed cells.
  final List<int> changes;
  final List<NetEvent> events;
}

/// One line of a round scoreboard.
class Score {
  const Score(this.name, this.percent);
  final String name;
  final double percent;
}

/// The round just ended: who won and the top of the scoreboard. A new round
/// starts immediately (the arena is wiped in the same instant).
class RoundMsg extends ServerMsg {
  const RoundMsg({required this.winnerSlot, required this.winnerName, required this.percent, required this.top});
  final int winnerSlot;
  final String winnerName;
  final double percent;
  final List<Score> top;
}

class ErrorMsg extends ServerMsg {
  const ErrorMsg(this.code, this.message);
  final String code;
  final String message;
}

class PongMsg extends ServerMsg {
  const PongMsg(this.stamp);
  final int stamp;
}

double _r2(num v) => (v * 100).roundToDouble() / 100;

String encodeServer(ServerMsg m) => jsonEncode(switch (m) {
      WelcomeMsg() => {
          't': 'welcome',
          'v': kProtocolVersion,
          'you': m.you,
          'code': m.code,
          'size': m.size,
          'slots': [for (final s in m.slots) s.toJson()],
          'own': base64Encode(m.owners),
        },
      SlotMsg() => {'t': 'slot', 'left': m.left ? 1 : 0, 'slot': m.slot.toJson()},
      SnapshotMsg() => {
          't': 'snap',
          'q': m.seq,
          'rl': m.roundLeft,
          'p': [
            for (final p in m.players)
              [
                p.id,
                _r2(p.x),
                _r2(p.y),
                _r2(p.heading),
                p.alive ? 1 : 0,
                p.kills,
                p.reset ? 1 : 0,
                // Trail in tenths of a cell keeps the frame small.
                [for (final v in p.trail) (v * 10).round()],
              ],
          ],
          'd': m.changes,
          'e': [
            for (final e in m.events) [e.kind, e.a, e.b, e.c, _r2(e.x), _r2(e.y)],
          ],
        },
      RoundMsg() => {
          't': 'round',
          'w': m.winnerSlot,
          'n': m.winnerName,
          'p': _r2(m.percent),
          'top': [
            for (final s in m.top) [s.name, _r2(s.percent)],
          ],
        },
      ErrorMsg() => {'t': 'err', 'c': m.code, 'm': m.message},
      PongMsg() => {'t': 'pong', 's': m.stamp},
    });

/// Parses a frame from the server. Returns null for anything invalid.
ServerMsg? decodeServer(Object? frame) {
  if (frame is! String) return null;
  final Object? j;
  try {
    j = jsonDecode(frame);
  } catch (_) {
    return null;
  }
  if (j is! Map) return null;
  try {
    switch (j['t']) {
      case 'welcome':
        if (j['v'] != kProtocolVersion) return null;
        final you = j['you'], code = j['code'], size = j['size'], slots = j['slots'], own = j['own'];
        if (you is! int || code is! String || size is! int || slots is! List || own is! String) return null;
        if (size < 8 || size > 200 || you < 1 || you > 16) return null;
        final owners = base64Decode(own);
        if (owners.length != size * size) return null;
        final list = <SlotInfo>[];
        for (final s in slots) {
          final info = SlotInfo.fromJson(s);
          if (info == null) return null;
          list.add(info);
        }
        return WelcomeMsg(you: you, code: code, size: size, slots: list, owners: owners);
      case 'slot':
        final info = SlotInfo.fromJson(j['slot']);
        if (info == null) return null;
        return SlotMsg(info, j['left'] == 1);
      case 'snap':
        final q = j['q'], p = j['p'], d = j['d'], e = j['e'];
        if (q is! int || p is! List || d is! List || e is! List) return null;
        final players = <PlayerState>[];
        for (final row in p) {
          if (row is! List || row.length < 8) return null;
          final trail = row[7];
          if (trail is! List) return null;
          players.add(PlayerState(
            (row[0] as num).toInt(),
            (row[1] as num).toDouble(),
            (row[2] as num).toDouble(),
            (row[3] as num).toDouble(),
            row[4] == 1,
            (row[5] as num).toInt(),
            [for (final v in trail) (v as num) / 10],
            reset: row[6] == 1,
          ));
        }
        final events = <NetEvent>[];
        for (final row in e) {
          if (row is! List || row.length < 6) return null;
          events.add(NetEvent(row[0] as String, (row[1] as num).toInt(), (row[2] as num).toInt(),
              (row[3] as num).toInt(), (row[4] as num).toDouble(), (row[5] as num).toDouble()));
        }
        final rl = j['rl'];
        return SnapshotMsg(q, players, [for (final v in d) (v as num).toInt()], events, roundLeft: rl is int ? rl : 0);
      case 'round':
        final w = j['w'], n = j['n'], p = j['p'], top = j['top'];
        if (w is! int || n is! String || p is! num || top is! List) return null;
        final scores = <Score>[];
        for (final row in top) {
          if (row is! List || row.length < 2 || row[0] is! String || row[1] is! num) return null;
          scores.add(Score(row[0] as String, (row[1] as num).toDouble()));
        }
        return RoundMsg(winnerSlot: w, winnerName: n, percent: p.toDouble(), top: scores);
      case 'err':
        return ErrorMsg('${j['c']}', '${j['m']}');
      case 'pong':
        final s = j['s'];
        return s is int ? PongMsg(s) : null;
    }
  } catch (_) {
    return null;
  }
  return null;
}

// ---- building a snapshot from the authoritative simulation -----------------------

int _causeIndex(DeathCause c) => c.index;

/// Captures what clients need to draw [sim] right now. [changes] are the
/// cells whose owner changed since the last snapshot; [events] the sim events
/// since then.
SnapshotMsg buildSnapshot(Simulation sim, int seq, List<int> changes, List<SimEvent> events, TrailSync sync,
    {int roundLeft = 0}) {
  final players = <PlayerState>[];
  for (final p in sim.players) {
    if (p.vacant) continue;
    final pts = p.alive ? p.trailPoints : const <double>[];
    final gen = p.alive ? p.trailGen : -1; // a dead player has no trail
    final sameTrail = sync._gen[p.id] == gen && (sync._len[p.id] ?? 0) <= pts.length;
    final from = sameTrail ? sync._len[p.id]! : 0;
    sync._gen[p.id] = gen;
    sync._len[p.id] = pts.length;
    players.add(PlayerState(p.id, p.x, p.y, p.heading, p.alive, p.kills, pts.sublist(from), reset: !sameTrail));
  }
  final flat = <int>[];
  for (final idx in changes) {
    flat
      ..add(idx)
      ..add(sim.arena.owner[idx]);
  }
  final ev = <NetEvent>[];
  for (final e in events) {
    switch (e) {
      case CaptureEvent():
        ev.add(NetEvent('c', e.playerId, e.cells, 0, e.x, e.y));
      case DeathEvent():
        ev.add(NetEvent('d', e.victimId, e.killerId, _causeIndex(e.cause), e.x, e.y));
      case SpawnEvent():
        ev.add(NetEvent('s', e.playerId, 0, 0, 0, 0));
      case PowerEvent():
        ev.add(NetEvent('c', e.playerId, e.cells, 0, e.x, e.y));
    }
  }
  return SnapshotMsg(seq, players, flat, ev, roundLeft: roundLeft);
}

/// Turns wire events back into simulation events (for effects on the client).
SimEvent? simEventFromNet(NetEvent e) => switch (e.kind) {
      'c' => CaptureEvent(e.a, e.b, e.x, e.y),
      'd' => e.c >= 0 && e.c < DeathCause.values.length
          ? DeathEvent(e.a, e.b, DeathCause.values[e.c], e.x, e.y)
          : null,
      's' => SpawnEvent(e.a),
      _ => null,
    };
