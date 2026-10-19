import 'dart:async';
import 'dart:io';

import 'lobby.dart';

class _WsConn implements ClientConn {
  _WsConn(this.socket);
  final WebSocket socket;

  @override
  void send(String text) {
    if (socket.readyState == WebSocket.open) socket.add(text);
  }

  @override
  void close() => socket.close();
}

/// WebSocket front-end for [Lobby]. `GET /health` answers 200 for hosting
/// platforms; any WebSocket upgrade becomes a player connection.
class GameServer {
  GameServer(this.lobby, {this.maxConnections = 1500});

  final Lobby lobby;
  final int maxConnections;
  HttpServer? _http;
  final Set<WebSocket> _sockets = {};
  Timer? _timer;
  final Stopwatch _clock = Stopwatch();
  Duration _last = Duration.zero;

  int get port => _http?.port ?? 0;

  /// [autoTick] false lets tests step the rooms by hand with `lobby.tick`.
  Future<void> start({String host = '0.0.0.0', int port = 8080, bool autoTick = true}) async {
    final http = await HttpServer.bind(host, port);
    _http = http;
    _clock.start();
    if (autoTick) {
      _timer = Timer.periodic(const Duration(milliseconds: 33), (_) {
        final now = _clock.elapsed;
        var dt = (now - _last).inMicroseconds / 1e6;
        _last = now;
        if (dt > 0.1) dt = 0.1;
        lobby.tick(dt);
      });
    }
    http.listen(_onRequest, onError: (_) {});
  }

  /// Stops accepting players and says goodbye to everyone connected.
  Future<void> stop() async {
    _timer?.cancel();
    await _http?.close(force: true);
    for (final s in _sockets.toList()) {
      try {
        await s.close(WebSocketStatus.goingAway, 'server stopping');
      } catch (_) {}
    }
    _sockets.clear();
  }

  Future<void> _onRequest(HttpRequest req) async {
    try {
      if (WebSocketTransformer.isUpgradeRequest(req)) {
        if (lobby.connections >= maxConnections) {
          req.response.statusCode = HttpStatus.serviceUnavailable;
          await req.response.close();
          return;
        }
        final socket = await WebSocketTransformer.upgrade(req);
        socket.pingInterval = const Duration(seconds: 15);
        _attach(socket);
        return;
      }
      if (req.uri.path == '/health') {
        req.response
          ..statusCode = HttpStatus.ok
          ..write('ok rooms=${lobby.rooms.length} players=${lobby.humans}');
      } else {
        req.response.statusCode = HttpStatus.notFound;
      }
      await req.response.close();
    } catch (_) {
      try {
        await req.response.close();
      } catch (_) {}
    }
  }

  void _attach(WebSocket socket) {
    final conn = _WsConn(socket);
    _sockets.add(socket);
    lobby.connect(conn);
    // A client that never joins a room is dropped.
    final hello = Timer(const Duration(seconds: 10), () {
      if (!lobby.isSeated(conn)) conn.close();
    });
    socket.listen(
      (data) => lobby.onFrame(conn, data),
      onDone: () {
        hello.cancel();
        _sockets.remove(socket);
        lobby.disconnect(conn);
      },
      onError: (_) {
        hello.cancel();
        _sockets.remove(socket);
        lobby.disconnect(conn);
      },
      cancelOnError: true,
    );
  }
}
