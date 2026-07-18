import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'package:vidra_player/core/adapters/base_video_player_adapter.dart';
import 'package:vidra_player/core/lifecycle/lifecycle_token.dart';
import 'package:vidra_player/core/model/model.dart';
import 'package:vidra_player/core/state/states.dart';
import 'package:vidra_player/core/player_exceptions.dart';

/// Media player adapter backed by the `media_kit` / libmpv stack.
///
/// Compared to [VideoPlayerAdapter] (video_player + fvp):
/// - Native HLS / DASH / m3u8 support via libmpv
/// - Hardware-accelerated decoding on macOS / Windows / Linux
/// - No fvp registration required — works out of the box
///
/// Call [MediaKit.ensureInitialized] in `main()` before using this adapter.
///
/// All StreamController / stream-getter / dispose boilerplate is handled by
/// [BaseVideoPlayerAdapter]. This class only deals with media_kit specifics.
class MediaKitPlayerAdapter extends BaseVideoPlayerAdapter {
  final Player _player;
  VideoController? _videoController;

  VideoSize? _cachedVideoSize;

  /// Suppresses intermediate mpv error noise while the media is still loading.
  bool _isInitializing = false;

  MediaKitPlayerAdapter()
      : _player = Player(
          configuration: const PlayerConfiguration(title: 'VidraPlayer'),
        );

  // ── onInitialize ────────────────────────────────────────────────────────────

  @override
  Future<void> onInitialize(VideoSource source, LifecycleToken token) async {
    _isInitializing = true;
    try {
      // Push clean state so the UI does not show stale data.
      resetAllStreams();

      if (_videoController != null) {
        await reset();
      }

      // Reuse a single VideoController for the Player's whole lifetime.
      // Recreating one per initialize() (every quality/episode switch) leaks
      // the previous platform texture — VideoController has no public dispose
      // and is designed to be created once per Player (canonical media_kit
      // usage). The controller keeps rendering across open() calls.
      _videoController ??= VideoController(_player);

      // ── 1. Set all mpv properties BEFORE open() ────────────────────────────
      //   Some properties (especially demuxer-* series) must be applied before
      //   libmpv starts probing the source; changes after open() may be ignored.
      await _applyMpvProperties(source);

      // ── 2. Subscribe to player event streams ───────────────────────────────
      addSubscription(_player.stream.position.listen(_onPosition));
      addSubscription(_player.stream.playing.listen(_onPlaying));
      addSubscription(_player.stream.buffering.listen(_onBuffering));
      addSubscription(_player.stream.error.listen(_onError));
      addSubscription(_player.stream.buffer.listen(_onBuffer));
      addSubscription(_player.stream.width.listen(_onVideoSize));
      addSubscription(_player.stream.height.listen(_onVideoSize));
      addSubscription(_player.stream.duration.listen(_onDurationAvailable));
      // Real end-of-media signal from mpv (true at EOF, false on new media).
      addSubscription(_player.stream.completed.listen(emitCompleted));

      // ── 3. HLS warmup (optional preflight) ────────────────────────────────
      await performHlsWarmup(source, token);

      // ── 4. Build Media with required HTTP headers ──────────────────────────
      final media = Media(source.path, httpHeaders: getHttpProxyHeaders(source));

      // ── 5. Open with retry using base-class HLS tools ─────────────────────
      await openWithRetry(
        maxRetries: 3,
        token: token,
        open: () => _player.open(media, play: false),
        errorStream: _player.stream.error,
        isFatalError: _isFatalOpenError,
        waitForFormat: (cancelToken) => waitForFormatStable(
          source: source,
          token: token,
          cancelToken: cancelToken,
          getCurrentDuration: () => _player.state.duration,
          getCurrentWidth: () => _player.state.width,
        ),
        onRetry: (attempt, maxRetries) {
          emitBuffering(BufferingState(
            isBuffering: true,
            message: 'Retrying... ($attempt/$maxRetries)',
          ));
          // Stop player before retry to clear mpv's internal error state.
          _player.stop().catchError((_) {});
        },
      );
    } catch (e) {
      rethrow;
    } finally {
      _isInitializing = false;
    }
  }

  // ── mpv property setup ────────────────────────────────────────────────────
  // ⚠️  DO NOT modify these parameters — they are carefully tuned for HLS
  //      resilience. See the detailed comments below for reasoning.

