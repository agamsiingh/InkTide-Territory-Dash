import 'dart:io';

import '../lib/lobby.dart';
import '../lib/ws_server.dart';

/// InkTide room server.
///   dart run bin/server.dart            (PORT env var, default 8080)
///   dart compile exe bin/server.dart -o inktide_server   (single binary)
///
/// Optional environment variables: PORT, ROUND_SECONDS (210), WIN_PERCENT (50),
/// TARGET_PLAYERS (8), ARENA_SIZE (80), MAX_HUMANS (8).
Future<void> main(List<String> args) async {
  final env = Platform.environment;
  int i(String k, int d) => int.tryParse(env[k] ?? '') ?? d;
  double dbl(String k, double d) => double.tryParse(env[k] ?? '') ?? d;
  const base = ServerConfig();
  final config = ServerConfig(
    arenaSize: i('ARENA_SIZE', base.arenaSize).clamp(40, 160),
    targetPlayers: i('TARGET_PLAYERS', base.targetPlayers).clamp(2, 16),
    maxHumans: i('MAX_HUMANS', base.maxHumans).clamp(1, 16),
    roundSeconds: dbl('ROUND_SECONDS', base.roundSeconds).clamp(20.0, 1800.0),
    winPercent: dbl('WIN_PERCENT', base.winPercent).clamp(20.0, 95.0),
  );
  final server = GameServer(Lobby(config: config));
  await server.start(port: i('PORT', 8080));
  stdout.writeln('InkTide server listening on :${server.port}  (GET /health)  '
      'round ${config.roundSeconds.round()}s / win ${config.winPercent.round()}%');
  ProcessSignal.sigint.watch().listen((_) async {
    await server.stop();
    exit(0);
  });
}
