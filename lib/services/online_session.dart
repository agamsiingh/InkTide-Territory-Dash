import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../game/net/protocol.dart';
import '../game/sim/arena.dart';
import '../game/sim/skins.dart';
import '../game/sim/simulation.dart';

/// Why joining or playing online failed. [code] is machine readable
/// (room_not_found, room_full, server_busy, connect_failed, timeout, ...).
class OnlineException implements Exception {
  const OnlineException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => 'OnlineException($code): $message';
}

/// A socket carrying text frames. Faked in tests.
abstract class OnlineTransport {
  Stream<Object?> get frames;
  void send(String text);
  Future<void> close();
}

typedef TransportFactory = Future<OnlineTransport> Function(Uri url);

class WebSocketTransport implements OnlineTransport {
  WebSocketTransport._(this._socket);
  final WebSocket _socket;

  static Future<OnlineTransport> connect(Uri url) async {
    final ws = await WebSocket.connect(url.toString()).timeout(const Duration(seconds: 8));
    ws.pingInterval = const Duration(seconds: 15);
    return WebSocketTransport._(ws);
  }

  @override
  Stream<Object?> get frames => _socket;

  @override
  void send(String text) {
    if (_socket.readyState == WebSocket.open) _socket.add(text);
  }

  @override
  Future<void> close() async {
    try {
      await _socket.close();
    } catch (_) {}
  }
}

enum OnlineState { idle, connecting, joining, playing, closed }

/// How a round ended, shown as a banner for a few seconds.
class RoundResult {
  const RoundResult({required this.winnerName, required this.percent, required this.top, required this.youWon});
  final String winnerName;
  final double percent;
  final List<Score> top;
  final bool youWon;
}

/// Where a player was drawn and where the server last said it is.
class _Track {
  _Track.at(double x, double y, double h)
      : fromX = x,
        fromY = y,
        fromH = h,
        toX = x,
        toY = y,
        toH = h;
  double fromX, fromY, fromH;
  double toX, toY, toH;
}

/// One online match from the player's side. It keeps a [mirror] of the
/// server's arena in a [Simulation] so the normal renderer can draw it, feeds
/// that mirror from snapshots, smooths movement between them and streams the
/// player's steering to the server. The server decides everything; nothing
/// here can change the outcome.
class OnlineSession extends ChangeNotifier {
  OnlineSession({TransportFactory? factory}) : _factory = factory ?? WebSocketTransport.connect;

  final TransportFactory _factory;
  OnlineTransport? _transport;
  StreamSubscription<Object?>? _sub;

  OnlineState state = OnlineState.idle;
  Simulation? mirror;
  int you = 0;
  String code = '';

  /// Set when the connection ended without the player asking for it.
  OnlineException? lostReason;

  /// Round-trip time in milliseconds (0 until the first pong).
  int pingMs = 0;

  /// Players currently in the arena (humans + bots).
  int get playerCount => mirror?.players.where((p) => !p.vacant).length ?? 0;
  int get humanCount => _humans.length;
  final Set<int> _humans = {};

  /// Seconds left in the current round (0 until the server says).
  int roundLeft = 0;

  /// True once the first snapshot has placed everyone.
  bool hasSnapshot = false;

  /// The round that just ended, for the banner; clears itself after a few seconds.
  final ValueNotifier<RoundResult?> roundResult = ValueNotifier(null);
  double _roundShow = 0;

  // Stats for the results screen. Kills are per round on the server, so they
  // are added up across rounds here.
  int _carriedKills = 0;
  int _roundKills = 0;
  int get kills => _carriedKills + _roundKills;
  int roundWins = 0;
  int deaths = 0;
  double bestPercent = 0;
  double seconds = 0;

  final Map<int, _Track> _tracks = {};
  Completer<void>? _welcome;
  int _lastSeq = -1;
  double _interval = 1 / 15;
  double _alpha = 1;
  double _sinceFrame = 0;
  double _sendTimer = 0;
  double _pingTimer = 0;
  double? _pendingSteer;
  bool _leaving = false;
  final Stopwatch _clock = Stopwatch()..start();
  int _lastSnapMs = 0;

  SimPlayer? get me => mirror == null || you == 0 ? null : mirror!.byId(you);

  /// Connects and joins a room. Completes once the server has welcomed us;
  /// throws [OnlineException] otherwise.
  Future<void> join(Uri url, HelloMsg hello) async {
    if (state != OnlineState.idle) throw StateError('session already used');
    state = OnlineState.connecting;
    notifyListeners();
    try {
      _transport = await _factory(url);
    } catch (_) {
      _fail(const OnlineException('connect_failed', 'Could not reach the server.'));
      throw lostReason!;
    }
    state = OnlineState.joining;
    notifyListeners();
    _welcome = Completer<void>();
    _sub = _transport!.frames.listen(
      _onFrame,
      onDone: _onClosed,
      onError: (_) => _onClosed(),
      cancelOnError: true,
    );
    _transport!.send(encodeClient(hello));
    try {
      await _welcome!.future.timeout(const Duration(seconds: 10));
    } on TimeoutException {
      _fail(const OnlineException('timeout', 'The server did not answer.'));
      await _transport?.close();
      throw lostReason!;
    }
  }

