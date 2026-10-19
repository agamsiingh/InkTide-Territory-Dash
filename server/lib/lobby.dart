import 'dart:math' as math;
import 'dart:typed_data';

import '../../lib/game/net/protocol.dart';
import '../../lib/game/sim/arena.dart';
import '../../lib/game/sim/simulation.dart';
import '../../lib/game/sim/skins.dart';

/// One connected player as the lobby sees it (a WebSocket in production, a
/// fake in tests).
abstract class ClientConn {
  void send(String text);
  void close();
}

/// Server tuning. Defaults suit a small VPS.
class ServerConfig {
  const ServerConfig({
    this.arenaSize = 80,
    this.targetPlayers = 8,
    this.maxHumans = 8,
    this.maxRooms = 200,
    this.maxSteerPerSecond = 40,
    this.snapshotEveryTicks = 2,
    this.roundSeconds = 210,
    this.winPercent = 50,
  });

  /// A round ends after this long, or as soon as someone owns [winPercent]
  /// of the arena. Without rounds one player would eventually own everything
  /// and nobody could respawn.
  final double roundSeconds;
  final double winPercent;

  final int arenaSize;

  /// Humans + bots in a room while at least one human is there.
  final int targetPlayers;
  final int maxHumans;
  final int maxRooms;
  final int maxSteerPerSecond;
  final int snapshotEveryTicks;
}

const _codeLetters = 'BCDFGHJKLMNPQRSTVWXZ';

const _blocked = [
  'fuck', 'shit', 'bitch', 'nigg', 'cunt', 'asshole', 'dick', 'pussy', 'whore', 'slut', 'rape', 'nazi', 'hitler',
  'fag', 'cock', 'porn', 'sex', 'kill', 'suicide',
];

