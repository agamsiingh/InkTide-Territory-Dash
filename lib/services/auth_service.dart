import 'package:flutter/foundation.dart';
import 'package:games_services/games_services.dart';

/// Who the player is when joining online games.
class PlayerIdentity {
  const PlayerIdentity({required this.id, required this.name});
  final String id;
  final String name;
}

/// Signs the player in to Google Play Games. Everything fails soft: if the
/// game is not set up in Play Console yet (or the player cancels), callers
/// simply fall back to a guest nickname.
abstract class AuthService {
  Future<PlayerIdentity?> signIn();
}

class PlayGamesAuth implements AuthService {
  @override
  Future<PlayerIdentity?> signIn() async {
    try {
      await GamesServices.signIn();
      if (!await GamesServices.isSignedIn) return null;
      final id = await GamesServices.getPlayerID();
      final name = await GamesServices.getPlayerName();
      if (id == null || id.isEmpty) return null;
      return PlayerIdentity(id: id, name: (name == null || name.isEmpty) ? 'Player' : name);
    } catch (e) {
      debugPrint('Play Games sign-in failed: $e');
      return null;
    }
  }
}

/// No Play Games (tests, other platforms).
class NoAuth implements AuthService {
  @override
  Future<PlayerIdentity?> signIn() async => null;
}