  void _fail(OnlineException e) {
    lostReason = e;
    state = OnlineState.closed;
    notifyListeners();
  }

  void _onClosed() {
    if (state == OnlineState.closed) return;
    final w = _welcome;
    if (w != null && !w.isCompleted) {
      _fail(const OnlineException('connect_failed', 'The server closed the connection.'));
      w.completeError(lostReason!);
      return;
    }
    if (_leaving) {
      state = OnlineState.closed;
    } else {
      _fail(const OnlineException('connection_lost', 'Connection lost.'));
      return;
    }
    notifyListeners();
  }

  void _onFrame(Object? frame) {
    final msg = decodeServer(frame);
    if (msg == null) return;
    _sinceFrame = 0;
    switch (msg) {
      case WelcomeMsg():
        _onWelcome(msg);
      case SnapshotMsg():
        if (state == OnlineState.playing) _onSnapshot(msg);
      case SlotMsg():
        _onSlot(msg);
      case ErrorMsg():
        final w = _welcome;
        final e = OnlineException(msg.code, msg.message);
        if (w != null && !w.isCompleted) {
          _fail(e);
          w.completeError(e);
        } else {
          _fail(e);
        }
      case RoundMsg():
        if (state == OnlineState.playing) _onRound(msg);
      case PongMsg():
        pingMs = math.max(0, DateTime.now().millisecondsSinceEpoch - msg.stamp);
    }
  }

  void _onWelcome(WelcomeMsg w) {
    final sim = Simulation.room(size: w.size);
    sim.arena.loadOwners(w.owners);
    sim.humanIndex = w.you - 1;
    mirror = sim;
    you = w.you;
    code = w.code;
    for (final s in w.slots) {
      _seat(s);
    }
    // Make sure our own slot exists even if the list were somehow short.
    if (sim.byId(you) == null) {
      sim.ensureSlot(you, name: 'You', skin: kSkins.first, human: true);
    }
    state = OnlineState.playing;
    _welcome?.complete();
    notifyListeners();
  }

  void _seat(SlotInfo s) {
    final sim = mirror!;
    // Only the local player counts as "the human" for rendering; everyone
    // else (real or bot) is drawn like a rival with a name tag.
    final p = sim.ensureSlot(s.id, name: s.name, skin: skinById(s.skin), human: s.id == you);
    if (s.human) {
      _humans.add(s.id);
    } else {
      _humans.remove(s.id);
    }
    p.vacant = false;
    _tracks.putIfAbsent(s.id, () => _Track.at(p.x, p.y, p.heading));
  }

  void _onRound(RoundMsg m) {
    final won = m.winnerSlot == you;
    if (won) roundWins++;
    _carriedKills += _roundKills;
    _roundKills = 0;
    roundResult.value = RoundResult(winnerName: m.winnerName, percent: m.percent, top: m.top, youWon: won);
    _roundShow = 6;
    notifyListeners();
  }

  void _onSlot(SlotMsg m) {
    final sim = mirror;
    if (sim == null || state != OnlineState.playing) return;
    if (m.left) {
      final p = sim.byId(m.slot.id);
      if (p != null && !p.vacant && m.slot.id != you) {
        sim.removePlayer(p);
      }
      _tracks.remove(m.slot.id);
      _humans.remove(m.slot.id);
    } else {
      _seat(m.slot);
    }
    notifyListeners();
  }

