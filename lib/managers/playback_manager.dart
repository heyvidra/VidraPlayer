import 'dart:async';
import 'package:flutter/widgets.dart';

import '../core/interfaces/video_player.dart';
import '../core/lifecycle/lifecycle_token.dart';
import '../core/lifecycle/safe_stream.dart';
import '../core/model/model.dart';
import '../core/player_exceptions.dart';
import '../core/state/states.dart';
import '../utils/log.dart';

/// Manages playback state and coordinates with the underlying video player.
///
/// This is an internal implementation class. SDK users should interact
/// with [PlayerController] instead.
class PlaybackManager with LifecycleTokenProvider {
  // ===============================================================
  // Dependencies & State
  // ===============================================================

  PlayerConfig _config;
  final IVideoPlayer _player;

  /// Force-clears a stuck isSeeking flag if the player never ticks close
  /// enough to the target (keyframe-sparse HLS seeks can land far away).
  Timer? _seekWatchdog;
  static const _kSeekWatchdogTimeout = Duration(seconds: 2);

  final List<StreamSubscription<dynamic>> _subscriptions = [];

  // Lifecycle flag
  bool _isDisposed = false;

  // Internal State Cache
  PlaybackLifecycleState _lifecycleState = const PlaybackLifecycleState();
  PlaybackPositionState _positionState = const PlaybackPositionState();
  ErrorState _errorState = const ErrorState();
  SwitchingState _switching = const SwitchingState();
  BufferingState _bufferingState = const BufferingState();

  // State Notifiers (for high-performance UI updates)
  late final ValueNotifier<PlaybackPositionState> positionNotifier;

  // Distilled live-ness flag. Control button rows only care whether the media
  // is live (changes ~once per load), NOT the position (changes many times a
  // second). Subscribing them to this instead of positionNotifier stops the
  // top bar / prev-next / settings rows from rebuilding on every tick.
  late final ValueNotifier<bool> isLiveNotifier;

  // Stream Controllers
  final _lifecycleCtrl = StreamController<PlaybackLifecycleState>.broadcast();
  final _positionCtrl = StreamController<PlaybackPositionState>.broadcast();
  final _errorCtrl = StreamController<ErrorState>.broadcast();
  final _switchingCtrl = StreamController<SwitchingState>.broadcast();
  final _bufferingCtrl = StreamController<BufferingState>.broadcast();

  // ===============================================================
  // Construction
  // ===============================================================

  PlaybackManager({required PlayerConfig config, required IVideoPlayer player})
    : _config = config,
      _player = player {
    positionNotifier = ValueNotifier<PlaybackPositionState>(_positionState);
    isLiveNotifier = ValueNotifier<bool>(_positionState.isLive);
    _bindPlayerStreams();
  }

  // ===============================================================
  // Stream & State Accessors
  // ===============================================================

  Stream<PlaybackLifecycleState> get lifecycleStream => _lifecycleCtrl.stream;
  Stream<PlaybackPositionState> get positionStream => _positionCtrl.stream;
  Stream<ErrorState> get errorStream => _errorCtrl.stream;
  Stream<SwitchingState> get switchingStream => _switchingCtrl.stream;
  Stream<BufferingState> get bufferingStream => _bufferingCtrl.stream;

  PlaybackLifecycleState get lifecycleState => _lifecycleState;
  PlaybackPositionState get positionState => _positionState;
  SwitchingState get switchingState => _switching;
  ErrorState get errorState => _errorState;
  BufferingState get bufferingState => _bufferingState;

  // ===============================================================
  // Initialization & Playback Control
  // ===============================================================

  /// Opens [source] on the underlying player.
  ///
  /// Returns `true` on success, `false` on failure (error already emitted).
  /// Callers MUST honour the result: on `false` the player is not playing, so
  /// committing new media/quality state or driving seek/play would diverge the
  /// UI from reality. [source] is resolved by the single authority
  /// (MediaContextState.currentSource); a null source is a load failure.
  Future<bool> initialize(VideoSource? source) async {
    final token = lifecycleToken;
    if (!token.isAlive) return false;

    // Reset error state on each initialization attempt
    _errorState = const ErrorState();
    safeEmit(_errorCtrl, _errorState, token);

    if (source == null) {
      _errorState = ErrorState(
        error: PlayerError(code: 'INIT_ERROR', message: "no playable source"),
      );
      safeEmit(_errorCtrl, _errorState, token);
      _setInitialized(false, token);
      return false;
    }
    try {
      await _player.initialize(source);

      if (!token.isAlive) return false;

      _setInitialized(true, token);
      return true;
    } catch (e, stackTrace) {
      final wrapped = ExceptionHandler.convertToPlayerException(
        e,
        context: 'initialize',
        stackTrace: stackTrace,
      );
      _errorState = ErrorState(
        error: PlayerError(
          code: wrapped.code ?? 'INIT_ERROR',
          message: wrapped.message,
          details: wrapped.details,
          timestamp: wrapped.timestamp,
          stackTrace: wrapped.stackTrace,
        ),
      );
      logger.e(_errorState.error);
      safeEmit(_errorCtrl, _errorState, token);
      // Don't leave isInitialized lying true from the previous media.
      _setInitialized(false, token);
      return false;
    }
  }

