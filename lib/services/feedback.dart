import 'dart:async';

import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'progress_store.dart';

enum Sfx {
  capture('capture.ogg', 0.8),
  death('death.ogg', 0.9),
  kill('kill.ogg', 0.8),
  click('click.ogg', 0.6),
  countdown('countdown.ogg', 0.7),
  go('go.ogg', 0.8),
  win('win.ogg', 0.9),
  lose('lose.ogg', 0.8),
  unlock('unlock.ogg', 0.8),
  trailTick('trail_tick.ogg', 0.35, 90),
  trailStart('trail_start.wav', 0.5, 350),
  bump('bump.wav', 0.85),
  coin('coin.wav', 0.7, 55),
  levelUp('levelup.wav', 0.85),
  achievement('achievement.wav', 0.8),
  claim('claim.wav', 0.8, 120),
  countryComplete('country_complete.wav', 0.9),
  gem('gem.wav', 0.75, 60),
  power('power.wav', 0.9),
  bonus('bonus.wav', 0.9),
  capsuleOpen('capsule_open.wav', 0.9),
  meterTick('meter_tick.wav', 0.5, 60);

  const Sfx(this.file, this.volume, [this.minGapMs = 70]);
  final String file;
  final double volume;

  /// Minimum time between two plays of this sound (avoids stacking).
  final int minGapMs;
}

/// Sound, music and haptics, gated by user settings. Audio failures never
/// crash the game. Set [enabled] to false in tests.
class GameFeedback {
  GameFeedback(this.store);

  final ProgressStore store;
  static bool enabled = true;

  /// Music level at 100% of the music volume setting.
  static const double musicVolume = 0.45;
  static const double _duckedVolume = 0.14;
  static const _pooled = {
    Sfx.capture: 3,
    Sfx.kill: 3,
    Sfx.click: 2,
    Sfx.trailTick: 3,
    Sfx.coin: 3,
    Sfx.gem: 2,
  };
  static const int _voicesPerSfx = 2;
  static const int _maxFallbackPlayers = 6;
  static final Stopwatch _clock = Stopwatch()..start();

  bool _loaded = false;
  bool _disposed = false;
  bool _musicPlaying = false;
  bool _ducked = false;
  final Map<Sfx, int> _lastPlayed = {};

  // Low-latency AudioPools for frequent sounds, bounded by [_pooled].
  final Map<Sfx, AudioPool> _pools = {};
  final Map<Sfx, int> _poolActive = {};
  final Map<Sfx, int> _poolDurMs = {};

  // Small rings of low-latency players used for pitch-shifted plays.
  final Map<Sfx, List<AudioPlayer>> _voices = {};
  final Map<Sfx, int> _voiceNext = {};
  final Set<Sfx> _voicesPending = {};
  int _fallbackActive = 0;

  double _musicVol = 0;
  Timer? _fadeTimer;
  Completer<void>? _fadeDone;

