import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'package:vidra_player/core/adapters/base_video_player_adapter.dart';
import 'package:vidra_player/core/lifecycle/lifecycle_token.dart';
import 'package:vidra_player/core/model/model.dart';
import 'package:vidra_player/core/state/states.dart';
import 'package:vidra_player/core/player_exceptions.dart';

/// Video player adapter backed by the `video_player` package.
///
/// ### What this adapter implements:
/// - [onInitialize]: create [VideoPlayerController], call `.initialize()`,
///   attach the tick listener, and push the initial video-size event.
/// - [onReset]: remove tick listener, pause, and dispose the controller.
/// - [buildRenderWidget]: return a [VideoPlayer] widget.
///
/// Everything else (StreamControllers, stream getters, dispose lifecycle,
/// subscription management) is handled by [BaseVideoPlayerAdapter].
class VideoPlayerAdapter extends BaseVideoPlayerAdapter {
  VideoPlayerController? _controller;

  // PERFORMANCE: Cache last-seen buffered ranges to skip redundant allocations
  // on every frame tick when the buffer has not actually moved.
  List<BufferRange> _cachedBufferedRanges = [];

  // Emit a given error only once per error episode — the tick listener fires
  // ~10x/second and value.hasError stays true, so without this we'd flood the
  // error stream with duplicates every frame.
  bool _errorEmitted = false;

  // Edge-detect completion so completedStream fires once per transition
  // instead of on every tick while value.isCompleted stays true.
  bool _wasCompleted = false;

  // ── onInitialize ────────────────────────────────────────────────────────────

  @override
  Future<void> onInitialize(VideoSource source, LifecycleToken token) async {
    // Tear down any existing controller before opening a new source.
    if (_controller != null) {
      await reset();
    }

    // Reset all stream states so the UI shows a clean slate immediately.
    resetAllStreams();

    final errorCtrl = StreamController<String>.broadcast();

    // The tick listener to capture async errors during initialization before
    // the main tick listener is attached.
    void initTickListener() {
      final ctrl = _controller;
      if (ctrl != null && ctrl.value.hasError) {
        errorCtrl.add(ctrl.value.errorDescription ?? 'Unknown error');
      }
    }

    try {
      await performHlsWarmup(source, token);

      await openWithRetry(
        maxRetries: 3,
        token: token,
        open: () async {
          // Clean up previous attempt if any
          _controller?.removeListener(initTickListener);
          await _controller?.dispose();

          _controller = _buildController(source);
          _controller!.addListener(initTickListener);

          try {
            // video_player's initialize() often throws synchronously on failure
            await _controller!.initialize();
          } catch (e) {
            errorCtrl.add(e.toString());
          }
        },
        errorStream: errorCtrl.stream,
        isFatalError: (error) {
          if (error.isEmpty) return false;
          // Ignore general playback completed messages if they leak in
          if (error.contains('completed')) return false;
          return true; // FVP/video_player errors during init are generally fatal
        },
        waitForFormat: (cancelToken) => waitForFormatStable(
          source: source,
          token: token,
          cancelToken: cancelToken,
          getCurrentDuration: () => _controller?.value.duration ?? Duration.zero,
          getCurrentWidth: () => _controller?.value.size.width.toInt(),
        ),
        onRetry: (attempt, maxRetries) {
          emitBuffering(BufferingState(
            isBuffering: true,
            message: 'Retrying... ($attempt/$maxRetries)',
          ));
        },
      );
    } finally {
      emitBuffering(const BufferingState(isBuffering: false));
      // Cleanup the temporary error stream and listener
      _controller?.removeListener(initTickListener);
      await errorCtrl.close();
    }

    // Initialization succeeded!
    // Emit initial video size — available right after initialize().
    final size = _controller!.value.size;
    emitVideoSize(VideoSize(size.width.toInt(), size.height.toInt()));

    // Attach regular heartbeat updates
    _controller!.addListener(_onTick);
  }


  VideoPlayerController _buildController(VideoSource source) {
    final opts = VideoPlayerOptions(
      mixWithOthers: false,
      allowBackgroundPlayback: false,
    );
    return switch (source.type) {
      VideoSourceType.network => VideoPlayerController.networkUrl(
          Uri.parse(source.path),
          videoPlayerOptions: opts,
          httpHeaders: getHttpProxyHeaders(source) ?? const {},
        ),
      VideoSourceType.file => VideoPlayerController.file(
          File(source.path),
          videoPlayerOptions: opts,
        ),
      VideoSourceType.asset => VideoPlayerController.asset(
          source.path,
          videoPlayerOptions: opts,
        ),
    };
  }

  // ── Tick listener ──────────────────────────────────────────────────────────
  // Called on every frame by VideoPlayerController's ChangeNotifier.
  // Uses the emit* helpers from BaseVideoPlayerAdapter; each helper reads
  // lifecycleToken at call-time and guards against closed controllers.