  /// Configure all mpv runtime properties before open().
  ///
  /// All writes are wrapped in [_trySet] so a single failure does not abort
  /// the initialization flow.
  Future<void> _applyMpvProperties(VideoSource source) async {
    dynamic np;
    try {
      np = _player.platform as dynamic;
    } catch (e) {
      debugPrint('[MediaKitPlayerAdapter] Cannot access native platform: $e');
      return;
    }

    // ── General network resilience ─────────────────────────────────────────
    await _trySet(np, 'tls-verify', 'no');
    await _trySet(np, 'network-timeout', '15');
    await _trySet(np, 'reconnect-on-error', 'yes');
    await _trySet(np, 'reconnect-on-http-error', '4xx,5xx');
    await _trySet(np, 'cache', 'yes');
    await _trySet(np, 'cache-secs', '30');
    await _trySet(np, 'demuxer-readahead-secs', '20');

    if (isM3u8(source.path)) {
      // ── HLS / m3u8 specific configuration ─────────────────────────────────
      //
      // Root problem: libmpv/lavf defaults to probing only the first TS
      // segment and immediately reports duration, leading to duration =
      // single-segment length (typically 4–10 s) instead of full VOD length.
      //
      // Fix strategy:
      //   1. Increase probe size/duration so lavf has time to traverse the
      //      full playlist.
      //   2. Use prefetch-playlist to pre-fetch segments and help mpv build a
      //      complete index.
      //   3. demuxer-lavf-o writes one key=value at a time (lavf does NOT
      //      support comma-separated multi-option strings).
      //   4. hls-bitrate=max ensures we load the highest-bitrate variant whose
      //      playlist is most complete.
      //   5. _waitHlsDurationStable (in base class) confirms stability via the
      //      two-phase polling algorithm.

      // Increase probe size (64 MB) and duration (30 s)
      await _trySet(np, 'demuxer-lavf-probsize', '67108864');
      await _trySet(np, 'demuxer-lavf-analyzeduration', '30');

      // Note: demuxer-lavf-o accepts exactly ONE key=value per call.
      //       Additional options must use demuxer-lavf-o-append.
      await _trySet(np, 'demuxer-lavf-o', 'strict=-2');
      await _trySet(np, 'demuxer-lavf-o-append', 'reconnect=1');
      await _trySet(np, 'demuxer-lavf-o-append', 'reconnect_at_eof=1');
      await _trySet(np, 'demuxer-lavf-o-append', 'reconnect_streamed=1');
      await _trySet(np, 'demuxer-lavf-o-append', 'reconnect_delay_max=5');

      // Allow loading relative paths and cross-origin m3u8 sub-playlists
      await _trySet(np, 'load-unsafe-playlists', 'yes');

      // Prefetch subsequent segments while the current one plays;
      // also assists mpv in building a complete segment index
      await _trySet(np, 'prefetch-playlist', 'yes');

      // Select the highest-bitrate variant to get the most complete index
      await _trySet(np, 'hls-bitrate', 'max');
    }
  }

  /// Safely write a single mpv property; log and continue on failure.
  Future<void> _trySet(dynamic np, String key, String value) async {
    try {
      await np.setProperty(key, value);
    } catch (e) {
      debugPrint(
        '[MediaKitPlayerAdapter] setProperty($key=$value) failed: $e',
      );
    }
  }


  // ── Fatal-error predicate ──────────────────────────────────────────────────

  /// Returns `true` for errors that indicate the current open attempt has
  /// failed and a retry is warranted.
  ///
  /// Returns `false` for mpv lifecycle signals and transient noise that mpv
  /// handles automatically (e.g. HLS segment 404).
  bool _isFatalOpenError(String error) {
    if (error.isEmpty) return false;

    // mpv normal lifecycle signals — not errors
    const normalSignals = ['End of file', 'Interrupted by signal', 'Exiting'];
    if (normalSignals.any((p) => error.contains(p))) return false;

    // HLS segment-switch 404 — mpv auto-retries these
    if (error.contains('HTTP error 404')) return false;

    // Patterns that mean "this open attempt is unrecoverable"
    const fatalPatterns = [
      'Failed to open', // DNS failure, connection refused
      'Connection refused',
      'No such file',
      'HTTP error 403', // Auth failure (retry rarely helps, but kept for completeness)
      'HTTP error 5', // 5xx server errors — worth retrying
      'playback failed',
    ];
    return fatalPatterns.any(
      (p) => error.toLowerCase().contains(p.toLowerCase()),
    );
  }

  // ── Event handlers ────────────────────────────────────────────────────────

  void _onPosition(Duration pos) => emitPosition(pos);

  void _onDurationAvailable(Duration dur) {
    if (isStreamLive(currentSource, dur)) {
      emitLive(true);
      return;
    }
    emitLive(false);
    // Refresh the position stream so the UI progress bar picks up the new
    // total duration from the same tick.
    emitPosition(_player.state.position);
  }

  void _onPlaying(bool playing) => emitPlaying(playing);

  void _onBuffering(bool buffering) =>
      emitBuffering(BufferingState(isBuffering: buffering));

