import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app.dart';
import '../../game/net/protocol.dart';
import '../../game/sim/skins.dart';
import '../../services/online_config.dart';
import '../../services/online_session.dart';
import '../blob_painter.dart';
import '../palette.dart';
import '../widgets.dart';
import 'game_screen.dart';
import 'menu_screen.dart' show fadeRoute;

/// Friendly text for each way joining can fail.
String onlineErrorText(OnlineException e) => switch (e.code) {
      'connect_failed' => "Can't reach the server. Check your internet connection and the server address.",
      'timeout' => 'The server took too long to answer. Try again.',
      'room_not_found' => 'No room with that code. Check the letters and try again.',
      'room_full' => 'That room is full. Try another one.',
      'server_busy' => 'The server is busy right now. Try again in a minute.',
      _ => e.message,
    };

/// Lobby for real-time online play: pick a nickname (or sign in with Google
/// Play Games), then quick-play, create a private room or join one by code.
class OnlineScreen extends StatefulWidget {
  const OnlineScreen({super.key});

  @override
  State<OnlineScreen> createState() => _OnlineScreenState();
}

class _OnlineScreenState extends State<OnlineScreen> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _code = TextEditingController();
  final TextEditingController _server = TextEditingController();
  bool _busy = false;
  bool _showServer = false;
  bool _inited = false;
  String? _error;
  String _busyLabel = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_inited) return;
    _inited = true;
    final store = Services.of(context).store;
    _name.text = store.onlineName.isNotEmpty
        ? store.onlineName
        : (store.playGamesName.isNotEmpty ? store.playGamesName : '');
    _server.text = store.serverUrl;
    _showServer = effectiveServer(store).isEmpty;
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _server.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final s = Services.of(context);
    s.fx.tap();
    setState(() {
      _busy = true;
      _busyLabel = 'Signing in...';
      _error = null;
    });
    final id = await s.auth.signIn();
    if (!mounted) return;
    if (id == null) {
      setState(() {
        _busy = false;
        _error = 'Google Play Games sign-in is not available right now. You can still play with a nickname.';
      });
      return;
    }
    await s.store.update((st) {
      st.playGamesId = id.id;
      st.playGamesName = id.name;
      if (st.onlineName.isEmpty) st.onlineName = id.name;
    });
    if (!mounted) return;
    if (_name.text.trim().isEmpty) _name.text = id.name;
    setState(() => _busy = false);
  }

  Future<void> _start(JoinMode mode) async {
    final s = Services.of(context);
    s.fx.tap();
    FocusScope.of(context).unfocus();
    final name = _name.text.trim();
    if (name.length < 2) {
      setState(() => _error = 'Pick a nickname with at least 2 characters.');
      return;
    }
    final typed = _server.text.trim();
    final url = parseServer(typed.isNotEmpty ? typed : effectiveServer(s.store));
    if (url == null) {
      setState(() {
        _showServer = true;
        _error = 'Enter the server address first, for example 192.168.1.5:8080.';
      });
      return;
    }
    String? code;
    if (mode == JoinMode.join) {
      code = _code.text.trim().toUpperCase();
      if (!RegExp(r'^[A-Z]{4}$').hasMatch(code)) {
        setState(() => _error = 'Room codes are 4 letters, like BCDF.');
        return;
      }
    }
    setState(() {
      _busy = true;
      _busyLabel = mode == JoinMode.join ? 'Joining room...' : (mode == JoinMode.create ? 'Creating room...' : 'Finding a match...');
      _error = null;
    });
    final id = await s.store.ensurePlayerId();
    await s.store.update((st) {
      st.onlineName = name;
      if (typed.isNotEmpty) st.serverUrl = typed;
    });
    final session = OnlineSession(factory: s.transport);
    try {
      await session.join(
        url,
        HelloMsg(name: name, playerId: id, skin: s.store.selectedSkin, mode: mode, code: code),
      );
    } on OnlineException catch (e) {
      session.dispose();
      if (mounted) {
        setState(() {
          _busy = false;
          _error = onlineErrorText(e);
        });
      }
      return;
    } catch (_) {
      session.dispose();
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Something went wrong. Try again.';
        });
      }
      return;
    }
    if (!mounted) {
      await session.leave();
      return;
    }
    setState(() => _busy = false);
    await Navigator.of(context).push(fadeRoute(GameScreen(level: s.store.level, online: session)));
  }

  @override
  Widget build(BuildContext context) {
    final s = Services.of(context);
    final store = s.store;
    final skin = skinById(store.selectedSkin);
    final signedIn = store.playGamesId.isNotEmpty;
    final server = effectiveServer(store);
    return Scaffold(
      key: const Key('onlineScreen'),
      body: Stack(fit: StackFit.expand, children: [
        const PaintBackground(animate: false),
        SafeArea(
          child: AnimatedBuilder(
            animation: store,
            builder: (context, _) => ListView(
              padding: const EdgeInsets.all(18),
              children: [
                Row(children: [
                  RoundIconButton(
                    key: const Key('backButton'),
                    icon: Icons.arrow_back_rounded,
                    tooltip: 'Back',
                    onTap: () {
                      s.fx.tap();
                      Navigator.of(context).pop();
                    },
                  ),
                  const SizedBox(width: 14),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text('PLAY ONLINE', style: kTitle.copyWith(fontSize: 34)),
                    ),
                  ),
                ]),
                const SizedBox(height: 16),
                GamePanel(
                  title: 'YOUR PLAYER',
                  headerColor: Palette.pink,
                  child: Column(children: [
                    Row(children: [
                      BlobAvatar(skin: skin, size: 64, mood: Mood.excited),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          key: const Key('nicknameField'),
                          controller: _name,
                          maxLength: 14,
                          textCapitalization: TextCapitalization.words,
                          enabled: !_busy,
                          style: bodyStyle(20),
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9 _.\-]'))],
                          decoration: const InputDecoration(
                            labelText: 'Nickname',
                            counterText: '',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 10),
                    if (signedIn)
                      Row(key: const Key('playGamesStatus'), children: [
                        const Icon(Icons.verified_rounded, color: Color(Palette.green)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text('Signed in with Google Play Games as ${store.playGamesName}',
                              style: bodyStyle(14)),
                        ),
                      ])
                    else
                      ChunkyButton(
                        key: const Key('signInButton'),
                        label: 'SIGN IN WITH PLAY GAMES',
                        icon: Icons.sports_esports_rounded,
                        color: Palette.cyan,
                        dark: 0xFF1474C9,
                        width: double.infinity,
                        height: 50,
                        fontSize: 16,
                        onTap: _busy ? null : _signIn,
                      ),
                    if (!signedIn)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text('Or just pick a nickname and play as a guest.',
                            style: bodyStyle(13, color: const Color(0xFF6A7393))),
                      ),
                  ]),
                ),
                const SizedBox(height: 16),
                GamePanel(
                  title: 'FIGHT!',
                  child: Column(children: [
                    ChunkyButton(
                      key: const Key('quickPlayButton'),
                      label: 'QUICK PLAY',
                      icon: Icons.bolt_rounded,
                      width: double.infinity,
                      onTap: _busy ? null : () => _start(JoinMode.quick),
                    ),
                    const SizedBox(height: 12),
                    ChunkyButton(
                      key: const Key('createRoomButton'),
                      label: 'CREATE FRIEND ROOM',
                      icon: Icons.group_add_rounded,
                      color: Palette.cyan,
                      dark: 0xFF1474C9,
                      width: double.infinity,
                      height: 54,
                      fontSize: 18,
                      onTap: _busy ? null : () => _start(JoinMode.create),
                    ),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                        child: TextField(
                          key: const Key('joinCodeField'),
                          controller: _code,
                          maxLength: 4,
                          textCapitalization: TextCapitalization.characters,
                          enabled: !_busy,
                          style: bodyStyle(22),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z]')),
                            TextInputFormatter.withFunction((o, n) => n.copyWith(text: n.text.toUpperCase())),
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Room code',
                            counterText: '',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 130,
                        child: ChunkyButton(
                          key: const Key('joinRoomButton'),
                          label: 'JOIN',
                          icon: Icons.login_rounded,
                          color: Palette.pink,
                          dark: 0xFFC92A7A,
                          height: 50,
                          fontSize: 18,
                          onTap: _busy ? null : () => _start(JoinMode.join),
                        ),
                      ),
                    ]),
                  ]),
                ),
                if (_busy)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Row(key: const Key('onlineBusy'), mainAxisAlignment: MainAxisAlignment.center, children: [
                      const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white)),
                      const SizedBox(width: 12),
                      Text(_busyLabel, style: kTitle.copyWith(fontSize: 20)),
                    ]),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Container(
                      key: const Key('onlineError'),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFEAEA),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE53950), width: 2.5),
                      ),
                      child: Row(children: [
                        const Icon(Icons.error_rounded, color: Color(0xFFE53950)),
                        const SizedBox(width: 10),
                        Expanded(child: Text(_error!, style: bodyStyle(15, color: const Color(0xFF8A1F2E)))),
                      ]),
                    ),
                  ),
                const SizedBox(height: 16),
                // Server address: hidden once a build-time default exists.
                GestureDetector(
                  key: const Key('serverToggle'),
                  onTap: () => setState(() => _showServer = !_showServer),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.dns_rounded, size: 18, color: Colors.white),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(server.isEmpty ? 'Server address needed' : 'Server: $server',
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: bodyStyle(13, color: Colors.white)),
                      ),
                    ]),
                  ),
                ),
                if (_showServer)
                  TextField(
                    key: const Key('serverField'),
                    controller: _server,
                    enabled: !_busy,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    style: bodyStyle(16),
                    decoration: InputDecoration(
                      labelText: 'Game server',
                      hintText: 'ws://192.168.1.5:8080',
                      filled: true,
                      fillColor: Colors.white,
                      border: const OutlineInputBorder(),
                      isDense: true,
                      helperText: server.isEmpty ? 'Ask whoever runs the server for this address.' : null,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}