  void _onTick() {
    // Fast-path: if the lifecycle is dead, do nothing.
    if (!lifecycleToken.isAlive) return;

    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;

    final value = ctrl.value;

    emitPosition(value.position);
    emitPlaying(value.isPlaying);
    emitBuffering(BufferingState(isBuffering: value.isBuffering));
    emitLive(isStreamLive(currentSource, value.duration));

    // Real end-of-media signal (video_player >= 2.9 sets isCompleted at EOF).
    if (value.isCompleted != _wasCompleted) {
      _wasCompleted = value.isCompleted;
      emitCompleted(_wasCompleted);
    }

    // PERFORMANCE: Only allocate a new list when buffered ranges changed.
    final newBuffered = value.buffered;
    if (_bufferedRangesChanged(newBuffered)) {
      _cachedBufferedRanges = newBuffered
          .map((e) => BufferRange(start: e.start, end: e.end))
          .toList();
      emitBuffered(_cachedBufferedRanges);
    }

    if (value.hasError) {
      if (!_errorEmitted) {
        _errorEmitted = true;
        final wrapped = ExceptionHandler.convertToPlayerException(
          value.errorDescription ?? 'Unknown error',
          context: 'video_player_tick',
        );
        emitError(PlayerError(
          code: wrapped.code ?? '',
          message: wrapped.message,
          details: wrapped.details,
          timestamp: wrapped.timestamp,
        ));
      }
    } else if (_errorEmitted) {
      _errorEmitted = false;
    }
  }

  // PERFORMANCE: Compare element-by-element without allocating new objects.
  bool _bufferedRangesChanged(List<DurationRange> newRanges) {
    if (_cachedBufferedRanges.length != newRanges.length) return true;
    for (int i = 0; i < newRanges.length; i++) {
      final cached = _cachedBufferedRanges[i];
      final current = newRanges[i];
      if (cached.start != current.start || cached.end != current.end) {
        return true;
      }
    }
    return false;
  }

  // ── onReset ────────────────────────────────────────────────────────────────

  @override
  Future<void> onReset() async {
    final ctrl = _controller;
    _controller = null;
    _cachedBufferedRanges = [];
    _errorEmitted = false;
    _wasCompleted = false;

    if (ctrl == null) return;
    try {
      ctrl.removeListener(_onTick);
      // Bounded: these platform calls run inside the switching window; a hung
      // pause()/dispose() would otherwise pin the input-blocking switching
      // overlay forever. On timeout the controller is abandoned — it is being
      // discarded anyway.
      await ctrl.pause().timeout(const Duration(seconds: 5));
      // Drain before disposing. pause() posts a native state-change
      // (isPlayingStateUpdate: false) that fvp relays into its own event
      // StreamController; fvp.dispose() closes that controller *first*
      // (streamCtl.close() before super.dispose()), so a still-pending event
      // lands on the closed controller and throws "Cannot add event after
      // closing" from a microtask we can't try/catch. This short wait lets the
      // platform-thread event arrive and deliver while the controller is still
      // open. Android keeps a larger delay: it also needs the platform layer
      // to flush pending frames before disposal.
      await Future<void>.delayed(
        Platform.isAndroid
            ? const Duration(milliseconds: 150)
            : const Duration(milliseconds: 50),
      );
      await ctrl.dispose().timeout(const Duration(seconds: 5));
    } catch (_) {
      // Ignore errors during teardown — the controller is being discarded.
    }
  }

  // ── buildRenderWidget ──────────────────────────────────────────────────────

  @override
  Widget buildRenderWidget(Key? key, BoxFit fit, Alignment alignment) {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) {
      return const SizedBox.shrink();
    }
    // Note: video_player's VideoPlayer widget does not expose fit/alignment
    // natively; wrap in FittedBox / AspectRatio if those are needed.
    return VideoPlayer(ctrl, key: key);
  }

  // ── State getters ──────────────────────────────────────────────────────────
  // These read directly from the underlying controller's synchronous state.

  @override
  Duration get duration => _controller?.value.duration ?? Duration.zero;

  @override
  Duration get position => _controller?.value.position ?? Duration.zero;

  @override
  bool get isPlaying => _controller?.value.isPlaying ?? false;

  @override
  bool get isLive => isStreamLive(currentSource, _controller?.value.duration ?? Duration.zero);

  @override
  VideoSize? get videoSize {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return null;
    final size = ctrl.value.size;
    return VideoSize(size.width.toInt(), size.height.toInt());
  }

  // ── Playback controls ──────────────────────────────────────────────────────

  // Null-safe: onReset() nulls _controller and onInitialize() rebuilds it
  // asynchronously (seconds for HLS). A loop-restart, autoplay race, or user
  // tap landing in that window must not throw a null-check crash.
  //
  // play()/pause() report the not-ready state as a Future.error instead of a
  // silent no-op: PlaybackManager flips its lifecycle optimistically and
  // relies on the throw to ROLL BACK — swallowing it would leave a stuck
  // "playing" state (and an engaged wakelock) when nothing is playing.
  @override
  Future<void> play() =>
      _controller?.play() ??
      Future.error(StateError('fvp player not ready (initializing/reset)'));

  @override
  Future<void> pause() =>
      _controller?.pause() ??
      Future.error(StateError('fvp player not ready (initializing/reset)'));

  @override
  Future<void> seek(Duration position) =>
      _controller?.seekTo(position) ?? Future.value();

  @override
  Future<void> setVolume(double volume) =>
      _controller?.setVolume(volume) ?? Future.value();

  @override
  Future<void> setPlaybackSpeed(double speed) =>
      _controller?.setPlaybackSpeed(speed) ?? Future.value();
}