  void _setInitialized(bool value, LifecycleToken token) {
    if (_lifecycleState.isInitialized == value) return;
    _lifecycleState = _lifecycleState.copyWith(isInitialized: value);
    safeEmit(_lifecycleCtrl, _lifecycleState, token);
  }

  Future<void> play() async {
    if (_isDisposed) return;

    // Optimistic flip for instant UI feedback; reconciled against the player's
    // real isPlayingStream (see _bindPlayerStreams) and rolled back on failure.
    final previous = _lifecycleState;
    _lifecycleState = _lifecycleState.copyWith(
      isPlaying: true,
      status: PlaybackStatus.playing,
    );
    if (!_lifecycleCtrl.isClosed) {
      _lifecycleCtrl.add(_lifecycleState);
    }

    try {
      await _player.play();
    } catch (e) {
      // e.g. autoplay-blocked or player not ready — revert so the UI does not
      // get stuck showing a "playing" state that never happened.
      if (!_isDisposed) {
        _lifecycleState = previous;
        if (!_lifecycleCtrl.isClosed) {
          _lifecycleCtrl.add(_lifecycleState);
        }
      }
      logger.w('[PlaybackManager] play() failed, reverted state: $e');
    }
  }

  Future<void> pause() async {
    if (_isDisposed) return;

    final previous = _lifecycleState;
    _lifecycleState = _lifecycleState.copyWith(
      isPlaying: false,
      status: PlaybackStatus.paused,
    );
    if (!_lifecycleCtrl.isClosed) {
      _lifecycleCtrl.add(_lifecycleState);
    }

    try {
      await _player.pause();
    } catch (e) {
      if (!_isDisposed) {
        _lifecycleState = previous;
        if (!_lifecycleCtrl.isClosed) {
          _lifecycleCtrl.add(_lifecycleState);
        }
      }
      logger.w('[PlaybackManager] pause() failed, reverted state: $e');
    }
  }

  /// Propagate a runtime config change so behavior flags (e.g. [loop]) read
  /// from the live config instead of a construction-time snapshot.
  void updateConfig(PlayerConfig config) {
    _config = config;
  }

  Future<void> resetPlayer() async {
    // Old media is gone — don't let isInitialized lie true through the reopen.
    _setInitialized(false, lifecycleToken);
    await _player.reset();
  }

  Future<void> seek(Duration pos, SeekSource source) {
    final token = lifecycleToken;
    if (!token.isAlive) return Future.value();

    // Hand the NEW state to _emitPositionState and let it assign — assigning
    // _positionState first and emitting the same object trips the no-op guard
    // (next == _positionState is trivially true) and swallows the seek event.
    _emitPositionState(
      _positionState.copyWith(
        isSeeking: true,
        seekTarget: pos,
        seekSource: source,
        position: pos,
      ),
      token,
    );

    // Watchdog: the position-based completion check (below, in
    // _bindPlayerStreams) requires a tick within 800ms of the target. On
    // keyframe-sparse content the player can legitimately land further away,
    // which would leave isSeeking stuck forever (frozen progress bar /
    // spinner). Force-clear after a bounded window.
    _seekWatchdog?.cancel();
    _seekWatchdog = Timer(_kSeekWatchdogTimeout, () {
      if (_isDisposed || !_positionState.isSeeking) return;
      logger.w(
        '[PlaybackManager] Seek watchdog fired — clearing stuck isSeeking '
        '(target: ${_positionState.seekTarget})',
      );
      _emitPositionState(
        _positionState.copyWith(
          isSeeking: false,
          clearSeek: true,
          position: _player.position,
          duration: _player.duration,
        ),
        lifecycleToken,
      );
    });

    return _player.seek(pos);
  }