  static final AudioContext _ctx =
      AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers).build();

  bool get _canPlay => enabled && !_disposed && store.sound;

  Future<void> preload() async {
    if (!enabled || _loaded || _disposed) return;
    try {
      await FlameAudio.audioCache
          .loadAll([...Sfx.values.map((s) => s.file), 'music_loop.ogg']);
      await FlameAudio.bgm.initialize();
      _loaded = true;
      unawaited(_warmUp());
    } catch (e) {
      debugPrint('Audio preload failed: $e');
    }
  }

  Future<void> _warmUp() async {
    for (final e in _pooled.entries) {
      if (_disposed) return;
      try {
        final pool =
            await FlameAudio.createPool(e.key.file, maxPlayers: e.value);
        if (_disposed) {
          unawaited(pool.dispose().catchError((_) {}));
          return;
        }
        _pools[e.key] = pool;
        final d = await pool
            .getDuration()
            .timeout(const Duration(seconds: 2), onTimeout: () => null);
        final ms = d?.inMilliseconds ?? 0;
        if (ms > 0) _poolDurMs[e.key] = ms.clamp(60, 2000);
      } catch (err) {
        debugPrint('pool ${e.key.file} failed: $err');
      }
      await _ensureVoices(e.key);
    }
  }

  Future<void> _ensureVoices(Sfx s) async {
    if (_voices.containsKey(s) || !_voicesPending.add(s)) return;
    final made = <AudioPlayer>[];
    try {
      for (var i = 0; i < _voicesPerSfx; i++) {
        final p = AudioPlayer()..audioCache = FlameAudio.audioCache;
        made.add(p);
        await p.setPlayerMode(PlayerMode.lowLatency);
        await p.setAudioContext(_ctx);
        await p.setReleaseMode(ReleaseMode.stop);
        await p.setSource(AssetSource(s.file));
      }
      if (_disposed) throw StateError('disposed');
      _voices[s] = made;
    } catch (e) {
      for (final p in made) {
        unawaited(p.dispose().catchError((_) {}));
      }
      if (!_disposed) debugPrint('voices ${s.file} failed: $e');
    } finally {
      _voicesPending.remove(s);
    }
  }

  /// Plays [s]. [rate] shifts pitch/speed (0.5..2), [volumeScale] scales the
  /// sound's base volume. Never throws.
  void play(Sfx s, {double rate = 1.0, double volumeScale = 1.0}) {
    if (!_canPlay) return;
    final now = _clock.elapsedMilliseconds;
    final last = _lastPlayed[s];
    if (last != null && now - last < s.minGapMs) return;
    _lastPlayed[s] = now;
    final r = rate.isFinite ? rate.clamp(0.5, 2.0).toDouble() : 1.0;
    final vs = volumeScale.isFinite ? volumeScale.clamp(0.0, 2.0) : 1.0;
    final vol = (s.volume * vs * store.sfxVolume).clamp(0.0, 1.0).toDouble();
    if (vol <= 0.001) return;
    if ((r - 1).abs() > 0.02) {
      final voices = _voices[s];
      if (voices != null) {
        _playVoice(s, voices, vol, r);
        return;
      }
      if (_loaded) unawaited(_ensureVoices(s));
    }
    final pool = _pools[s];
    if (pool != null) {
      _playPool(s, pool, vol);
    } else {
      _playFallback(s, vol);
    }
  }

  void _playVoice(Sfx s, List<AudioPlayer> voices, double vol, double rate) {
    final i = _voiceNext[s] ?? 0;
    _voiceNext[s] = (i + 1) % voices.length;
    final p = voices[i];
    final preRate = defaultTargetPlatform == TargetPlatform.android;
    () async {
      try {
        await p.stop();
        await p.setVolume(vol);
        if (preRate) await p.setPlaybackRate(rate);
        await p.resume();
        if (!preRate) await p.setPlaybackRate(rate);
      } catch (e) {
        debugPrint('pitched sfx failed: $e');
      }
    }();
  }

  void _playPool(Sfx s, AudioPool pool, double vol) {
    final active = _poolActive[s] ?? 0;
    if (active >= (_pooled[s] ?? 1)) return;
    _poolActive[s] = active + 1;
    () async {
      try {
        await pool.start(volume: vol);
      } catch (e) {
        debugPrint('pooled sfx failed: $e');
      } finally {
        Timer(Duration(milliseconds: (_poolDurMs[s] ?? 400) + 40), () {
          _poolActive[s] = ((_poolActive[s] ?? 1) - 1).clamp(0, 99);
        });
      }
    }();
  }

  void _playFallback(Sfx s, double vol) {
    if (_fallbackActive >= _maxFallbackPlayers) return;
    _fallbackActive++;
    () async {
      try {
        await FlameAudio.play(s.file, volume: vol);
      } catch (e) {
        debugPrint('sfx failed: $e');
      } finally {
        Timer(const Duration(milliseconds: 900), () {
          if (_fallbackActive > 0) _fallbackActive--;
        });
      }
    }();
  }

  double get _musicTarget => (_ducked ? _duckedVolume : musicVolume) * store.musicVolume;

  /// Applies a changed music volume setting immediately.
  Future<void> applyMusicVolume() async {
    if (!enabled || _disposed || !_musicPlaying) return;
    await _fadeTo(_musicTarget, 120);
  }

  Future<void> syncMusic() async {
    if (!enabled || _disposed) return;
    try {
      if (store.music && !_musicPlaying) {
        _cancelFade();
        _musicVol = 0;
        await FlameAudio.bgm.play('music_loop.ogg', volume: 0);
        _musicPlaying = true;
        if (_disposed) return;
        await _fadeTo(_musicTarget, 900);
      } else if (!store.music && _musicPlaying) {
        _musicPlaying = false;
        _cancelFade();
        await FlameAudio.bgm.stop();
      }
    } catch (e) {
      debugPrint('music failed: $e');
    }
  }

  Future<void> pauseMusic() async {
    if (!enabled || !_musicPlaying || _disposed) return;
    try {
      await FlameAudio.bgm.pause();
    } catch (_) {}
  }

  Future<void> resumeMusic() async {
    if (!enabled || !_musicPlaying || !store.music || _disposed) return;
    try {
      await FlameAudio.bgm.resume();
    } catch (_) {}
  }

  /// Temporarily lowers the music (e.g. on win/lose/death).
  Future<void> duckMusic() async {
    if (!enabled || _disposed) return;
    _ducked = true;
    if (_musicPlaying) await _fadeTo(_musicTarget, 260);
  }

  /// Restores the music volume after [duckMusic].
  Future<void> restoreMusic() async {
    if (!enabled || _disposed) return;
    _ducked = false;
    if (_musicPlaying) await _fadeTo(_musicTarget, 700);
  }

  void _cancelFade() {
    _fadeTimer?.cancel();
    _fadeTimer = null;
    final done = _fadeDone;
    _fadeDone = null;
    if (done != null && !done.isCompleted) done.complete();
  }

  Future<void> _fadeTo(double target, int ms) {
    _cancelFade();
    final from = _musicVol;
    if ((target - from).abs() < 0.005) {
      _setMusicVolume(target);
      return Future.value();
    }
    final done = _fadeDone = Completer<void>();
    final watch = Stopwatch()..start();
    _fadeTimer = Timer.periodic(const Duration(milliseconds: 40), (t) {
      final k = (watch.elapsedMilliseconds / ms).clamp(0.0, 1.0);
      final e = k * k * (3 - 2 * k);
      _setMusicVolume(from + (target - from) * e);
      if (k >= 1) _cancelFade();
    });
    return done.future;
  }

  void _setMusicVolume(double v) {
    _musicVol = v;
    try {
      FlameAudio.bgm.audioPlayer.setVolume(v).catchError((_) {});
    } catch (_) {}
  }

  void tap() {
    play(Sfx.click);
    if (store.haptics && enabled) HapticFeedback.selectionClick();
  }

  void hapticLight() {
    if (store.haptics && enabled) HapticFeedback.lightImpact();
  }

  void hapticHeavy() {
    if (store.haptics && enabled) HapticFeedback.heavyImpact();
  }

  /// Releases pooled players and stops music. Safe to call more than once.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _cancelFade();
    if (!enabled) return;
    final pools = _pools.values.toList();
    final voices = _voices.values.expand((v) => v).toList();
    _pools.clear();
    _voices.clear();
    try {
      if (_musicPlaying) await FlameAudio.bgm.stop();
    } catch (_) {}
    _musicPlaying = false;
    for (final p in pools) {
      try {
        await p.dispose();
      } catch (_) {}
    }
    for (final p in voices) {
      try {
        await p.dispose();
      } catch (_) {}
    }
  }
}