/// Makes a safe display name: letters, digits, space and _-. only, 2-14
/// characters, no blocked words. Falls back to "Player123".
String sanitizeName(String raw, String playerId) {
  var n = raw.replaceAll(RegExp(r'[^A-Za-z0-9 _.\-]'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (n.length > 14) n = n.substring(0, 14).trim();
  final flat = n.toLowerCase().replaceAll(RegExp(r'[ _.\-]'), '').replaceAll('0', 'o').replaceAll('1', 'i').replaceAll('3', 'e').replaceAll('4', 'a').replaceAll('5', 's').replaceAll('\$', 's');
  final bad = _blocked.any(flat.contains);
  if (n.length < 2 || bad) {
    final h = playerId.codeUnits.fold<int>(7, (a, c) => (a * 31 + c) & 0xFFFF);
    return 'Player${100 + h % 900}';
  }
  return n;
}

class _Session {
  _Session(this.conn);
  final ClientConn conn;
  Room? room;
  int slot = 0;
  String playerId = '';
  bool helloDone = false;
  // Token bucket for steering messages.
  double tokens = 0;
}

/// Owns every room and routes messages. Not tied to sockets: feed it
/// decoded messages and call [tick] on a timer.
class Lobby {
  Lobby({this.config = const ServerConfig(), int? seed}) : _rng = math.Random(seed ?? DateTime.now().microsecondsSinceEpoch);

  final ServerConfig config;
  final math.Random _rng;
  final Map<String, Room> rooms = {};
  final Map<ClientConn, _Session> _sessions = {};

  int get connections => _sessions.length;
  int get humans => _sessions.values.where((s) => s.room != null).length;

  void connect(ClientConn c) => _sessions[c] = _Session(c);

  /// True once [c] sits in a room.
  bool isSeated(ClientConn c) => _sessions[c]?.room != null;

  void disconnect(ClientConn c) {
    final s = _sessions.remove(c);
    if (s != null) _leave(s);
  }

  /// Handles one raw text frame from [c].
  void onFrame(ClientConn c, Object? frame) {
    final s = _sessions[c];
    if (s == null) return;
    final msg = decodeClient(frame);
    if (msg == null) return; // garbage is ignored, never crashes the server
    switch (msg) {
      case HelloMsg():
        if (s.helloDone) return;
        s.helloDone = true;
        _join(s, msg);
      case SteerMsg():
        final r = s.room;
        if (r == null || s.tokens < 1) return;
        s.tokens -= 1;
        r.steer(s.slot, msg.angle);
      case LeaveMsg():
        _leave(s);
        s.helloDone = false; // may join again on the same socket
      case PingMsg():
        _send(c, PongMsg(msg.stamp));
    }
  }

  void _send(ClientConn c, ServerMsg m) {
    try {
      c.send(encodeServer(m));
    } catch (_) {}
  }

  String _newCode() {
    for (var i = 0; i < 200; i++) {
      final code = String.fromCharCodes([for (var k = 0; k < 4; k++) _codeLetters.codeUnitAt(_rng.nextInt(_codeLetters.length))]);
      if (!rooms.containsKey(code)) return code;
    }
    throw StateError('no free room code');
  }

  Room? _createRoom({required bool isPublic}) {
    if (rooms.length >= config.maxRooms) return null;
    final code = _newCode();
    final r = Room(code, config, isPublic: isPublic, seed: _rng.nextInt(1 << 30));
    rooms[code] = r;
    return r;
  }

  void _join(_Session s, HelloMsg hello) {
    s.playerId = hello.playerId;
    Room? room;
    switch (hello.mode) {
      case JoinMode.quick:
        // Fill the busiest public room that still has space.
        final open = rooms.values.where((r) => r.isPublic && r.humanCount < config.maxHumans).toList()
          ..sort((a, b) => b.humanCount.compareTo(a.humanCount));
        room = open.isEmpty ? _createRoom(isPublic: true) : open.first;
      case JoinMode.create:
        room = _createRoom(isPublic: false);
      case JoinMode.join:
        final code = (hello.code ?? '').toUpperCase().trim();
        room = rooms[code];
        if (room == null) {
          _send(s.conn, const ErrorMsg('room_not_found', 'No room with that code.'));
          s.helloDone = false;
          return;
        }
        if (room.humanCount >= config.maxHumans) {
          _send(s.conn, const ErrorMsg('room_full', 'That room is full.'));
          s.helloDone = false;
          return;
        }
    }
    if (room == null) {
      _send(s.conn, const ErrorMsg('server_busy', 'The server is full. Try again in a minute.'));
      s.helloDone = false;
      return;
    }
    final name = sanitizeName(hello.name, hello.playerId);
    final slot = room.addHuman(s.conn, name, skinById(hello.skin));
    if (slot == null) {
      _send(s.conn, const ErrorMsg('room_full', 'That room is full.'));
      s.helloDone = false;
      return;
    }
    s.room = room;
    s.slot = slot;
    s.tokens = config.maxSteerPerSecond.toDouble();
    room.sendWelcome(s.conn, slot);
  }

  void _leave(_Session s) {
    final r = s.room;
    if (r == null) return;
    r.removeHuman(s.slot);
    s.room = null;
    s.slot = 0;
    if (r.humanCount == 0) rooms.remove(r.code);
  }

  /// Advances every room by [dt] seconds.
  void tick(double dt) {
    for (final s in _sessions.values) {
      s.tokens = math.min(config.maxSteerPerSecond.toDouble(), s.tokens + config.maxSteerPerSecond * dt);
    }
    for (final r in rooms.values) {
      r.tick(dt);
    }
  }
}

class Room {
  Room(this.code, this.config, {required this.isPublic, int seed = 1})
      : sim = Simulation.room(size: config.arenaSize, seed: seed),
        _rng = math.Random(seed ^ 0x9e37) {
    sim.arena.changeLog = [];
  }

  final String code;
  final ServerConfig config;
  final bool isPublic;
  final Simulation sim;
  final math.Random _rng;
  final Map<int, ClientConn> _humans = {}; // slot id -> connection
  final List<SimEvent> _pendingEvents = [];
  final TrailSync _trails = TrailSync();
  int _ticks = 0;
  int _seq = 0;
  double _roundTime = 0;
  int roundsPlayed = 0;

  /// Whole seconds left in the current round.
  int get roundLeft => math.max(0, (config.roundSeconds - _roundTime).ceil());

  int get humanCount => _humans.length;
  int get botCount => sim.countPlayers(humans: false);

  SlotInfo _info(SimPlayer p) => SlotInfo(p.id, p.name, p.skin.id, p.isHuman);

  List<SlotInfo> get slots => [for (final p in sim.players) if (!p.vacant) _info(p)];

  void _broadcast(ServerMsg m, {ClientConn? except}) {
    final text = encodeServer(m);
    for (final c in _humans.values) {
      if (c == except) continue;
      try {
        c.send(text);
      } catch (_) {}
    }
  }

  /// Seats a human. Bots make room for them, so the arena is never "full" of bots.
  int? addHuman(ClientConn c, String name, Skin skin) {
    if (_humans.length >= config.maxHumans) return null;
    if (sim.countPlayers(humans: true) + sim.countPlayers(humans: false) >= Arena.maxPlayers) {
      _removeBot();
    }
    final unique = _uniqueName(name);
    final p = sim.addPlayer(name: unique, skin: skin, human: true);
    if (p == null) return null;
    _humans[p.id] = c;
    // The newcomer has seen no trails yet: next snapshot sends them all.
    _trails.forgetAll();
    _balanceBots();
    _broadcast(SlotMsg(_info(p), false), except: c);
    return p.id;
  }

  void removeHuman(int slot) {
    final p = sim.byId(slot);
    if (p == null || !_humans.containsKey(slot)) return;
    _humans.remove(slot);
    final info = _info(p);
    sim.removePlayer(p);
    _trails.forget(slot);
    _broadcast(SlotMsg(info, true));
    _balanceBots();
  }

  String _uniqueName(String name) {
    final taken = {for (final p in sim.players) if (!p.vacant) p.name};
    if (!taken.contains(name)) return name;
    for (var i = 2; i < 100; i++) {
      final candidate = '${name.length > 11 ? name.substring(0, 11) : name} $i';
      if (!taken.contains(candidate)) return candidate;
    }
    return name;
  }

  /// Keeps the arena lively: bots fill the empty seats up to the target and
  /// step aside as humans arrive. An empty room has no bots at all.
  void _balanceBots() {
    final want = _humans.isEmpty ? 0 : math.max(0, config.targetPlayers - _humans.length);
    while (botCount > want) {
      _removeBot();
    }
    while (botCount < want) {
      if (!_addBot()) break;
    }
  }

  bool _addBot() {
    final used = {for (final p in sim.players) if (!p.vacant) p.name};
    final names = kBotNames.where((n) => !used.contains(n)).toList();
    if (names.isEmpty) return false;
    final skins = kSkins.where((s) => s.id != 'sunny').toList();
    final p = sim.addPlayer(
      name: names[_rng.nextInt(names.length)],
      skin: skins[_rng.nextInt(skins.length)],
      human: false,
      skill: 0.55 + _rng.nextDouble() * 0.3,
      seed: _rng.nextInt(1 << 30),
    );
    if (p == null) return false;
    _trails.forget(p.id);
    _broadcast(SlotMsg(_info(p), false));
    return true;
  }

  void _removeBot() {
    SimPlayer? weakest;
    for (final p in sim.players) {
      if (p.vacant || p.isHuman) continue;
      if (weakest == null || sim.arena.counts[p.id] < sim.arena.counts[weakest.id]) weakest = p;
    }
    if (weakest == null) return;
    final info = _info(weakest);
    sim.removePlayer(weakest);
    _trails.forget(weakest.id);
    _broadcast(SlotMsg(info, true));
  }

  void steer(int slot, double angle) {
    final p = sim.byId(slot);
    if (p == null || p.vacant || !p.isHuman) return;
    sim.steerPlayer(p, angle);
  }

  void sendWelcome(ClientConn c, int slot) {
    final owners = Uint8List.fromList(sim.arena.owner);
    final msg = WelcomeMsg(you: slot, code: code, size: sim.arena.width, slots: slots, owners: owners);
    try {
      c.send(encodeServer(msg));
    } catch (_) {}
  }

  /// Ends the round when time is up or someone has won it, announces the
  /// result, and starts the next round straight away.
  void _checkRound() {
    final cells = sim.arena.cellCount;
    SimPlayer? leader;
    for (final p in sim.players) {
      if (p.vacant) continue;
      if (leader == null || sim.arena.counts[p.id] > sim.arena.counts[leader.id]) leader = p;
    }
    if (leader == null) return;
    final pct = sim.arena.counts[leader.id] * 100 / cells;
    if (_roundTime < config.roundSeconds && pct < config.winPercent) return;
    endRound();
  }

  /// Announces the winner and wipes the arena for the next round.
  void endRound() {
    final cells = sim.arena.cellCount;
    final board = [for (final p in sim.players) if (!p.vacant) p]
      ..sort((a, b) => sim.arena.counts[b.id].compareTo(sim.arena.counts[a.id]));
    if (board.isNotEmpty) {
      final w = board.first;
      _broadcast(RoundMsg(
        winnerSlot: w.id,
        winnerName: w.name,
        percent: sim.arena.counts[w.id] * 100 / cells,
        top: [for (final p in board.take(3)) Score(p.name, sim.arena.counts[p.id] * 100 / cells)],
      ));
    }
    roundsPlayed++;
    _roundTime = 0;
    sim.resetRound();
    // Fresh arena: every client needs everyone's trails again.
    _trails.forgetAll();
    _pendingEvents
      ..clear()
      ..addAll(sim.drainEvents());
  }

  void tick(double dt) {
    if (_humans.isEmpty) return;
    // Sub-step long frames so a hiccup never lets players teleport.
    var left = dt;
    while (left > 1e-6) {
      final d = math.min(left, 1 / 30);
      sim.step(d);
      _pendingEvents.addAll(sim.drainEvents());
      left -= d;
    }
    _roundTime += dt;
    _checkRound();
    _ticks++;
    if (_ticks % config.snapshotEveryTicks != 0) return;
    final changes = sim.arena.changeLog!;
    // A cell may change several times between snapshots; send each once.
    final unique = <int>{...changes}.toList();
    changes.clear();
    _broadcast(buildSnapshot(sim, ++_seq, unique, List.of(_pendingEvents), _trails, roundLeft: roundLeft));
    _pendingEvents.clear();
  }
}