  /// Called by the controller after a seek gesture fully completes so the
  /// wasPlayingBeforeSeek intent doesn't leak into unrelated later logic.
  void afterSeek() {
    if (_isDisposed) return;
    if (!_lifecycleState.wasPlayingBeforeSeek) return;
    _lifecycleState = _lifecycleState.copyWith(wasPlayingBeforeSeek: false);
    if (!_lifecycleCtrl.isClosed) {
      _lifecycleCtrl.add(_lifecycleState);
    }
  }

  // ===============================================================
  // Features (Switching, Seek Prep)
  // ===============================================================

  void refreshState() {
    if (_isDisposed) return;

    if (!_lifecycleCtrl.isClosed) _lifecycleCtrl.add(_lifecycleState);
    if (!_positionCtrl.isClosed) _positionCtrl.add(_positionState);
    if (!_switchingCtrl.isClosed) _switchingCtrl.add(_switching);
    if (!_errorCtrl.isClosed) _errorCtrl.add(_errorState);
  }

  void startSwitching(String targetQualityLabel) {
    if (_isDisposed) return;

    _switching = SwitchingState(
      isSwitching: true,
      targetQualityLabel: targetQualityLabel,
    );
    if (!_switchingCtrl.isClosed) {
      _switchingCtrl.add(_switching);
    }
  }

  void endSwitching() {
    if (_isDisposed) return;

    _switching = const SwitchingState();
    if (!_switchingCtrl.isClosed) {
      _switchingCtrl.add(_switching);
    }

    // Reconcile once against ground truth. isPlayingStream reconciliation is
    // suppressed during switching (see _bindPlayerStreams) to swallow the
    // synthetic reset. Change-driven adapters (media_kit emits `playing` only
    // on change) won't re-deliver a real transition that happened inside the
    // window, so a failed post-switch play() could otherwise leave
    // lifecycle.isPlaying stale-true over a frozen frame. Close the window.
    final realPlaying = _player.isPlaying;
    if (_lifecycleState.isPlaying != realPlaying) {
      final token = lifecycleToken;
      _lifecycleState = _lifecycleState.copyWith(
        isPlaying: realPlaying,
        status: realPlaying ? PlaybackStatus.playing : PlaybackStatus.paused,
      );
      safeEmit(_lifecycleCtrl, _lifecycleState, token);
    }
  }

  void beforeSeek() {
    if (_isDisposed) return;
    _lifecycleState = _lifecycleState.copyWith(
      wasPlayingBeforeSeek: _lifecycleState.isPlaying,
    );
    if (!_lifecycleCtrl.isClosed) {
      _lifecycleCtrl.add(_lifecycleState);
    }
  }

  // ===============================================================
  // Rendering
  // ===============================================================

  Widget renderPlayer({Key? key}) {
    return _player.render(key: key);
  }

  // ===============================================================
  // Internal Stream Binding
  // ===============================================================

