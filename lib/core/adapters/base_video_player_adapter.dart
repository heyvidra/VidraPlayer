import 'dart:async';

import 'package:flutter/material.dart';

import '../interfaces/video_player.dart';
import '../lifecycle/lifecycle_token.dart';
import '../lifecycle/safe_stream.dart';
import '../model/model.dart';
import '../player_exceptions.dart';
import '../state/states.dart';
import '../../utils/network_resilience.dart';

// ── Retry concurrency token ────────────────────────────────────────────────────
// Shared by [BaseVideoPlayerAdapter._raceSuccessOrError] and the duration-
// stable wait loops so that any side can cancel the other immediately.

/// Result of a single open-with-retry attempt.
enum OpenResult { success, failure }

/// Abstract base class for all video player adapters.
///
/// ## What this handles for you (boilerplate-free):
/// - Six [StreamController]s (position, playing, buffering, error, buffered, videoSize)
/// - All corresponding [Stream] getters required by [IVideoPlayer]
/// - [LifecycleTokenProvider] mixin (token management, invalidation)
/// - [addSubscription] / subscription cancellation on [reset]
/// - [dispose] skeleton: invalidates lifecycle → calls [onReset] → closes controllers
/// - Typed `emit*` helpers that guard against closed controllers / dead tokens
/// - [resetAllStreams] to push clean initial state into all streams at once
/// - HLS duration-stability detection and open-with-retry helpers (see below)
///
/// ## What you MUST implement in your adapter:
/// ```dart
/// // 1. Create your player, wire events via emit* helpers.
/// @override
/// Future<void> onInitialize(VideoSource source) async { ... }
///
/// // 2. Release adapter-specific resources.
/// //    Subscriptions added via addSubscription are already cancelled.
/// @override
/// Future<void> onReset() async { ... }
///
/// // 3. Return the widget that renders video frames.
/// @override
/// Widget buildRenderWidget(Key? key, BoxFit fit, Alignment alignment);
/// ```
///
/// ## What you SHOULD implement (source-specific):
/// - [duration], [position], [isPlaying], [videoSize]
///
/// ## HLS open-with-retry helpers (optional):
/// If your adapter's underlying player does NOT throw synchronously on open
/// failure (errors arrive via a separate stream), use the provided tools:
///
/// ```dart
/// // Inside onInitialize, after subscribing to the player's error stream:
/// await openWithRetry(
///   maxRetries: 3,
///   open: () => _player.open(media),
///   errorStream: _player.stream.error,
///   isFatalError: _isFatalOpenError,
///   waitForFormat: (cancelToken) => waitForFormatStable(
///     source: source,
///     cancelToken: cancelToken,
///     getCurrentDuration: () => _player.state.duration,
///   ),
/// );
/// ```
///
/// ## Example minimal adapter:
/// ```dart
/// class MyAdapter extends BaseVideoPlayerAdapter {
///   MyPlayer? _player;
///
///   @override
///   Future<void> onInitialize(VideoSource source) async {
///     _player = MyPlayer();
///     await _player!.open(source.path);
///     addSubscription(_player!.positionStream.listen(emitPosition));
///     addSubscription(_player!.playingStream.listen(emitPlaying));
///   }
///
///   @override
///   Future<void> onReset() async { await _player?.stop(); _player = null; }
///
///   @override
///   Widget buildRenderWidget(Key? key, BoxFit fit, Alignment alignment) =>
///       PlayerView(controller: _player!, key: key);
///
///   @override Duration get duration => _player?.duration ?? Duration.zero;
///   @override Duration get position => _player?.position ?? Duration.zero;
///   @override bool get isPlaying => _player?.isPlaying ?? false;
///   @override VideoSize? get videoSize => null;
/// }
/// ```
abstract class BaseVideoPlayerAdapter
    with LifecycleTokenProvider
    implements IVideoPlayer {
  // ── Stream controllers ─────────────────────────────────────────────────────
  // All are broadcast so multiple UI widgets can listen simultaneously.
  // Closed in [dispose] — no external holder can leak them.

  final StreamController<Duration> _positionCtrl =
      StreamController<Duration>.broadcast();
  final StreamController<bool> _playingCtrl =
      StreamController<bool>.broadcast();
  final StreamController<BufferingState> _bufferingCtrl =
      StreamController<BufferingState>.broadcast();
  final StreamController<PlayerError?> _errorCtrl =
      StreamController<PlayerError?>.broadcast();
  final StreamController<List<BufferRange>> _bufferedCtrl =
      StreamController<List<BufferRange>>.broadcast();
  final StreamController<VideoSize?> _videoSizeCtrl =
      StreamController<VideoSize?>.broadcast();
  final StreamController<bool> _isLiveCtrl = StreamController<bool>.broadcast();
  final StreamController<bool> _completedCtrl =
      StreamController<bool>.broadcast();

  // ── Protected state ───────────────────────────────────────────────────────
  @protected
  VideoSource? currentSource;

  // Permanent kill switch. A freshly-minted lifecycleToken is alive by design
  // (its generation matches the current one), so after dispose() the token
  // checks alone cannot stop a stale retry/poll loop — this flag can.
  bool _isDisposed = false;

  /// Whether [dispose] has run. Retry/poll loops check this alongside their
  /// captured token so they bail out permanently after teardown.
  @protected
  bool get isDisposed => _isDisposed;

  // ── Subscription tracking ──────────────────────────────────────────────────
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  // ── Template methods ───────────────────────────────────────────────────────

  /// Initialize the underlying player for [source].
  ///
  /// Called by [initialize]. Wire up player events via [addSubscription] +
  /// `emit*` helpers. Throw on unrecoverable error.
  ///
  /// [token] is captured once for this initialization scope. Pass it to
  /// [openWithRetry] / [waitForFormatStable] / [performHlsWarmup] and check
  /// `token.isAlive` after your own awaits so a later initialize()/dispose()
  /// cancels this attempt instead of two open loops fighting over the player.
  @protected
  Future<void> onInitialize(VideoSource source, LifecycleToken token);

  /// Release adapter-specific resources (stop player, free handles, etc.).
  ///
  /// Called by both [reset] and [dispose]. All subscriptions previously
  /// added via [addSubscription] are already cancelled before this runs.
  @protected
  Future<void> onReset();

  /// Return the widget that renders video frames for this adapter.
  ///
  /// Called by [render]. Return [SizedBox.shrink] when not yet ready.
  @protected
  Widget buildRenderWidget(Key? key, BoxFit fit, Alignment alignment);

  // ── IVideoPlayer: lifecycle ────────────────────────────────────────────────

  @override
  Future<void> initialize(VideoSource source) async {
    // 1. Invalidate any existing initialization attempts or retry loops.
    //    This is CRITICAL: without this, if another initialize() is called while
    //    the previous one is in a back-off delay, they will BOTH keep running,
    //    interfering with each other's state and causing a "infinite" retry cycle.
    invalidateLifecycle();

    // Capture ONE token for this whole init scope. A later initialize() or
    // dispose() advances the generation, killing this local — so any loop
    // that threads it (openWithRetry / pollers / warmup) stops on its next
    // check instead of re-minting an always-alive token at each call site.
    final token = lifecycleToken;
    currentSource = source;
    await onInitialize(source, token);
  }

  @override
  Future<void> reset() async {
    await _cancelAndClearSubscriptions();
    await onReset();
  }

  @override
  Future<void> dispose() async {
    // 0. Permanent kill switch for retry/poll loops (survives token re-minting).
    _isDisposed = true;
    // 1. Invalidate lifecycle token — all pending safeEmit calls become no-ops.
    invalidateLifecycle();
    // 2. Cancel subscriptions + release adapter resources.
    await _cancelAndClearSubscriptions();
    await onReset();
    // 3. Close stream controllers LAST so no stray emit can slip through.
    await _closeAllControllers();
  }

  // ── IVideoPlayer: rendering ────────────────────────────────────────────────

  @override
  Widget render({
    Key? key,
    BoxFit fit = BoxFit.contain,
    Alignment alignment = Alignment.center,
  }) => buildRenderWidget(key, fit, alignment);

  // ── IVideoPlayer: stream getters ───────────────────────────────────────────

  @override
  Stream<Duration> get positionStream => _positionCtrl.stream;

  @override
  Stream<BufferingState> get bufferingStream => _bufferingCtrl.stream;

  @override
  Stream<bool> get isPlayingStream => _playingCtrl.stream;

  @override
  Stream<PlayerError?> get errorStream => _errorCtrl.stream;

  @override
  Stream<List<BufferRange>> get bufferedStream => _bufferedCtrl.stream;

  @override
  Stream<VideoSize?> get videoSizeStream => _videoSizeCtrl.stream;

  @override
  Stream<bool> get isLiveStream => _isLiveCtrl.stream;

  @override
  Stream<bool> get completedStream => _completedCtrl.stream;

  // ── Protected helpers: typed emit ─────────────────────────────────────────
  // Each helper reads lifecycleToken at call-time, so safe inside async
  // callbacks and stream listeners.

  @protected
  void emitPosition(Duration v) => safeEmit(_positionCtrl, v, lifecycleToken);

  @protected
  void emitPlaying(bool v) => safeEmit(_playingCtrl, v, lifecycleToken);

  @protected
  void emitBuffering(BufferingState v) =>
      safeEmit(_bufferingCtrl, v, lifecycleToken);

  @protected
  void emitError(PlayerError? v) => safeEmit(_errorCtrl, v, lifecycleToken);

  @protected
  void emitBuffered(List<BufferRange> v) =>
      safeEmit(_bufferedCtrl, v, lifecycleToken);

  @protected
  void emitVideoSize(VideoSize? v) =>
      safeEmit(_videoSizeCtrl, v, lifecycleToken);

  @protected
  void emitLive(bool v) => safeEmit(_isLiveCtrl, v, lifecycleToken);

  @protected
  void emitCompleted(bool v) => safeEmit(_completedCtrl, v, lifecycleToken);

  // ── Protected helpers: subscription tracking ───────────────────────────────

  /// Register an event subscription so it is cancelled automatically during
  /// [reset] and [dispose].
  ///
  /// Call this inside [onInitialize] for every `stream.listen(...)` you create.
  @protected
  void addSubscription(StreamSubscription<dynamic> sub) {
    _subscriptions.add(sub);
  }

  // ── Protected helpers: stream state reset ──────────────────────────────────

  /// Push clean initial state into every stream.
  ///
  /// Call at the start of [onInitialize] (before opening a new source) so
  /// the UI does not show stale data from the previous media.
  @protected
  void resetAllStreams() {
    final token = lifecycleToken;
    safeEmit(_positionCtrl, Duration.zero, token);
    safeEmit(_playingCtrl, false, token);
    safeEmit(_bufferingCtrl, const BufferingState(isBuffering: true), token);
    safeEmit(_errorCtrl, null, token);
    safeEmit(_bufferedCtrl, const <BufferRange>[], token);
    safeEmit(_videoSizeCtrl, null, token);
    safeEmit(_isLiveCtrl, false, token);
    safeEmit(_completedCtrl, false, token);
  }

  // ── Protected helpers: HLS open-with-retry ────────────────────────────────
  //
  // These helpers are backend-agnostic — they interact with the underlying
  // player only through callbacks you provide, so any adapter can use them.
  //
  // Background: Many lower-level players (libmpv / media_kit) do NOT throw
  // synchronously on open() failure; errors arrive asynchronously via a
  // separate error stream. The standard try/catch pattern simply does not
  // work. The strategy here is to "race" two futures after each open():
  //   a) Format-stable signal  → success
  //   b) Fatal error signal    → failure → retry with back-off
  //
  // ── HLS duration-stable detection constants ────────────────────────────────
  //
  // Phase 1 – wait for the first non-zero duration (playlist parsed).
  // Phase 2 – wait for the duration to stop changing (full index loaded).
  //
  // Rationale for values:
  //   • Most CDN m3u8 segments are 2–10 s; the full index usually resolves in
  //     3–8 s on a healthy connection.
  //   • 500 ms poll interval is fast enough to catch changes without burning
  //     the event loop.
  //   • 6 consecutive stable readings = 3 s of stability, enough to
  //     distinguish "truly done" from "momentarily paused".
  //   • Fast path: a duration already past 5 min that holds for 2 readings
  //     (1 s) is a VOD whose index is done loading — a still-growing HLS
  //     index doesn't sit motionless on a large value (same 300s heuristic
  //     as isStreamLive). Skips the full 3 s tax on the common case.

  static const _kPollInterval = Duration(milliseconds: 500);
  static const _kPhase1Timeout = Duration(seconds: 15);
  static const _kPhase2Timeout = Duration(seconds: 30);
  static const _kStableRequired = 6;
  static const _kFastPathMinDuration = Duration(minutes: 5);
  static const _kFastPathStableRequired = 2;

  /// Open media with automatic retry on fatal errors.
  ///
  /// ### Parameters
  /// - [maxRetries]: Maximum number of attempts (default: 3).
  /// - [open]: Callback that triggers the underlying player's open/load call.
  ///   This callback is NOT expected to throw on failure — errors must arrive
  ///   via [errorStream].
  /// - [errorStream]: The player's error stream. Events are inspected by
  ///   [isFatalError]; non-fatal events are silently ignored.
  /// - [isFatalError]: Predicate that returns `true` for errors that should
  ///   trigger a retry (e.g. connection refused, HTTP 5xx). Return `false`
  ///   for transient noise (e.g. HLS segment 404 that the player auto-retries).
  /// - [waitForFormat]: Async callback that waits until the format/duration is
  ///   stable enough to consider the open successful. Receives a [Completer]
  ///   that resolves to [OpenResult] — complete it with [OpenResult.failure]
  ///   to abort the current wait early.
  /// - [onRetry]: Optional callback invoked before each retry attempt.
  ///
  /// ### Throws
  /// Throws [Exception] after exhausting all retries.
  @protected
  Future<void> openWithRetry({
    int maxRetries = 3,
    required LifecycleToken token,
    required Future<void> Function() open,
    required Stream<String> errorStream,
    required bool Function(String error) isFatalError,
    required Future<void> Function(Completer<OpenResult> cancelToken)
    waitForFormat,
    void Function(int attempt, int maxRetries)? onRetry,
    Duration openCallTimeout = const Duration(seconds: 60),
  }) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      // [token] was captured once at initialize() entry. If initialize() is
      // called again (new scope) or dispose() runs, this check ends the loop.
      if (_isDisposed || !token.isAlive) return;

      debugPrint(
        '[BaseVideoPlayerAdapter] openWithRetry attempt $attempt/$maxRetries',
      );

      final cancelToken = Completer<OpenResult>();
      StreamSubscription<String>? errorSub;

      // Start listening to the error stream BEFORE calling open().
      // This ensures we capture synchronous errors that happen during open()
      // without waiting for the full format-stable timeout.
      errorSub = errorStream.listen((error) {
        if (cancelToken.isCompleted) return;
        if (isFatalError(error)) {
          debugPrint('[BaseVideoPlayerAdapter] Fatal error during open: $error');
          cancelToken.complete(OpenResult.failure);
        }
      });

      try {
        // Bounded: a platform open that neither completes nor throws (stalled
        // HLS socket keeps fvp "preparing" forever) would hang this await —
        // and with it the caller's switching state, whose opaque overlay
        // blocks ALL player input. A timeout counts as a failed attempt so
        // the normal retry ladder / OPEN_FAILED path takes over.
        try {
          await open().timeout(openCallTimeout);
        } on TimeoutException {
          debugPrint(
            '[BaseVideoPlayerAdapter] open() timed out on attempt $attempt',
          );
          if (!cancelToken.isCompleted) {
            cancelToken.complete(OpenResult.failure);
          }
        }

        if (!cancelToken.isCompleted) {
          // If open() succeeded without immediate error, race against timeouts/format stability.
          await waitForFormat(cancelToken);
        }

        if (!cancelToken.isCompleted) {
          cancelToken.complete(OpenResult.success);
        }

        final result = await cancelToken.future;

        if (result == OpenResult.success) {
          debugPrint(
            '[BaseVideoPlayerAdapter] openWithRetry succeeded on attempt $attempt',
          );
          return;
        }

        debugPrint(
          '[BaseVideoPlayerAdapter] openWithRetry failed on attempt $attempt/$maxRetries',
        );

        if (attempt >= maxRetries) {
          final msg = 'Failed to open media after $maxRetries attempts.';
          emitError(PlayerError(code: 'OPEN_FAILED', message: msg));
          throw Exception(msg);
        }

        onRetry?.call(attempt, maxRetries);

        // Exponential back-off: 1 s, 2 s, … Re-check after the delay so a
        // switch/dispose landing mid-back-off cancels instead of reopening.
        await Future.delayed(Duration(seconds: attempt));
        if (_isDisposed || !token.isAlive) return;
      } finally {
        await errorSub.cancel();
      }
    }
  }

  /// Wait until the media format (duration / video dimensions) is stable.
  ///
  /// - For regular media: one valid non-zero duration reading is enough.
  /// - For HLS/m3u8: uses the two-phase duration-stability algorithm to avoid
  ///   reporting a single-segment duration instead of the full playlist length.
  ///
  /// ### Parameters
  /// - [source]: The video source being opened.
  /// - [cancelToken]: Shared cancellation signal from [_raceSuccessOrError].
  /// - [getCurrentDuration]: Synchronous getter for the player's current
  ///   duration state (e.g. `() => _player.state.duration`).
  /// - [getCurrentWidth]: Optional width getter — used as an additional
  ///   "format ready" signal for non-HLS sources.
  @protected
  Future<void> waitForFormatStable({
    required VideoSource source,
    required LifecycleToken token,
    required Completer<OpenResult> cancelToken,
    required Duration Function() getCurrentDuration,
    int? Function()? getCurrentWidth,
  }) async {
    if (!isM3u8(source.path)) {
      await _waitFirstValidDuration(
        timeout: const Duration(seconds: 10),
        token: token,
        cancelToken: cancelToken,
        getCurrentDuration: getCurrentDuration,
        getCurrentWidth: getCurrentWidth,
      );
      return;
    }
    await _waitHlsDurationStable(
      token: token,
      cancelToken: cancelToken,
      getCurrentDuration: getCurrentDuration,
    );
  }

  @protected
  bool isM3u8(String path) {
    final lower = path.toLowerCase();
    return lower.contains('.m3u8') || lower.contains('.m3u');
  }

  /// Extracts standard HTTP headers for anti-hotlinking evasion.
  @protected
  Map<String, String>? getHttpProxyHeaders(VideoSource source) {
    if (source.type != VideoSourceType.network) return null;
    final uri = Uri.tryParse(source.path);
    if (uri == null) return null;
    return {
      'User-Agent':
          'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
      'Referer': '${uri.scheme}://${uri.host}/',
    };
  }

  @protected
  bool isStreamLive(VideoSource? source, Duration dur) {
    // 1. Extreme duration represents infinite/live
    if (dur <= Duration.zero || dur.inDays > 100) return true;

    // 2. Identify by URL keywords
    final path = source?.path.toLowerCase() ?? '';
    final isPlaylist = isM3u8(path);

    if (isPlaylist) {
      // Common live indicators in URLs (especially YouTube/DVR)
      // Note: Use more specific boundaries to avoid 'keepalive' false positive.
      final hasLiveKeywords =
          path.contains('/live/') ||
          path.contains('.live') ||
          path.contains('_live') ||
          path.contains('source/yt_live') ||
          path.contains('playlist_type/dvr');

      if (hasLiveKeywords) return true;

      // HLS sliding window check:
      // If duration is very short (e.g., < 60s) for a network playlist,
      // and NOT a local file, it is likely a sliding window and thus a live stream.
      // But if duration > 300s (5 min), it's almost certainly a VOD even with HLS.
      if (source?.type == VideoSourceType.network &&
          dur.inSeconds > 0 &&
          dur.inSeconds < 60) {
        return true;
      }
    }

    return false;
  }

  /// Perform optional DNS/Node warmup for HLS playlists.
  @protected
  Future<void> performHlsWarmup(VideoSource source, LifecycleToken token) async {
    if (!isM3u8(source.path)) return;

    emitBuffering(
      const BufferingState(isBuffering: true, messageKey: 'loading_video'),
    );

    try {
      await NetworkResilience.preflightWarmup(
        source.path,
        // Cancel the (up to ~60s of) retry chain the moment this init scope is
        // superseded or the adapter is disposed — otherwise zombie sockets keep
        // hitting the CDN after a switch/teardown.
        isCancelled: () => _isDisposed || !token.isAlive,
        onRetry: (attempt, maxRetries) {
          if (token.isAlive) {
            emitBuffering(
              BufferingState(
                isBuffering: true,
                messageKey: 'retrying_with_count',
                messageArgs: {
                  'attempt': attempt.toString(),
                  'total': maxRetries.toString(),
                },
              ),
            );
          }
        },
      );
    } catch (e) {
      debugPrint('[BaseVideoPlayerAdapter] Warmup failed: $e');
      throw NetworkException(
        'Video source unavailable',
        url: Uri.tryParse(source.path),
        code: 'SERVICE_UNAVAILABLE',
      );
    } finally {
      if (token.isAlive) {
        emitBuffering(const BufferingState(isBuffering: false));
      }
    }
  }

  /// Wait for the first non-zero duration or first valid video width.
  /// Used for non-HLS sources where a single reading is sufficient.
  Future<void> _waitFirstValidDuration({
    required Duration timeout,
    required LifecycleToken token,
    required Completer<OpenResult> cancelToken,
    required Duration Function() getCurrentDuration,
    int? Function()? getCurrentWidth,
  }) async {
    if (getCurrentDuration() > Duration.zero) return;

    final completer = Completer<void>();

    void tryComplete() {
      if (!completer.isCompleted) completer.complete();
    }

    // Poll every interval — simpler than subscribing to player streams, and
    // avoids coupling the base class to any specific player API.
    final timer = Timer.periodic(_kPollInterval, (_) {
      // Stop early if this init scope was superseded or disposed.
      if (_isDisposed || !token.isAlive) {
        tryComplete();
        return;
      }
      if (getCurrentDuration() > Duration.zero) tryComplete();
      if (getCurrentWidth != null && (getCurrentWidth() ?? 0) > 0) {
        tryComplete();
      }
    });

    try {
      await Future.any([completer.future.timeout(timeout), cancelToken.future]);
    } catch (_) {
      // timeout or cancellation
      if (!cancelToken.isCompleted) {
        cancelToken.complete(OpenResult.failure);
      }
    } finally {
      timer.cancel();
    }
  }

  /// HLS-specific two-phase duration stability detection.
  ///
  /// ### Why two phases?
  /// Phase 1 waits for the first non-zero duration (fetching the playlist can
  /// take several seconds on a slow connection). Phase 2 then waits for the
  /// duration to *stop changing*, indicating that the full segment index has
  /// been parsed. Without Phase 2, a progress bar would show the single-
  /// segment duration (typically 4–10 s) instead of the full video length.
  ///
  /// ### Why polling instead of stream.listen?
  /// A duration stream only fires when the value *changes*. Once the player
  /// stops updating it (index complete or network stall), the stream goes
  /// silent — indistinguishable from "stable" and "stuck". Polling can tell
  /// the difference by observing the absence of change over a time window.
  Future<void> _waitHlsDurationStable({
    required LifecycleToken token,
    required Completer<OpenResult> cancelToken,
    required Duration Function() getCurrentDuration,
  }) async {
    // ── Phase 1: wait for first valid duration ───────────────────────────────
    final phase1Deadline = DateTime.now().add(_kPhase1Timeout);

    while (getCurrentDuration() <= Duration.zero) {
      if (_isDisposed || !token.isAlive || cancelToken.isCompleted) return;
      if (DateTime.now().isAfter(phase1Deadline)) {
        debugPrint(
          '[BaseVideoPlayerAdapter] HLS Phase 1 timeout: no duration received.',
        );
        if (!cancelToken.isCompleted) cancelToken.complete(OpenResult.failure);
        return;
      }
      await Future.delayed(_kPollInterval);
    }

    if (_isDisposed || !token.isAlive || cancelToken.isCompleted) return;

    debugPrint(
      '[BaseVideoPlayerAdapter] HLS Phase 1 done: '
      'initial duration = ${getCurrentDuration().inSeconds}s',
    );

    // ── Phase 2: wait for duration to stabilise ──────────────────────────────
    Duration lastSeen = getCurrentDuration();
    int stableStreak = 0;
    final phase2Deadline = DateTime.now().add(_kPhase2Timeout);

    while (true) {
      if (_isDisposed || !token.isAlive || cancelToken.isCompleted) return;
      if (DateTime.now().isAfter(phase2Deadline)) {
        debugPrint(
          '[BaseVideoPlayerAdapter] HLS Phase 2 timeout: '
          'duration last seen = ${lastSeen.inSeconds}s',
        );
        if (!cancelToken.isCompleted) cancelToken.complete(OpenResult.failure);
        return;
      }

      await Future.delayed(_kPollInterval);

      if (_isDisposed || !token.isAlive || cancelToken.isCompleted) return;

      final current = getCurrentDuration();
      if (current == lastSeen) {
        stableStreak++;
        debugPrint(
          '[BaseVideoPlayerAdapter] HLS Phase 2: stable '
          '$stableStreak/$_kStableRequired (${current.inSeconds}s)',
        );
        final required = current >= _kFastPathMinDuration
            ? _kFastPathStableRequired
            : _kStableRequired;
        if (stableStreak >= required) {
          debugPrint(
            '[BaseVideoPlayerAdapter] HLS Phase 2 done: '
            'duration stable at ${current.inSeconds}s'
            '${required == _kFastPathStableRequired ? ' (fast path)' : ''}',
          );
          return;
        }
      } else {
        debugPrint(
          '[BaseVideoPlayerAdapter] HLS Phase 2: duration changed '
          '${lastSeen.inSeconds}s → ${current.inSeconds}s, reset streak',
        );
        lastSeen = current;
        stableStreak = 0;
      }
    }
  }

  // ── Private internals ──────────────────────────────────────────────────────

  Future<void> _cancelAndClearSubscriptions() async {
    // Cancel concurrently for speed.
    if (_subscriptions.isNotEmpty) {
      await Future.wait(_subscriptions.map((s) => s.cancel()));
      _subscriptions.clear();
    }
  }

  Future<void> _closeAllControllers() async {
    await Future.wait([
      _positionCtrl.close(),
      _playingCtrl.close(),
      _bufferingCtrl.close(),
      _errorCtrl.close(),
      _bufferedCtrl.close(),
      _videoSizeCtrl.close(),
      _isLiveCtrl.close(),
      _completedCtrl.close(),
    ]);
  }
}
