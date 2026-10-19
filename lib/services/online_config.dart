import 'progress_store.dart';

/// Server address baked in at build time:
///   flutter build appbundle --dart-define=INKTIDE_SERVER=wss://play.example.com
/// Left empty, online play asks the player (or tester) for an address.
const String kDefaultServer = String.fromEnvironment('INKTIDE_SERVER');

/// The address to connect to: the player's own setting, else the build default.
String effectiveServer(ProgressStore store) => store.serverUrl.trim().isNotEmpty ? store.serverUrl.trim() : kDefaultServer;

/// Turns user input into a websocket [Uri], or null if it is not usable.
/// Accepts ws://, wss:// and bare "host:port" (assumed ws://).
Uri? parseServer(String input) {
  var text = input.trim();
  if (text.isEmpty || text.length > 200 || text.contains(' ')) return null;
  if (!text.contains('://')) text = 'ws://$text';
  final u = Uri.tryParse(text);
  if (u == null || !u.hasAuthority || u.host.isEmpty) return null;
  if (u.scheme != 'ws' && u.scheme != 'wss') return null;
  if (u.hasPort && (u.port <= 0 || u.port > 65535)) return null;
  return u;
}

/// True for addresses that are not encrypted and not on this device/LAN.
bool isInsecureRemote(Uri u) {
  if (u.scheme == 'wss') return false;
  final h = u.host;
  if (h == 'localhost' || h == '127.0.0.1' || h == '10.0.2.2') return false;
  if (h.startsWith('192.168.') || h.startsWith('10.')) return false;
  if (RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(h)) return false;
  return true;
}
