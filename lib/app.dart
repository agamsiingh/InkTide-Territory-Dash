import 'dart:async';

import 'package:flutter/material.dart';

import 'services/feedback.dart';
import 'services/auth_service.dart';
import 'services/local_reminder_backend.dart';
import 'services/online_session.dart';
import 'services/progress_store.dart';
import 'services/reminders.dart';
import 'ui/palette.dart';
import 'ui/screens/menu_screen.dart';
import 'ui/widgets.dart';

/// Shared app services, available below [InkTideApp].
class Services extends InheritedWidget {
  const Services({
    super.key,
    required this.store,
    required this.fx,
    required this.reminders,
    required this.auth,
    required this.transport,
    required super.child,
  });

  final ProgressStore store;
  final GameFeedback fx;
  final ReminderService reminders;
  final AuthService auth;

  /// Opens the websocket for online play (a fake in tests).
  final TransportFactory transport;

  static Services of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<Services>()!;

  @override
  bool updateShouldNotify(Services oldWidget) =>
      store != oldWidget.store || fx != oldWidget.fx || reminders != oldWidget.reminders;
}

ThemeData buildTheme() {
  const body = TextStyle(
    fontFamily: 'Fredoka',
    fontVariations: [FontVariation('wght', 600)],
    color: Color(Palette.ink),
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(Palette.cyan),
      primary: const Color(Palette.skyDeep),
      secondary: const Color(Palette.yellow),
    ),
    scaffoldBackgroundColor: const Color(Palette.sky),
    fontFamily: 'Fredoka',
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: 'Fredoka').copyWith(
          bodyMedium: body.copyWith(fontSize: 16),
          bodyLarge: body.copyWith(fontSize: 18),
          titleLarge: const TextStyle(fontFamily: 'Lilita', fontSize: 26, color: Color(Palette.ink)),
        ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.all(const Color(Palette.white)),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected)
          ? const Color(Palette.green)
          : const Color(0xFFB8C4D6)),
    ),
  );
}

class InkTideApp extends StatefulWidget {
  const InkTideApp({
    super.key,
    this.store,
    this.skipSplash = false,
    this.reminderBackend,
    this.authService,
    this.transport,
  });

  /// Injected in tests.
  final ProgressStore? store;
  final bool skipSplash;

  /// Defaults to the real on-device scheduler. Tests pass a fake.
  final ReminderBackend? reminderBackend;

  /// Google Play Games sign-in and the online socket; tests pass fakes.
  final AuthService? authService;
  final TransportFactory? transport;

  @override
  State<InkTideApp> createState() => _InkTideAppState();
}

class _InkTideAppState extends State<InkTideApp> with WidgetsBindingObserver {
  ProgressStore? _store;
  GameFeedback? _fx;
  ReminderService? _reminders;
  AuthService get _auth => widget.authService ?? (_defaultAuth ??= PlayGamesAuth());
  AuthService? _defaultAuth;
  TransportFactory get _transport => widget.transport ?? WebSocketTransport.connect;
  bool _ready = false;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _boot();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Reminders only exist while the player is away from the game.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final r = _reminders;
    if (r == null) return;
    if (state == AppLifecycleState.resumed) {
      r.onForeground();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      r.onBackground();
    }
  }

  Future<void> _boot() async {
    final started = DateTime.now();
    final store = widget.store ?? await ProgressStore.open();
    if (!mounted) return;
    setState(() => _progress = 0.4);
    final fx = GameFeedback(store);
    await fx.preload();
    if (!mounted) return;
    setState(() => _progress = 0.9);
    if (!widget.skipSplash) {
      final elapsed = DateTime.now().difference(started);
      const minSplash = Duration(milliseconds: 1400);
      if (elapsed < minSplash) await Future<void>.delayed(minSplash - elapsed);
    }
    if (!mounted) return;
    unawaited(fx.syncMusic());
    final reminders = ReminderService(store, widget.reminderBackend ?? LocalReminderBackend());
    unawaited(reminders.init());
    setState(() {
      _store = store;
      _fx = fx;
      _reminders = reminders;
      _progress = 1;
      _ready = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final Widget home = _ready
        ? Services(store: _store!, fx: _fx!, reminders: _reminders!, auth: _auth, transport: _transport, child: const MenuScreen())
        : SplashView(progress: _progress);
    return MaterialApp(
      title: 'InkTide: Territory Dash',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      builder: (context, child) {
        // Services must wrap every route, including pushed ones.
        if (!_ready) return child!;
        return Services(store: _store!, fx: _fx!, reminders: _reminders!, auth: _auth, transport: _transport, child: child!);
      },
      home: AnimatedSwitcher(
        duration: const Duration(milliseconds: 450),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        // Splash zooms past the camera while the menu settles in.
        transitionBuilder: (child, a) => FadeTransition(
          opacity: a,
          child: ScaleTransition(
            scale: Tween(begin: child is SplashView ? 1.25 : 0.94, end: 1.0).animate(a),
            child: child,
          ),
        ),
        child: home,
      ),
    );
  }
}