  void _onSnapshot(SnapshotMsg s) {
    final sim = mirror!;
    if (s.seq <= _lastSeq) return;
    _lastSeq = s.seq;
    if (s.roundLeft > 0) roundLeft = s.roundLeft;
    hasSnapshot = true;
    final now = _clock.elapsedMilliseconds;
    if (_lastSnapMs != 0) {
      final dt = (now - _lastSnapMs) / 1000;
      _interval = (_interval * 0.8 + dt.clamp(0.03, 0.3) * 0.2);
    }
    _lastSnapMs = now;
    _alpha = 0;

    final cells = sim.arena.owner.length;
    for (var i = 0; i + 1 < s.changes.length; i += 2) {
      final idx = s.changes[i], owner = s.changes[i + 1];
      if (idx < 0 || idx >= cells || owner < 0 || owner > Arena.maxPlayers) continue;
      sim.arena.setOwner(idx, owner);
    }
    for (final ps in s.players) {
      final p = sim.byId(ps.id);
      if (p == null || p.vacant) continue;
      final t = _tracks.putIfAbsent(ps.id, () => _Track.at(ps.x, ps.y, ps.heading));
      final wasAlive = p.alive;
      final far = (ps.x - p.x).abs() + (ps.y - p.y).abs() > 6;
      if (!wasAlive || far) {
        // Respawn or a big jump: show it where it is, no sliding across the map.
        t
          ..fromX = ps.x
          ..fromY = ps.y
          ..fromH = ps.heading;
        p
          ..x = ps.x
          ..y = ps.y;
      } else {
        t
          ..fromX = p.x
          ..fromY = p.y
          ..fromH = p.heading;
      }
      t
        ..toX = ps.x
        ..toY = ps.y
        ..toH = ps.heading;
      p
        ..alive = ps.alive
        ..kills = ps.kills;
      if (!ps.alive) {
        p.trailPoints.clear();
      } else {
        // The server sends only new trail points unless the trail restarted.
        if (ps.reset) p.trailPoints.clear();
        p.trailPoints.addAll(ps.trail);
      }
      if (ps.id == you) {
        if (ps.kills < _roundKills) _carriedKills += _roundKills; // a new round started
        _roundKills = ps.kills;
      }
    }
    for (final e in s.events) {
      final ev = simEventFromNet(e);
      if (ev == null) continue;
      sim.events.add(ev);
      if (ev is CaptureEvent) {
        sim.byId(ev.playerId)?.sinceCapture = 0;
      } else if (ev is DeathEvent && ev.victimId == you) {
        deaths++;
      }
    }
  }

  /// Per-frame: smooth everyone toward the latest snapshot, ease our own
  /// heading toward the finger, and send queued steering.
  void update(double dt) {
    final sim = mirror;
    if (sim == null || state != OnlineState.playing) return;
    seconds += dt;
    _sinceFrame += dt;
    if (_roundShow > 0) {
      _roundShow -= dt;
      if (_roundShow <= 0) roundResult.value = null;
    }
    _alpha = math.min(1.0, _alpha + dt / _interval);
    for (final e in _tracks.entries) {
      final p = sim.byId(e.key);
      if (p == null || p.vacant) continue;
      p.sinceCapture += dt;
      if (!p.alive) continue;
      final t = e.value;
      p.x = t.fromX + (t.toX - t.fromX) * _alpha;
      p.y = t.fromY + (t.toY - t.fromY) * _alpha;
      p.cx = p.x.floor().clamp(0, sim.arena.width - 1);
      p.cy = p.y.floor().clamp(0, sim.arena.height - 1);
      if (e.key == you) {
        // Our arrow answers the finger immediately.
        final diff = Simulation.normalizeAngle(p.desiredHeading - p.heading);
        final step = 14 * dt;
        p.heading = Simulation.normalizeAngle(p.heading + diff.clamp(-step, step));
      } else {
        final d = Simulation.normalizeAngle(t.toH - t.fromH);
        p.heading = Simulation.normalizeAngle(t.fromH + d * _alpha);
      }
    }
    final m = me;
    if (m != null) bestPercent = math.max(bestPercent, sim.percentOf(m));

    _sendTimer += dt;
    if (_pendingSteer != null && _sendTimer >= 0.04) {
      _transport?.send(encodeClient(SteerMsg(_pendingSteer!)));
      _pendingSteer = null;
      _sendTimer = 0;
    }
    _pingTimer += dt;
    if (_pingTimer >= 4) {
      _pingTimer = 0;
      _transport?.send(encodeClient(PingMsg(DateTime.now().millisecondsSinceEpoch)));
    }
    // Hearing nothing for a while means the link is dead.
    if (_sinceFrame > 8) {
      _fail(const OnlineException('connection_lost', 'Connection lost.'));
      unawaited(_transport?.close());
    }
  }

  /// Queues a steering angle; it is sent at most ~25 times a second.
  void sendSteer(double angle) {
    if (state != OnlineState.playing || !angle.isFinite) return;
    _pendingSteer = angle;
  }

  /// Leaves the room politely and closes the connection.
  Future<void> leave() async {
    if (state == OnlineState.closed) return;
    _leaving = true;
    try {
      _transport?.send(encodeClient(const LeaveMsg()));
    } catch (_) {}
    state = OnlineState.closed;
    notifyListeners();
    // Never wait on the closing handshake: a dead server would stall the
    // results screen for seconds.
    unawaited(_sub?.cancel());
    unawaited(_transport?.close());
  }

  @override
  void dispose() {
    roundResult.dispose();
    _sub?.cancel();
    unawaited(_transport?.close());
    super.dispose();
  }
}