  void _onError(String error) {
    if (error.isEmpty) return;

    // mpv normal lifecycle signals
    const ignoredPatterns = [
      'End of file',
      'Interrupted by signal',
      'Exiting',
      'HTTP error 404', // HLS segment-switch — mpv auto-retries
    ];
    if (ignoredPatterns.any((p) => error.contains(p))) return;

    debugPrint('[MediaKitPlayerAdapter] error: $error');

    // During initialization: openWithRetry's error stream listener handles
    // retry logic. Don't surface intermediate errors to the UI.
    if (_isInitializing) return;

    final mapped = _mapError(error);
    emitError(PlayerError(
      code: mapped.code ?? 'MEDIA_KIT_ERROR',
      message: mapped.message,
      details: error,
    ));
  }

  PlayerException _mapError(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('500') || lower.contains('server error')) {
      return NetworkException(
        'This video source is temporarily unavailable.',
        code: 'SERVER_ERROR',
        statusCode: 500,
      );
    }
    if (lower.contains('timeout') || lower.contains('connection refused')) {
      return NetworkException(
        'Connection timed out. Please check your network.',
        code: 'TIMEOUT',
      );
    }
    if (lower.contains('403') || lower.contains('forbidden')) {
      return NetworkException(
        'Access denied by the video provider.',
        code: 'FORBIDDEN',
        statusCode: 403,
      );
    }
    if (lower.contains('404') || lower.contains('not found')) {
      return NetworkException(
        'The video file was not found on the server.',
        code: 'NOT_FOUND',
        statusCode: 404,
      );
    }
    return PlayerException('This video source is temporarily unavailable.');
  }

  /// media_kit's buffer stream emits the ABSOLUTE timestamp of the buffered
  /// endpoint (mpv `demuxer-cache-time`). The progress-bar painter treats
  /// [BufferRange] as absolute timeline coordinates, so anchor the range at the
  /// origin — matching the fvp adapter — instead of the playhead. Anchoring at
  /// the playhead made the buffered bar start at the thumb and hide everything
  /// already buffered before the current position.
  void _onBuffer(Duration buffered) {
    final duration = _player.state.duration;
    var end = buffered;
    if (end < Duration.zero) return;
    if (duration > Duration.zero && end > duration) end = duration;
    emitBuffered([BufferRange(start: Duration.zero, end: end)]);
  }

  void _onVideoSize(dynamic _) {
    final w = _player.state.width;
    final h = _player.state.height;
    if (w != null && h != null && w > 0 && h > 0) {
      final size = VideoSize(w, h);
      // Only emit when the size has actually changed (avoid redundant rebuilds).
      if (_cachedVideoSize?.width != size.width ||
          _cachedVideoSize?.height != size.height) {
        _cachedVideoSize = size;
        emitVideoSize(size);
      }
    }
  }

  // ── onReset ────────────────────────────────────────────────────────────────

  @override
  Future<void> onReset() async {
    // Note: BaseVideoPlayerAdapter cancels all subscriptions (added via
    // addSubscription) BEFORE calling onReset, so we never need to cancel
    // them here.
    //
    // _videoController is intentionally KEPT: it is bound to the Player for
    // its whole lifetime and reused across open() calls (see onInitialize).
    _cachedVideoSize = null;

    try {
      await _player.stop();
    } catch (_) {}
  }

  // ── buildRenderWidget ──────────────────────────────────────────────────────

  @override
  Widget buildRenderWidget(Key? key, BoxFit fit, Alignment alignment) {
    final ctrl = _videoController;
    if (ctrl == null) return const SizedBox.shrink();
    return Video(
      key: key,
      controller: ctrl,
      fit: fit,
      alignment: alignment,
      // Equivalent to NoVideoControls, but typed — media_kit declares that
      // constant as dynamic, which strict-casts rejects.
      controls: (state) => const SizedBox.shrink(),
    );
  }

  // ── State getters ──────────────────────────────────────────────────────────

  @override
  VideoSize? get videoSize {
    final w = _player.state.width;
    final h = _player.state.height;
    if (w == null || h == null || w == 0 || h == 0) return null;
    return VideoSize(w, h);
  }

  @override
  Duration get duration => _player.state.duration;

  @override
  Duration get position => _player.state.position;

  @override
  bool get isPlaying => _player.state.playing;

  @override
  bool get isLive => isStreamLive(currentSource, _player.state.duration);

  // ── Playback controls ──────────────────────────────────────────────────────

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  /// media_kit volume range: 0.0–100.0; IVideoPlayer contract: 0.0–1.0.
  @override
  Future<void> setVolume(double volume) =>
      _player.setVolume(volume.clamp(0.0, 1.0) * 100.0);

  @override
  Future<void> setPlaybackSpeed(double speed) => _player.setRate(speed);

  // ── dispose ────────────────────────────────────────────────────────────────
  // Extends the base dispose to also clean up the Player instance itself,
  // which is owned by this adapter.

  @override
  Future<void> dispose() async {
    await super.dispose(); // handles lifecycle invalidation + subscriptions + controllers
    try {
      await _player.dispose();
    } catch (_) {}
  }
}