  void _bindPlayerStreams() {
    _subscriptions.add(
      _player.positionStream.listen((pos) {
        final token = lifecycleToken;
        if (!token.isAlive) return;

        if (_positionState.isSeeking && _positionState.seekTarget != null) {
          final delta = (pos - _positionState.seekTarget!).abs();

          // Seek completion threshold
          if (delta < const Duration(milliseconds: 800)) {
            _seekWatchdog?.cancel();
            _emitPositionState(
              _positionState.copyWith(
                isSeeking: false,
                clearSeek: true,
                position: pos,
                duration: _player.duration,
                isLive: _player.isLive,
              ),
              token,
            );
          } else {
            return;
          }
        } else {
          _emitPositionState(
            _positionState.copyWith(
              position: pos,
              duration: _player.duration,
              isLive: _player.isLive,
            ),
            token,
          );
        }
        // Loop check
        if (_config.behavior.loop &&
            _player.duration > Duration.zero &&
            pos >= _player.duration) {
          seek(Duration.zero, SeekSource.external);
          play();
        }
      }),
    );

    // Buffering is a straight pass-through of the adapter's stream (folded in
    // from the former BufferingManager, which added nothing but a class).
    _subscriptions.add(
      _player.bufferingStream.listen((state) {
        final token = lifecycleToken;
        if (!token.isAlive) return;
        _bufferingState = state;
        safeEmit(_bufferingCtrl, _bufferingState, token);
      }),
    );

    _subscriptions.add(
      _player.bufferedStream.listen((buffered) {
        final token = lifecycleToken;
        if (!token.isAlive) return;
        _emitPositionState(_positionState.copyWith(buffered: buffered), token);
      }),
    );

    _subscriptions.add(
      _player.errorStream.listen((err) {
        final token = lifecycleToken;
        if (!token.isAlive) return;

        _errorState = ErrorState(
          error: err != null
              ? PlayerError(code: err.code, message: err.message)
              : null,
        );
        safeEmit(_errorCtrl, _errorState, token);
      }),
    );

    _subscriptions.add(
      _player.videoSizeStream.listen((size) {
        final token = lifecycleToken;
        if (!token.isAlive) return;

        _lifecycleState = _lifecycleState.copyWith(
          videoWidth: size?.width,
          videoHeight: size?.height,
        );
        safeEmit(_lifecycleCtrl, _lifecycleState, token);
      }),
    );
    _subscriptions.add(
      _player.isLiveStream.listen((isLive) {
        final token = lifecycleToken;
        if (!token.isAlive) return;
        _emitPositionState(_positionState.copyWith(isLive: isLive), token);
      }),
    );

    // Reconcile lifecycle against the player's REAL playing state. The adapters
    // faithfully emit this on natural end, OS/audio-focus pause, and any
    // self-initiated pause/resume — cases the optimistic play()/pause() flips
    // alone cannot observe. Only emit on an actual change to avoid churn from
    // tick-driven adapters (fvp emits playing on every frame).
    _subscriptions.add(
      _player.isPlayingStream.listen((playing) {
        final token = lifecycleToken;
        if (!token.isAlive) return;
        if (_lifecycleState.isPlaying == playing) return;
        // During an episode/quality switch the adapter's resetAllStreams()
        // emits a synthetic playing=false. Reconciling it would produce a
        // phantom paused transition mid-switch (spurious PlaybackPaused
        // events + history saves against the already-advanced episode index).
        if (_switching.isSwitching) return;

        _lifecycleState = _lifecycleState.copyWith(
          isPlaying: playing,
          status: playing ? PlaybackStatus.playing : PlaybackStatus.paused,
        );
        safeEmit(_lifecycleCtrl, _lifecycleState, token);
      }),
    );

    // Real end-of-media signal. Drives loop restarts and PlaybackStatus.ended
    // from the player's own EOF event instead of relying solely on the
    // position>=duration-200ms heuristic (kept as fallback in the controller),
    // which can be skipped entirely when tick intervals exceed 200ms.
    _subscriptions.add(
      _player.completedStream.listen((completed) {
        final token = lifecycleToken;
        if (!token.isAlive || !completed) return;

        if (_config.behavior.loop) {
          seek(Duration.zero, SeekSource.external);
          play();
          return;
        }

        if (_lifecycleState.status == PlaybackStatus.ended) return;
        _lifecycleState = _lifecycleState.copyWith(
          isPlaying: false,
          status: PlaybackStatus.ended,
        );
        safeEmit(_lifecycleCtrl, _lifecycleState, token);
      }),
    );
  }

  void _emitPositionState(PlaybackPositionState next, LifecycleToken token) {
    if (!token.isAlive) return;

    // Callers must pass a NEW state and let this method assign it. A caller
    // that pre-assigns _positionState and emits the same object would make
    // the no-op guard below trivially true and silently swallow the event.
    assert(
      !identical(next, _positionState),
      'Pass the new state to _emitPositionState; do not pre-assign '
      '_positionState first — the no-op guard would swallow the emission.',
    );

    // No-op updates (identical position AND buffered — common when adapters
    // re-report the same buffered list per tick, or tick while paused) must
    // not fan out to every position consumer.
    if (next == _positionState) return;

    _positionState = next;
    positionNotifier.value = next;
    // Only fires listeners when live-ness actually flips (ValueNotifier is
    // value-equality gated for bool), so tick-frequency position updates that
    // leave isLive unchanged don't rebuild the control rows.
    isLiveNotifier.value = next.isLive;
    safeEmit(_positionCtrl, next, token);
  }

  // ===============================================================
  // Disposal
  // ===============================================================

  void dispose() {
    if (_isDisposed) return;
    invalidateLifecycle();
    _isDisposed = true;
    for (final s in _subscriptions) {
      s.cancel();
    }
    _subscriptions.clear();
    _seekWatchdog?.cancel();
    positionNotifier.dispose();
    isLiveNotifier.dispose();
    _lifecycleCtrl.close();
    _positionCtrl.close();
    _errorCtrl.close();
    _switchingCtrl.close();
    _bufferingCtrl.close();
  }
}
