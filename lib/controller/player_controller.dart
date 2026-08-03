import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/interfaces/window_delegate.dart';
import '../adapters/repository/memory_media_repository.dart';
import '../core/interfaces/media_repository.dart';
import '../core/localization/localization.dart';
import '../core/model/player_locale.dart';
import '../managers/playback_manager.dart';
import '../managers/audio_manager.dart';
import '../managers/media_manager.dart';
import '../managers/shared_run_detector.dart';
import '../managers/sprite_sweep_service.dart';
import '../managers/thumbnail_manager.dart';
import '../managers/ui_manager.dart';
import '../managers/window_event_manager.dart';
import '../core/interfaces/video_player.dart';
import '../core/model/model.dart';
import '../core/state/states.dart';
import '../utils/chapter_probe.dart';
import '../utils/event_control.dart';
import '../utils/log.dart';
import '../utils/util.dart';
import 'delegates/resume_delegate.dart';
import 'delegates/skip_delegate.dart';
import 'playback_event_emitter.dart';
import '../core/events/player_lifecycle_event.dart';
import '../vidra_player_sdk.dart';

/// The main controller for VidraPlayer that manages video playback lifecycle.
///
/// `PlayerController` is the central orchestrator for all video player functionality including:
/// - Playback control (play, pause, seek)
/// - Episode and quality switching
/// - Audio control (volume, mute, playback speed)
/// - History tracking and resume functionality
/// - UI state management and keyboard shortcuts
/// - Multi-episode support with auto-play and auto-skip features
///
/// ## Lifecycle
///
/// 1. Create the controller with configuration and video metadata
/// 2. Use `renderPlayer()` to get the player widget
/// 3. Control playback using methods like `play()`, `pause()`, `seek()`
/// 4. Listen to state changes via exposed streams
/// 5. Call `dispose()` when done to clean up resources
///
/// ## Basic Usage
///
/// ```dart
/// // Create controller
/// final controller = PlayerController(
///   config: PlayerConfig(
///     theme: PlayerUITheme.dark(),
///     features: PlayerFeatures.all(),
///     locale: VidraLocale.en,
///   ),
///   player: videoPlayerAdapter,
///   video: videoMetadata,
///   episodes: episodeList,
/// );
///
/// // Render in widget tree
/// @override
/// Widget build(BuildContext context) {
///   return controller.renderPlayer();
/// }
///
/// // Control playback
/// await controller.play();
/// await controller.pause();
/// await controller.seek(Duration(seconds: 30), SeekSource.external);
///
/// // Switch episodes
/// await controller.switchEpisode(1);
///
/// // Clean up
/// @override
/// void dispose() {
///   controller.dispose();
///   super.dispose();
/// }
/// ```
///
/// ## State Streams
///
/// The controller exposes several streams for observing state changes:
/// - `lifecycleStream`: Playback status (playing, paused, initialized, etc.)
/// - `positionStream`: Current playback position and duration
/// - `mediaStream`: Current episode, quality, and metadata
/// - `audioStream`: Volume, mute status, playback speed
/// - `bufferingStream`: Buffering state
/// - `errorStream`: Playback errors
/// - `lifecycleEvents`: Structured lifecycle events (created, media, playback, completion)
///
/// See also:
/// - [PlayerConfig] for configuration options
/// - [VideoPlayerWidget] for the widget implementation
/// - [PlayerUITheme] for theme customization
class PlayerController {
  static const List<double> _playbackSpeeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  // ===============================================================
  // Dependencies & State
  // ===============================================================

  PlayerConfig config;

  // Managers
  final PlaybackManager _playbackManager;
  final AudioManager _audioManager;
  final MediaManager _mediaManager;
  final UIStateManager _uiManager;
  final WindowEventManager _windowManager;

  // Delegates for focused responsibilities
  late final ResumeDelegate _resumeDelegate;
  late final SkipDelegate _skipDelegate;
  late final IVideoPlayer _player;

  // State (for transition tracking)
  PlaybackLifecycleState _lastLifecycle = const PlaybackLifecycleState();
  PlaybackPositionState _lastPosition = const PlaybackPositionState();

  // Internal flags
  bool _isDisposed = false;
  bool _pendingResumeCheck = false;
  bool _isSwitchingEpisode = false;
  bool _isSwitchingQuality = false;

  // Bumped by cancelSwitching(). A switch flight snapshots it at entry and
  // goes stale when they diverge — see _switchEpisodeInternal.
  int _switchGeneration = 0;

  // Set by cancelSwitching, cleared when a load actually lands. After a
  // cancel, media state points at an episode the player never opened — the
  // "already on this episode" guard in switchEpisode must not swallow the
  // user's next attempt to open it.
  bool _cancelledLoad = false;
  bool _isSkippingOutro = false; // Currently executing a skip action
  bool _hasSkippedOutro = false; // Already skipped for this episode
  bool _hintedMarkerSetup = false; // The right-click hint fired once already

  // Subscriptions
  StreamSubscription<PlaybackLifecycleState>? _lifecycleSub;
  StreamSubscription<PlaybackPositionState>? _positionSub;
  StreamSubscription<ErrorState>? _errorSub;
  StreamSubscription<WindowEvent>? _windowSub;
  StreamSubscription<BufferingState>? _sweepBufferingSub;

  // Event System — transition->event derivation lives in the emitter; the
  // side effects keyed on the same transitions stay in this class.
  final _events = PlaybackEventEmitter();

  // Utilities
  final LeadingDebounce _mouseMoveDebounce = LeadingDebounce(
    const Duration(milliseconds: 100),
  );

  // Localization
  late VidraLocalization localization;

  // ===============================================================
  // Construction & Initialization
  // ===============================================================

  /// Create a [PlayerController].
  ///
  /// The [player] parameter is optional. When omitted, the controller
  /// automatically creates an adapter using the factory registered on
  /// [VidraPlayer]. If neither is provided, a
  /// [StateError] is thrown with a clear message.
  ///
  /// To keep using a specific adapter unconditionally, pass it explicitly:
  /// ```dart
  /// PlayerController(
  ///   player: MediaKitPlayerAdapter(),
  ///   ...
  /// )
  /// ```
  factory PlayerController({
    required PlayerConfig config,
    IVideoPlayer? player,
    required VideoMetadata video,
    required List<VideoEpisode> episodes,
    WindowDelegate? windowDelegate,
    MediaRepository? mediaRepository,
  }) {
    return PlayerController._internal(
      config: config,
      player: _resolvePlayer(player),
      video: video,
      episodes: episodes,
      windowDelegate: windowDelegate,
      mediaRepository: mediaRepository,
    );
  }

  /// Resolve the adapter: use the provided [player] if non-null,
  /// otherwise call [VidraPlayer.createPlayer].
  ///
  /// Throws [StateError] if [player] is null and [VidraPlayer] has not
  /// been initialized.
  static IVideoPlayer _resolvePlayer(IVideoPlayer? player) {
    if (player != null) return player;
    return VidraPlayer.createPlayer();
  }

  /// Internal constructor — always receives a non-null [IVideoPlayer].
  PlayerController._internal({
    required this.config,
    required IVideoPlayer player,
    required VideoMetadata video,
    required List<VideoEpisode> episodes,
    WindowDelegate? windowDelegate,
    MediaRepository? mediaRepository,
  }) : _playbackManager = PlaybackManager(config: config, player: player),
       _audioManager = AudioManager(player: player),
       _mediaManager = MediaManager(
         repository: mediaRepository ?? MemoryMediaRepository(),
       ),
       _windowManager = WindowEventManager(),
       _uiManager = UIStateManager(
         behavior: config.behavior,
         windowDelegate: windowDelegate,
       ),
       localization = VidraLocalization(config.locale ?? VidraLocale.en) {
    _player = player;
    config = _normalizeConfig(config);
    _bindStreams();

    _initialize(
      video: video,
      episodes: episodes,
      initEpisodeIndex: config.initialEpisodeIndex,
    );

    // Initialize delegates
    _resumeDelegate = ResumeDelegate(
      mediaManager: _mediaManager,
      uiManager: _uiManager,
    );
    _skipDelegate = SkipDelegate(uiManager: _uiManager);

    _bindWindowEvents();

    // Defer PlayerCreated one microtask: emitting it synchronously here (before
    // the constructor returns) drops it, because no caller can have subscribed
    // to the broadcast lifecycleEvents stream yet. This lets a host that does
    // `controller.lifecycleEvents.listen(...)` right after construction still
    // receive the creation event.
    scheduleMicrotask(() {
      if (_isDisposed) return;
      _events.emit(const PlayerCreated());
    });
  }

  void _initialize({
    required VideoMetadata video,
    required List<VideoEpisode> episodes,
    int? initEpisodeIndex,
  }) async {
    if (_isDisposed) return;

    _beforePlayerInit(
      video: video,
      episodes: episodes,
      initEpisodeIndex: initEpisodeIndex,
    );
    // Initial load
    await _loadEpisode(initEpisodeIndex ?? 0);

    _afterPlayerInit();
  }

  void _beforePlayerInit({
    required VideoMetadata video,
    required List<VideoEpisode> episodes,
    int? initEpisodeIndex,
  }) async {
    _mediaManager.initialize(
      video: video,
      episodes: episodes,
      episodeIndex: initEpisodeIndex,
    );
  }

  void _afterPlayerInit() async {
    if (_isDisposed) return;
    try {
      // Set initial volume
      if (config.behavior.initialVolume != 1.0) {
        await _audioManager.setVolume(config.behavior.initialVolume);
      }
      // Apply initial config
      if (config.behavior.muteOnStart) {
        await _audioManager.setMute();
      }
    } catch (e) {
      logger.w('[PlayerController] Post-init audio setup failed: $e');
    }
  }

  // ===============================================================
  // Stream Accessors
  // ===============================================================

  Stream<PlaybackLifecycleState> get lifecycleStream =>
      _playbackManager.lifecycleStream;
  Stream<PlaybackPositionState> get positionStream =>
      _playbackManager.positionStream;
  Stream<MediaContextState> get mediaStream => _mediaManager.mediaStream;
  Stream<AudioState> get audioStream => _audioManager.audioStream;
  Stream<ViewModeState> get viewStream => _uiManager.viewModeStream;
  Stream<BufferingState> get bufferingStream =>
      _playbackManager.bufferingStream;
  Stream<ErrorState> get errorStream => _playbackManager.errorStream;
  Stream<SwitchingState> get switchingStream =>
      _playbackManager.switchingStream;

  /// Stream of structured lifecycle events.
  Stream<PlayerLifecycleEvent> get lifecycleEvents => _events.stream;
  ValueListenable<PlaybackPositionState> get positionListenable =>
      _playbackManager.positionNotifier;

  /// Distilled live-ness flag that only notifies when it flips. Use this
  /// instead of [positionListenable] for widgets that only branch on isLive —
  /// it won't rebuild them on every position tick.
  ValueListenable<bool> get isLiveListenable => _playbackManager.isLiveNotifier;

  // State Getters
  PlaybackLifecycleState get lifecycle => _playbackManager.lifecycleState;
  PlaybackPositionState get position => _playbackManager.positionState;
  MediaContextState get media => _mediaManager.state;
  AudioState get audio => _audioManager.state;
  ViewModeState get view => _uiManager.currentViewMode;
  BufferingState get buffering => _playbackManager.bufferingState;
  ErrorState get error => _playbackManager.errorState;
  SwitchingState get switching => _playbackManager.switchingState;

  // ===============================================================
  // Core Playback Operations
  // ===============================================================

  Future<void> play() async {
    if (_isDisposed) return;
    await _playbackManager.play();
  }

  Future<void> pause() async {
    if (_isDisposed) return;
    await _playbackManager.pause();
  }

  Future<void> togglePlayPause() async {
    if (_isDisposed) return;

    if (lifecycle.isPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> seek(Duration targetPosition, SeekSource source) async {
    if (_isDisposed) return;
    await _playbackManager.seek(targetPosition, source);
  }

  Future<void> seekRelative(Duration offset) async {
    if (_isDisposed) return;

    final newPosition = position.position + offset;
    final clampedPosition = Duration(
      milliseconds: newPosition.inMilliseconds.clamp(
        0,
        position.duration.inMilliseconds,
      ),
    );
    await _playbackManager.seek(clampedPosition, SeekSource.external);
  }

  Future<void> seekStart() async {
    if (_isDisposed) return;
    _playbackManager.beforeSeek();
    if (lifecycle.isPlaying) {
      await pause();
    }
  }

  Future<void> seekEnd() async {
    if (_isDisposed) return;
    if (lifecycle.wasPlayingBeforeSeek) {
      await play();
    }
    // Clear the intent so it can't leak into unrelated later logic.
    _playbackManager.afterSeek();
  }

  Future<void> continuePlayback(int positionMillis) async {
    if (_isDisposed) return;

    // Seek first while dialog is effectively "blocking" logic (via showResumeDialog check)
    await seek(Duration(milliseconds: positionMillis), SeekSource.external);
    _uiManager.hideResumeDialog();
    await play();
    // The paused/buffering branch no longer force-shows controls while a
    // dialog is up, so give the user the standard brief bar after resuming.
    _uiManager.showControlsTemporarily();
  }

  Future<void> restartPlayback() async {
    if (_isDisposed) return;

    final setting = effectiveSkipSetting;
    if (setting.autoSkip && setting.skipIntro > 0) {
      await seek(Duration(seconds: setting.skipIntro), SeekSource.external);
      _uiManager.showSkipIntroNotification();
    } else {
      await seek(Duration.zero, SeekSource.external);
    }
    _uiManager.hideResumeDialog();
    await play();
    _uiManager.showControlsTemporarily();
  }

  // ===============================================================
  // Audio Operations
  // ===============================================================

  Future<void> setVolume(double volume) async {
    if (_isDisposed) return;
    await _audioManager.setVolume(volume);
  }

  Future<void> toggleMute() async {
    if (_isDisposed) return;
    await _audioManager.toggleMute();
  }

  Future<void> setPlaybackSpeed(double speed) async {
    if (_isDisposed) return;
    await _audioManager.setPlaybackSpeed(speed);
  }

  // ===============================================================
  // Media & Episode Management
  // ===============================================================

  Future<void> switchEpisode(int index) async {
    if (_isDisposed) return;
    // "Already on this episode" — unless a cancelled load left the player
    // empty behind a media state that claims this episode is current.
    if (_mediaManager.state.currentEpisodeIndex == index && !_cancelledLoad) {
      return;
    }

    // Prevent rapid re-entry and interleaving with a quality switch — both
    // drive resetPlayer/initialize/seek/play against the same player.
    if (_isSwitchingEpisode || _isSwitchingQuality) {
      logger.w('Ignored switchEpisode trigger: Already switching.');
      return;
    }

    return await _switchEpisodeInternal(index);
  }

  Future<void> _switchEpisodeInternal(int index) async {
    _isSwitchingEpisode = true;
    // Stop sweeping the episode being left: its tiles keep, but the new
    // episode's startup gets the whole pipe. The stable-playback trigger
    // re-arms for the new episode on its own.
    _spriteSweepService?.cancelSweep();
    // Snapshot the cancel generation: cancelSwitching() bumps it, turning this
    // flight stale. A stale flight must not play, must not re-end switching,
    // and must not clear flags a NEWER switch may have set.
    final generation = _switchGeneration;

    try {
      // Get target episode for display
      final targetEpisode =
          _mediaManager.state.episodes.isNotEmpty &&
              index < _mediaManager.state.episodes.length
          ? _mediaManager.state.episodes[index]
          : null;

      _events.rearmEpisodeEnd(); // Reset for new episode

      // Emit Change Event
      if (_mediaManager.state.currentEpisode != null && targetEpisode != null) {
        _events.emit(
          EpisodeChanged(
            from: _mediaManager.state.currentEpisode,
            to: targetEpisode,
          ),
        );
      }

      // Start switching state with episode title
      _playbackManager.startSwitching(
        targetEpisode?.title ?? localization.translate('unknown_episode'),
      );

      // Save history for current episode. Fire-and-forget: the arguments are
      // snapshotted here (old episode's index/position, a different key from
      // the episode being loaded), so the write can run concurrently with the
      // new episode's load instead of serially delaying it — and a stalled
      // host repository can no longer pin the input-blocking switching overlay.
      if (media.video != null &&
          media.currentEpisode != null &&
          position.position > Duration.zero) {
        unawaited(
          _mediaManager
              .saveProgressImmediate(
                episodeIndex: media.currentEpisodeIndex,
                positionMillis: position.position.inMilliseconds,
                durationMillis: position.duration.inMilliseconds,
              )
              .timeout(const Duration(seconds: 2))
              .catchError((Object e) {
                logger.w(
                  '[PlayerController] Pre-switch progress save failed: $e',
                );
              }),
        );
      }

      _mediaManager.switchEpisode(index);

      await _loadEpisode(index, switchEpisode: true, generation: generation);
      if (generation != _switchGeneration) return; // Cancelled mid-load.
      await play();
      if (generation != _switchGeneration) return; // Cancelled mid-play.

      // End switching state
      _playbackManager.endSwitching();

      // PERFORMANCE FIX: Removed unnecessary 500ms delay
      // The delay served no purpose and added latency to episode switches
    } catch (e) {
      logger.e('Error switching episode: $e');
      // Ensure switching state is cleared on error — but never a NEWER
      // flight's: a cancelled flight unwinding late must not tear down the
      // overlay of a switch the user started after the cancel.
      if (generation == _switchGeneration) {
        _playbackManager.endSwitching();
      }
      rethrow;
    } finally {
      // Reset the switching flag — unless this flight was cancelled, in which
      // case cancelSwitching() already cleared it and a newer switch may own
      // the flag by the time this stale flight unwinds.
      if (generation == _switchGeneration) {
        _isSwitchingEpisode = false;
      }
    }
  }

  Future<void> switchQuality(int index, {bool forcePlay = false}) async {
    if (_isDisposed) return;

    // Prevent rapid re-entry and interleaving with an episode switch — common
    // on flaky networks where users tap quality repeatedly.
    if (_isSwitchingQuality || _isSwitchingEpisode) {
      logger.w('Ignored switchQuality trigger: Already switching.');
      return;
    }

    // Get target quality label for display
    final targetQuality =
        media.availableQualities.isNotEmpty &&
            index < media.availableQualities.length
        ? media.availableQualities[index]
        : null;

    if (targetQuality == null) return;

    _isSwitchingQuality = true;
    final generation = _switchGeneration; // See _switchEpisodeInternal.
    // Same reasoning as the episode switch: the quality switch's open needs
    // the pipe more than the background sweep does. Resume re-arms after.
    _spriteSweepService?.cancelSweep();
    try {
      // Start switching state
      _playbackManager.startSwitching(targetQuality.label);

      final currentPosition = position.position;
      final wasPlaying = lifecycle.status == PlaybackStatus.playing;

      await _playbackManager.resetPlayer();
      // Cancel landing during resetPlayer: without this check the flight
      // would call initialize with a FRESH token and open the target quality
      // as if never cancelled.
      if (generation != _switchGeneration) return;

      // Open the target quality's source directly (we already resolved it as
      // targetQuality above — no need to mutate media state first).
      final ok = await _playbackManager.initialize(targetQuality.source);
      if (_isDisposed) {
        _playbackManager.endSwitching();
        return;
      }
      // A cancelled load lands in !ok too (its token died), so the stale
      // check comes FIRST — and a stale flight must not call endSwitching:
      // by the time it unwinds (a hung platform open ends at its own 60s
      // timeout) a NEWER switch may own the overlay it would tear down.
      if (generation != _switchGeneration) return;
      if (!ok) {
        // Open failed — keep the OLD quality index committed in media state so
        // the selector and currentSource stay truthful, and surface the error.
        _playbackManager.endSwitching();
        return;
      }
      _cancelledLoad = false; // The player genuinely holds this source now.

      _events.rearmEpisodeEnd();

      // Restore audio/speed state after player reset
      await _audioManager.restoreState();
      if (generation != _switchGeneration) return;

      // Commit the new quality only on success.
      _mediaManager.switchQuality(index);

      if (currentPosition > Duration.zero) {
        await seek(currentPosition, SeekSource.external);
        if (generation != _switchGeneration) return;
      }
      if (wasPlaying || forcePlay) {
        await play();
        if (generation != _switchGeneration) return;
      }
      // End switching state
      _playbackManager.endSwitching();
    } catch (e) {
      // Ensure state is cleared on error — never a newer flight's overlay.
      if (generation == _switchGeneration) {
        _playbackManager.endSwitching();
      }
      rethrow;
    } finally {
      if (generation == _switchGeneration) {
        _isSwitchingQuality = false;
      }
    }
  }

  /// Abandon an in-flight episode or quality switch and give the UI back.
  ///
  /// The blocking overlay drops immediately. The abandoned flight is killed
  /// two ways, because one is not enough: the dead lifecycle token makes an
  /// initialize() that is ALREADY in flight return false, and the generation
  /// checks after every await catch a cancel that lands anywhere else —
  /// during resetPlayer, restoreState, the chapter probe, or the resume
  /// check, where a fresh token would otherwise be minted and the flight
  /// would complete as if never cancelled.
  ///
  /// The player is left where a FAILED load leaves it — nothing playing,
  /// controls interactive, every episode/quality action available.
  ///
  /// No-op when nothing is switching.
  void cancelSwitching() {
    if (_isDisposed || !switching.isSwitching) return;

    // Turn the in-flight switch stale BEFORE anything else: whatever it does
    // from here on (play, endSwitching, flag clears) is guarded on this.
    _switchGeneration++;

    _playbackManager.cancelLoad();
    _playbackManager.endSwitching();

    // The stale flight skips its own flag clears (a newer switch may own the
    // flags by the time it unwinds), so this owns them: switching flags so a
    // new switch is allowed immediately, and the save-blocking resume flag
    // the flight set at load start — periodic saves stay safe behind their
    // own position > 0 guard.
    _isSwitchingEpisode = false;
    _isSwitchingQuality = false;
    _pendingResumeCheck = false;
    _cancelledLoad = true;

    showControls();
  }

  /// Whether [generation] belongs to a switch flight that has been cancelled.
  /// null means "not a cancellable flight" (the initial load).
  bool _isStaleFlight(int? generation) =>
      generation != null && generation != _switchGeneration;

  /// [generation] is the cancel-generation snapshotted by the switch flight
  /// that called this (null for the initial, uncancellable load). It is
  /// re-checked after EVERY await: the lifecycle token only covers a cancel
  /// that lands while initialize() is in flight — one landing during any
  /// other await here would otherwise go unseen, and the flight would mint
  /// fresh tokens and complete (EpisodeStarted, auto-play and all) for an
  /// episode the user just refused.
  Future<void> _loadEpisode(
    int index, {
    bool switchEpisode = false,
    int? generation,
  }) async {
    if (index < 0 || index >= _mediaManager.state.episodes.length) return;

    _hasSkippedOutro = false; // Reset skip state for new episode

    // Block periodic progress saves for the WHOLE load, not just from the
    // resume check onward: position(0) events emitted while the player opens
    // are delivered across this method's awaits, and an unblocked one would
    // save position 0 over the stored history before the resume check reads
    // it (whether it slipped through was previously microtask-timing luck).
    // _checkResumePlayback clears the flag in its finally.
    _pendingResumeCheck = true;

    if (switchEpisode) {
      await _playbackManager.resetPlayer();
      // A stale flight leaves _pendingResumeCheck alone everywhere below:
      // cancelSwitching cleared it, and a NEWER flight may have re-set it —
      // clearing here would disarm that flight's save protection (measured:
      // the periodic save then overwrites the stored resume position).
      if (_isDisposed || _isStaleFlight(generation)) return;
    }

    // Kick the chapter probe off in PARALLEL with opening the player: it's one
    // playlist GET against a URL the player is about to fetch anyway, so by the
    // time the (much slower) open finishes it has long since resolved, and
    // awaiting it below costs nothing. Sequencing it before the resume check is
    // what lets chapter markers apply on the first play, not the second.
    final chapterProbe = _probeChapterMarkers(index);

    // Resolve from the single source authority (media state was already
    // advanced to this episode+quality before _loadEpisode ran).
    final ok = await _playbackManager.initialize(
      _mediaManager.state.currentSource,
    );
    if (_isDisposed) return;
    if (!ok) {
      // Load failed — error already emitted. Don't drive audio/resume/play
      // against a player that never opened. Unblock saves: the resume check
      // that would normally clear the flag never runs on this path. (Not on
      // a stale flight — see the resetPlayer comment above.)
      if (!_isStaleFlight(generation)) _pendingResumeCheck = false;
      return;
    }
    if (_isStaleFlight(generation)) return; // Cancelled post-open.
    _cancelledLoad = false; // The player genuinely holds this episode now.
    // Restore audio/speed state after player reset
    await _audioManager.restoreState();
    if (_isDisposed || _isStaleFlight(generation)) return;
    showControls();

    // Emit EpisodeStarted
    final currentEp = _mediaManager.state.currentEpisode;
    if (currentEp != null) {
      _events.emit(EpisodeStarted(index: index, episode: currentEp));
    }

    // if (config.behavior.autoPlay) {
    //   // Optimisation: If history is enabled, we delay auto-play until
    //   // ResumeDelegate decides whether to seek (intro skip) or prompt (resume).
    //   // This prevents playing immediately then jumping, or playing then pausing.
    //   if (!config.features.enableHistory) {
    //     await play();
    //   }
    // }
    await chapterProbe;
    if (_isDisposed || _isStaleFlight(generation)) return;

    // Check restore for new episode (flag was set at the top of this method)
    _checkResumePlayback(index, generation: generation);
  }

  /// Once per session, nudge the user that skip points can be set by
  /// right-clicking the progress bar — but only for a video where nothing is
  /// set, so it never fires at someone who already configured it.
  ///
  /// Deliberately a few seconds INTO playback rather than at load: position
  /// only advances once nothing is blocking, so a resume/replay prompt has
  /// been dealt with by then and the hint can't be spent on a frame nobody
  /// sees. Desktop-only — there is no right-click to point at otherwise.
  ///
  /// Bounded to the opening minute so it reads as "here's a tip as you start
  /// watching". Without the upper bound it also fires at the natural end of an
  /// episode, on top of the auto-advance. A resumed episode starts past the
  /// window and simply doesn't get hinted — the next one played from the top
  /// will.
  void _maybeHintMarkerSetup(PlaybackPositionState state) {
    if (_hintedMarkerSetup || state.isLive) return;
    if (!Platform.isMacOS && !Platform.isWindows && !Platform.isLinux) return;
    if (state.position < const Duration(seconds: 4) ||
        state.position > const Duration(seconds: 60)) {
      return;
    }

    final markers = currentMarkers;
    final configured =
        playerSetting.skipIntro > 0 ||
        playerSetting.skipOutro > 0 ||
        (markers != null && !markers.isEmpty);
    if (configured) {
      // Nothing to teach — retire the hint for the rest of the session.
      _hintedMarkerSetup = true;
      return;
    }

    _hintedMarkerSetup = _uiManager.showMarkerHint();
    if (_hintedMarkerSetup) {
      logger.d('[PlayerController] showed the right-click marker hint');
    }
  }

  /// Read intro/outro markers out of the media's own chapters, if it has any.
  /// Never throws and never blocks for long — see [probeChapters].
  Future<void> _probeChapterMarkers(int index) async {
    // Anything already recorded (a manual edit, a previous probe) outranks
    // this, so don't spend a request re-deriving it.
    if (_mediaManager.state.episodeMarkers.containsKey(index)) return;

    final url = _mediaManager.state.currentSource?.path;
    if (url == null) return;

    final markers = await probeChapters(url, index);
    if (markers == null || _isDisposed) return;
    if (_mediaManager.state.currentEpisodeIndex != index) return;

    logger.d('[PlayerController] chapter markers for ep $index: $markers');
    await _mediaManager.updateEpisodeMarkers(markers);
  }

  Future<void> playNextEpisode() async {
    if (_isDisposed) return;

    if (hasNextEpisode) {
      final nextIndex = media.currentEpisodeIndex + 1;
      await switchEpisode(nextIndex);
    }
  }

  Future<void> playPreviousEpisode() async {
    if (_isDisposed) return;

    if (hasPreviousEpisode) {
      final previousIndex = media.currentEpisodeIndex - 1;
      await switchEpisode(previousIndex);
    }
  }

  void updateEpisodes(List<VideoEpisode> episodes) {
    if (_isDisposed) return;
    _mediaManager.updateEpisodes(episodes);
    // Sprite tiles are keyed by episode INDEX; a replaced/reordered catalog
    // would silently serve the wrong episode's frames. Drop and re-sweep.
    _spriteSweepService?.clear();
    // The overlay (episode list panel) is driven by visibilityStream; force a
    // repaint so a panel that is already open picks up the new catalog.
    _uiManager.refresh();
  }

  Future<void> playNextEpisodeFromReplay() async {
    if (_isDisposed) return;

    _uiManager.hideReplayDialog();
    await playNextEpisode();
  }

  bool get hasNextEpisode {
    if (_isDisposed) return false;
    return media.hasNextEpisode;
  }

  bool get hasPreviousEpisode {
    if (_isDisposed) return false;
    return media.hasPreviousEpisode;
  }

  Future<EpisodeHistory?> getEpisodeHistory(int index) async {
    if (_isDisposed) return null;
    return await _mediaManager.getEpisodeHistory(index);
  }

  Future<void> refreshHistory() async {
    if (_isDisposed) return;
    await _mediaManager.getAllHistories();
    if (_isDisposed) return;
    // Repaint an already-open episode list so watched badges/progress update.
    _uiManager.refresh();
  }

  // ===============================================================
  // Feature Logic (Resume/Properties)
  // ===============================================================

  void _checkResumePlayback(int episodeIndex, {int? generation}) async {
    if (_isDisposed) {
      _pendingResumeCheck = false;
      return;
    }
    // A stale flight neither plays nor touches the flag: cancelSwitching
    // owns the clear, and a newer flight may have re-armed it since.
    if (_isStaleFlight(generation)) return;

    // Cancel can land during any await below; auto-playing the episode the
    // user just refused is the one side effect that must not slip through.
    Future<void> guardedPlay() async {
      if (_isStaleFlight(generation)) return;
      await play();
    }

    if (!config.features.enableHistory) {
      _pendingResumeCheck = false;
      // If history is disabled but auto-play is on, we play immediately here
      // because _loadEpisode deferred it.
      if (config.behavior.autoPlay) {
        await guardedPlay();
      }
      return;
    }
    try {
      await _resumeDelegate.checkAndPromptResume(
        episodeIndex: episodeIndex,
        isInitialized: lifecycle.isInitialized,
        isDisposed: () => _isDisposed || _isStaleFlight(generation),
        seek: seek,
        pause: pause,
        play: guardedPlay,
        getPlayerSetting: () => effectiveSkipSetting,
        autoPlay: config.behavior.autoPlay,
        resumeMode: config.behavior.resumeMode,
      );
    } catch (e) {
      logger.e('[PlayerController] Resume check failed: $e');
      // If check fails, fallback to auto-play
      if (config.behavior.autoPlay) {
        await guardedPlay();
      }
    } finally {
      // Clear checking flag so we can start saving new progress — unless the
      // flight went stale mid-check, in which case the flag is no longer ours.
      if (!_isStaleFlight(generation)) {
        _pendingResumeCheck = false;
      }
    }
  }

  Future<void> replayEpisode() async {
    if (_isDisposed) return;

    await seek(Duration.zero, SeekSource.external);
    _uiManager.hideReplayDialog();
    await play();
    _uiManager.showControlsTemporarily();
  }

  /// Close the "you've finished this episode" dialog and stay put.
  ///
  /// Deliberately does NOT play: this is the dialog's only "I'm done watching"
  /// exit, and every one of its buttons used to start playback from 0:00 —
  /// "cancel" replayed the episode just like "replay" did, which made the
  /// choice a fake one and left no way to simply stop. Hiding the dialog also
  /// re-enables the control bar (and with it the window close button), which
  /// is IgnorePointer-blocked while any dialog is up.
  Future<void> dismissReplayDialog() async {
    if (_isDisposed) return;

    _uiManager.hideReplayDialog();
    _uiManager.showControlsTemporarily();
  }

  /// Dismiss the non-blocking resume card. Playback is already running at the
  /// restored position, so this only takes the card away.
  void dismissResumeHint() {
    if (_isDisposed) return;
    _uiManager.hideResumeHint();
  }

  /// Start this episode over from the beginning, from the resume card.
  Future<void> restartFromResumeHint() async {
    if (_isDisposed) return;
    _uiManager.hideResumeHint();
    await restartPlayback();
  }

  /// Close the resume prompt without starting playback. The dialog otherwise
  /// only offers "continue" or "start over" — both of which play — so there was
  /// no way to back out and drive the controls yourself.
  ///
  /// Parks the playhead ON the remembered position first. Hiding the dialog
  /// clears resumeState and nothing else in the UI shows where the viewer had
  /// got to, so dismissing from 0:00 would strand them at the start with the
  /// only record of "32:15" gone from the screen — and the first position tick
  /// would then write 0 over the stored history, which is exactly the overwrite
  /// the resume-check gate in _loadEpisode exists to prevent.
  Future<void> dismissResumeDialog() async {
    if (_isDisposed) return;

    final resume = _uiManager.currentVisibility.resumeState;
    if (resume != null && resume.positionMillis > 0) {
      await seek(
        Duration(milliseconds: resume.positionMillis),
        SeekSource.external,
      );
      if (_isDisposed) return;
    }
    _uiManager.hideResumeDialog();
    _uiManager.showControlsTemporarily();
  }

  /// Keys the modal resume/replay dialogs answer to: Enter takes the primary
  /// action, Escape backs out without playing, everything else — space very
  /// much included — is swallowed so it can't reach the blocked player behind
  /// the dialog.
  ///
  /// Space is deliberately NOT a confirm key here. It means play/pause
  /// everywhere else in the player, so binding it to "replay this episode"
  /// would trade one surprise (silent playback behind the dialog) for another
  /// (an episode restarting from 0:00 because the user reached for pause).
  void _handleDialogShortcut(String shortcut, {required bool isReplay}) {
    switch (shortcut) {
      case 'enter':
        if (isReplay) {
          // Finished an episode: the next one is what the viewer wants when
          // there is one, replaying this one is the fallback.
          if (hasNextEpisode) {
            playNextEpisodeFromReplay();
          } else {
            replayEpisode();
          }
        } else {
          final resume = _uiManager.currentVisibility.resumeState;
          if (resume != null) continuePlayback(resume.positionMillis);
        }
      case 'escape':
        if (isReplay) {
          dismissReplayDialog();
        } else {
          dismissResumeDialog();
        }
      default:
        break;
    }
  }

  PlayerSetting get playerSetting =>
      media.playerSetting ?? PlayerSetting(videoId: media.video!.id);

  /// Markers for the episode being played, if any.
  EpisodeMarkers? get currentMarkers => media.currentMarkers;

  /// What the skip logic must act on: [playerSetting] with skipIntro/skipOutro
  /// replaced by this episode's markers when it has any. Markers are absolute
  /// times while skipOutro is a tail length, hence the duration lookup.
  ///
  /// Everything downstream still sees a plain [PlayerSetting], so a host that
  /// only ever sets the series-wide seconds is unaffected.
  PlayerSetting get effectiveSkipSetting {
    final markers = currentMarkers;
    if (markers == null || markers.isEmpty) return playerSetting;
    return playerSetting.copyWith(
      skipIntro: markers.introEnd?.inSeconds,
      skipOutro: markers.outroStart == null
          ? null
          : markers.outroTailSeconds(_lastPosition.duration),
    );
  }

  late final bool _autoPlayNext = config.features.enableAutoPlayNext;
  bool get autoPlayNext => _autoPlayNext;

  void updateAutoSkip(bool value) {
    if (_isDisposed) return;
    _mediaManager.updateAutoSkip(value);
  }

  void updateSkipIntro(int duration) {
    if (_isDisposed) return;
    _mediaManager.updateSkipIntro(duration);
  }

  void updateSkipOutro(int duration) {
    if (_isDisposed) return;
    _mediaManager.updateSkipOutro(duration);
  }

  /// What [setSkipPoint] replaced, so [undoSkipPoint] can put it back.
  ({EpisodeMarkers? markers, int skipIntro, int skipOutro})? _skipPointUndo;

  /// A user placing a skip point by hand (the progress bar's right-click menu).
  ///
  /// Writes BOTH layers on purpose:
  /// - a manual marker on this episode, so it outranks any chapter/detected
  ///   value that would otherwise win here;
  /// - the series-wide [PlayerSetting], because that is what a viewer means by
  ///   "the intro is 90 seconds" — every other episode should skip it too — and
  ///   because it persists through [MediaRepository.savePlayerSettings], which
  ///   every host implements. [EpisodeMarkerStore] is optional, so a marker
  ///   alone would silently vanish on restart for most hosts.
  ///
  /// [outroStart] is absolute; skipOutro is a tail length, hence the duration.
  void setSkipPoint({Duration? introEnd, Duration? outroStart}) {
    if (_isDisposed) return;

    final previous = playerSetting;
    _skipPointUndo = (
      markers: currentMarkers,
      skipIntro: previous.skipIntro,
      skipOutro: previous.skipOutro,
    );

    setEpisodeMarkers(introEnd: introEnd, outroStart: outroStart);

    if (introEnd != null) {
      updateSkipIntro(introEnd.inSeconds < 0 ? 0 : introEnd.inSeconds);
    }
    if (outroStart != null) {
      final tail = _lastPosition.duration - outroStart;
      updateSkipOutro(tail.isNegative ? 0 : tail.inSeconds);

      // Marking the outro at or behind the playhead satisfies the auto-skip
      // condition on the very next tick, so the episode would cut away the
      // instant the menu closed — no warning, and it reads as the player
      // breaking. Treat this episode's outro as already handled; the value
      // still applies from the next episode on, exactly like the intro does.
      if (outroStart <= _lastPosition.position) {
        _hasSkippedOutro = true;
      }
    }

    _uiManager.showMarkerSetNotification(
      localization.translate(
        introEnd != null ? 'marker_set_intro' : 'marker_set_outro',
        args: {'time': Util.formatDuration(introEnd ?? outroStart!)},
      ),
    );
  }

  /// Put back whatever [setSkipPoint] overwrote. Backs the confirmation's undo
  /// button: a misplaced marker is otherwise only reversible through the
  /// settings menu's ±5s stepper, which is 240 taps for a 20-minute mistake.
  void undoSkipPoint() {
    if (_isDisposed) return;
    final undo = _skipPointUndo;
    if (undo == null) return;
    _skipPointUndo = null;

    _mediaManager.updateEpisodeMarkers(
      undo.markers ??
          EpisodeMarkers(episodeIndex: media.currentEpisodeIndex, clear: true),
    );
    updateSkipIntro(undo.skipIntro);
    updateSkipOutro(undo.skipOutro);
    _uiManager.hideSkipNotification();
  }

  /// Drop every skip point for this video: the episode's marker and the
  /// series-wide seconds alike. Without it a wrong value can only be walked
  /// back 5 seconds at a time, and a marker cannot be removed at all.
  void clearSkipPoints() {
    if (_isDisposed) return;

    _skipPointUndo = (
      markers: currentMarkers,
      skipIntro: playerSetting.skipIntro,
      skipOutro: playerSetting.skipOutro,
    );

    _mediaManager.updateEpisodeMarkers(
      EpisodeMarkers(episodeIndex: media.currentEpisodeIndex, clear: true),
    );
    updateSkipIntro(0);
    updateSkipOutro(0);
    _uiManager.hideSkipNotification();
  }

  /// Whether anything is currently set for this episode — drives whether the
  /// right-click menu bothers offering "clear".
  bool get hasSkipPoints {
    final markers = currentMarkers;
    return playerSetting.skipIntro > 0 ||
        playerSetting.skipOutro > 0 ||
        (markers != null && !markers.isEmpty);
  }

  /// Mark the intro end and/or outro start for one episode (defaults to the
  /// current one). Pass [MarkerSource.manual] — the default — for user edits;
  /// they then survive any later chapter probe or detector run.
  ///
  /// For a user action prefer [setSkipPoint], which also updates the
  /// series-wide setting so the value persists and covers the other episodes.
  void setEpisodeMarkers({
    Duration? introStart,
    Duration? introEnd,
    Duration? outroStart,
    int? episodeIndex,
    MarkerSource source = MarkerSource.manual,
  }) {
    if (_isDisposed) return;
    final index = episodeIndex ?? media.currentEpisodeIndex;
    // A cleared marker is not a base to merge onto — treat it as absent, or
    // "clear then set the intro" would resurrect the outro that was erased.
    final existing = media.episodeMarkers[index];
    final base = (existing == null || existing.clear) ? null : existing;
    _mediaManager.updateEpisodeMarkers(
      EpisodeMarkers(
        episodeIndex: index,
        introStart: introStart ?? base?.introStart,
        introEnd: introEnd ?? base?.introEnd,
        outroStart: outroStart ?? base?.outroStart,
        source: source,
      ),
    );
  }

  // ===============================================================
  // UI & Window Control
  // ===============================================================

  Widget renderPlayer({Key? key}) {
    return _playbackManager.renderPlayer(key: key);
  }

  double get aspectRatio => lifecycle.aspectRatio;

  void showControls() => _uiManager.showControlsTemporarily();
  void hideControls() => _uiManager.hideControlsImmediately();
  void toggleControls() => _uiManager.toggleControls();
  Stream<UIVisibilityState> get visibilityStream => _uiManager.visibilityStream;
  UIVisibilityState get visibility => _uiManager.currentVisibility;
  void showSeekFeedback(Duration amount) => _uiManager.showSeekFeedback(amount);
  void showControlsPersistently() => _uiManager.showControlsPersistently();
  void showControlsTemporarily() => _uiManager.showControlsTemporarily();
  void handleMouseEnterVideo() => _uiManager.handleMouseEnterVideo();
  void handleMouseLeaveVideo() => _uiManager.handleMouseLeaveVideo();
  void handleMouseEnterControls() => _uiManager.handleMouseEnterControls();
  void handleMouseLeaveControls() => _uiManager.handleMouseLeaveControls();

  Future<void> stepPlaybackSpeed(int direction) async {
    if (_isDisposed || !config.features.enablePlaybackSpeed || direction == 0) {
      return;
    }

    final currentSpeed = audio.playbackSpeed;
    final currentIndex = _playbackSpeeds.indexOf(currentSpeed);
    final safeIndex = currentIndex >= 0
        ? currentIndex
        : _playbackSpeeds.indexWhere((speed) => speed >= currentSpeed);
    final baseIndex = safeIndex >= 0 ? safeIndex : _playbackSpeeds.length - 1;
    final nextIndex = (baseIndex + direction).clamp(
      0,
      _playbackSpeeds.length - 1,
    );

    await setPlaybackSpeed(_playbackSpeeds[nextIndex]);
  }

  void handleMouseMove(Offset position) {
    if (_isDisposed) return;
    _mouseMoveDebounce.call(
      leading: () {
        _uiManager.handleMouseMove(position);
      },
      trailing: () {
        _uiManager.handleMouseMove(position);
      },
    );
  }

  void showMoreMenu() => _uiManager.showMoreMenu();
  void hideMoreMenu() => _uiManager.hideMoreMenu();

  void showEpisodeList() {
    if (_isDisposed) return;
    refreshHistory();
    _uiManager.showEpisodeList();
  }

  void hideEpisodeList() => _uiManager.hideEpisodeList();

  void toggleEpisodeList() {
    if (_isDisposed) return;
    if (visibility.showEpisodeList) {
      hideEpisodeList();
    } else {
      showEpisodeList();
    }
  }

  void toggleFullscreen() {
    if (_isDisposed) return;
    _uiManager.handleFullscreenToggle();
  }

  void togglePip() {
    if (_isDisposed) return;
    _uiManager.handlePictureInPicture();
  }

  /// Reconcile the player's view-mode state with a SYSTEM-initiated change.
  ///
  /// The fullscreen/PiP toggles above are optimistic — they flip internal
  /// state when the SDK itself drives the transition. When the OS does it
  /// instead (user presses Esc / the macOS green button, swipes PiP away,
  /// Android auto-enters PiP on home), the host should call this with the
  /// actual state so controls render in the correct mode and the next toggle
  /// doesn't invert.
  void notifyViewMode({bool? isFullscreen, bool? isPip}) {
    if (_isDisposed) return;
    _uiManager.setViewMode(isFullscreen: isFullscreen, isPip: isPip);
  }

  // ===============================================================
  // Input Handling
  // ===============================================================

  void handleKeyboardShortcut(String shortcut) {
    if (_isDisposed) return;

    // A resume/replay dialog is modal: the control bars behind it are
    // IgnorePointer-blocked, so a shortcut that slipped through would act on a
    // player the user can no longer reach — pressing space (the most reflexive
    // "just play it" key) started playback from 0:00 UNDER the dialog, with no
    // way to pause, seek or dismiss. Route the dialog's own keys, swallow the
    // rest.
    final dialog = _uiManager.currentVisibility;
    if (dialog.showResumeDialog || dialog.showReplayDialog) {
      _handleDialogShortcut(shortcut, isReplay: dialog.showReplayDialog);
      return;
    }

    _uiManager.handleKeyboardInteraction();
    switch (shortcut) {
      case 'space':
        togglePlayPause();
        break;
      case 'f':
        toggleFullscreen();
        break;
      case 'm':
        toggleMute();
        break;
      case 'arrow_left':
        const amount = Duration(seconds: -5);
        seekRelative(amount);
        showSeekFeedback(amount);
        break;
      case 'arrow_right':
        const amount = Duration(seconds: 5);
        seekRelative(amount);
        showSeekFeedback(amount);
        break;
      case 'arrow_up':
        setVolume((audio.volume + 0.1).clamp(0.0, 1.0));
        break;
      case 'arrow_down':
        setVolume((audio.volume - 0.1).clamp(0.0, 1.0));
        break;
      case 'j':
        const amountJ = Duration(seconds: -10);
        seekRelative(amountJ);
        showSeekFeedback(amountJ);
        break;
      case 'l':
        const amountL = Duration(seconds: 10);
        seekRelative(amountL);
        showSeekFeedback(amountL);
        break;
      case '>':
        stepPlaybackSpeed(1);
        break;
      case '<':
        stepPlaybackSpeed(-1);
        break;
      case 'escape':
        if (visibility.showEpisodeList) {
          hideEpisodeList();
        } else if (view.isFullscreen) {
          _uiManager.handleFullscreenToggle();
        }
        break;
    }
  }

  // ===============================================================
  // Internal bindings & Disposal
  // ===============================================================

  void _bindStreams() {
    _lifecycleSub = lifecycleStream.listen((state) {
      if (_isDisposed) return;

      final previousState = _lastLifecycle;
      _lastLifecycle = state;

      _uiManager.updatePlaybackState(
        isPlaying: state.isPlaying,
        isInitialized: state.isInitialized,
      );

      // Event derivation (MediaInitialized / PlaybackStarted / PlaybackPaused)
      // lives in the emitter; the side effects on the same transitions follow.
      _events.onLifecycleTransition(
        previous: previousState,
        next: state,
        mediaDuration: position.duration,
      );

      // Status Transitions — side effects only, events emitted above.
      if (state.status != previousState.status) {
        if (state.isPlaying) {
          _applyWakelock(true);
          // The sweep's decoder competes with the foreground for mdk's
          // render-path lock (see _maybeStartSpriteSweep). Resuming playback
          // evicts it; tiles already stored stay, and the next pause resumes
          // the sweep past them.
          _spriteSweepService?.cancelSweep();
        } else if (state.status == PlaybackStatus.paused) {
          _applyWakelock(false);
          // Paused is the sweep's window: the foreground decoder is parked,
          // so the lock is uncontended. Uses the last known position state.
          _maybeStartSpriteSweep(_lastPosition);

          // Save history only on TRANSITION to paused. Switch guards: while
          // switching, media.currentEpisodeIndex is already advanced but the
          // position may still belong to the OLD episode — saving here would
          // corrupt the new episode's history.
          if (!_isSwitchingEpisode &&
              !_isSwitchingQuality &&
              media.video != null &&
              media.currentEpisode != null &&
              position.position > Duration.zero) {
            _mediaManager.saveProgressImmediate(
              episodeIndex: media.currentEpisodeIndex,
              positionMillis: position.position.inMilliseconds,
              durationMillis: position.duration.inMilliseconds,
            );
          }
        } else if (state.status == PlaybackStatus.ended) {
          // Real end-of-media signal (adapter completedStream). The
          // position-threshold heuristic in _onPositionUpdate stays as a
          // fallback; the emitter's once-per-episode latch guards against
          // double-emission.
          // Switch guards: a backend's stop() during episode/quality switching
          // must not read as a natural end.
          _applyWakelock(false);
          if (!_isSwitchingEpisode &&
              !_isSwitchingQuality &&
              !position.isLive) {
            final didEmit = _emitEpisodeEndAndMaybePlaylistEnd(
              showReplayOnPlaylistEnd: true,
              markEndedWhenHasNext: true,
              endPosition: position.duration,
              endDuration: position.duration,
            );
            // Natural end with a next episode: auto-advance when enabled
            // (fire-and-forget: this listener is synchronous).
            if (didEmit && hasNextEpisode && autoPlayNext) {
              unawaited(playNextEpisode());
            }
          }
        }
      }
    });

    // Position updates stay subscribed for the player's lifetime. A paused
    // player stops ticking, so this is effectively free while paused — and
    // keeping it active guarantees the final end-of-media position event is
    // still processed (natural-end detection / replay dialog) even though the
    // lifecycle now flips to paused at EOF via isPlayingStream reconciliation.
    _positionSub = positionStream.listen(_onPositionUpdate);

    _errorSub = errorStream.listen((state) {
      if (_isDisposed) return;
      if (state.error != null) {
        _events.emit(MediaLoadFailed(state.error!));
      }
    });

    // The 10s-of-playback gate only guards sweep START; a network dip
    // mid-sweep needs the sweep to yield too — the foreground video always
    // wins the pipe. Cancel is cheap: the next stable stretch re-triggers
    // and the sweep RESUMES from its last tile, not from zero.
    _sweepBufferingSub = bufferingStream.listen((state) {
      if (_isDisposed || !state.isBuffering) return;
      // Cooldown, or a flapping connection restarts the sweep on every
      // buffering exit and each restart costs a resolve+open cycle.
      _spriteSweepService?.cancelSweep(cooldown: const Duration(seconds: 30));
    });
  }

  /// Extracted frame-dependent logic: Runs ONLY when explicitly allowed
  Future<void> _onPositionUpdate(PlaybackPositionState state) async {
    if (_isDisposed) return;

    // --- Seek Events --- (edge detection + end-event re-arm in the emitter;
    // must run BEFORE _lastPosition is overwritten, it is the "from" value)
    _events.onPositionUpdate(previous: _lastPosition, next: state);

    _lastPosition = state;

    _maybeHintMarkerSetup(state);

    // --- Auto Skip Outro Logic (delegated) ---
    if (!_isSkippingOutro && !_hasSkippedOutro && !state.isSeeking) {
      // Snapshot BEFORE the await: a successful skip advances the episode via
      // playNextEpisode inside the delegate, so reading media.* afterwards
      // would attribute the end events to the NEW episode.
      final processingEpisodeIndex = media.currentEpisodeIndex;
      final processingEpisode = media.currentEpisode;
      final hadNextEpisode = hasNextEpisode;
      final skipped = await _skipDelegate.checkAndSkipOutro(
        position: state,
        setting: effectiveSkipSetting,
        // Quality switches also hold the switch lock — attempting an
        // auto-advance during one would be silently dropped and then latch
        // _hasSkippedOutro, killing auto-advance for the whole episode.
        isSwitchingEpisode: _isSwitchingEpisode || _isSwitchingQuality,
        pendingResumeCheck: _pendingResumeCheck,
        hasNextEpisode: hadNextEpisode,
        playNextEpisode: playNextEpisode,
        pause: pause,
      );
      if (skipped) {
        // Identify if it was a next-episode skip or a playlist-end skip.
        // (No replay dialog here; auto-skip-outro auto-advances instead.)
        _emitEpisodeEndAndMaybePlaylistEnd(
          showReplayOnPlaylistEnd: false,
          markEndedWhenHasNext: false,
          episodeOverride: processingEpisode,
          episodeIndexOverride: processingEpisodeIndex,
          hasNextOverride: hadNextEpisode,
        );

        _isSkippingOutro = true;
        // Only mark as skipped if we are still on the same episode (i.e. didn't switch)
        if (media.currentEpisodeIndex == processingEpisodeIndex) {
          _hasSkippedOutro = true;
        }

        // Reset flag after delay
        Future.delayed(const Duration(milliseconds: 500), () {
          _isSkippingOutro = false;
        });

        // The skip already handled this tick (episode advanced or paused at
        // outro) — don't fall through to natural-end detection / history save
        // with a position that belongs to the previous episode.
        return;
      }
    }

    // --- Natural End Detection ---
    if (!_isSkippingOutro &&
        !_events.hasEmittedEpisodeEnd &&
        !state.isSeeking &&
        !state.isLive &&
        state.duration > Duration.zero &&
        state.position >= state.duration - const Duration(milliseconds: 200)) {
      final didEmit = _emitEpisodeEndAndMaybePlaylistEnd(
        showReplayOnPlaylistEnd: true,
        markEndedWhenHasNext: true,
        endPosition: state.position,
        endDuration: state.duration,
      );
      // Natural end with a next episode: auto-advance when enabled.
      // (The emitter's latch, set above, makes this fire exactly once
      // across the heuristic and ended-status paths.)
      if (didEmit && hasNextEpisode && autoPlayNext) {
        await playNextEpisode();
        return;
      }
    }

    // Save history periodically
    final isResumeDialogShowing = visibility.showResumeDialog;
    final isReplayDialogShowing = visibility.showReplayDialog;

    // position > 0 matches the three saveProgressImmediate sites, which have
    // always guarded it. Without it any moment the player legitimately sits at
    // 0:00 with history on file — a dismissed resume prompt, a fresh load that
    // slipped the gate — writes that 0 straight over the stored position, and
    // a run under 30s stops offering to resume at all.
    if (!_pendingResumeCheck &&
        !_isSwitchingEpisode &&
        !isResumeDialogShowing &&
        !isReplayDialogShowing &&
        state.position > Duration.zero &&
        media.video != null &&
        media.currentEpisode != null) {
      unawaited(
        _mediaManager.saveProgress(
          episodeIndex: media.currentEpisodeIndex,
          positionMillis: state.position.inMilliseconds,
          durationMillis: state.duration.inMilliseconds,
        ),
      );
    }

    _maybeStartSpriteSweep(state);
  }

  /// Kick off the background sprite sweep once THIS episode's playback has
  /// proven stable. Cheap bool checks on the position tick; every condition
  /// after the covers() check runs at most once per episode.
  ///
  /// The 10s-of-playback threshold is the bandwidth guard: the sweep shares
  /// the pipe with the video the user is watching, so it must not pile onto
  /// a startup that is still fighting to buffer.
  void _maybeStartSpriteSweep(PlaybackPositionState state) {
    if (!config.behavior.enableThumbnail) return;
    if (state.isLive || state.position < const Duration(seconds: 10)) return;
    if (buffering.isBuffering || _isSwitchingEpisode || _isSwitchingQuality) {
      return;
    }
    // NEVER while the foreground is playing. Two mdk players decoding at once
    // share one internal render-path mutex, and a 3-second sample of a live
    // hang showed the loser waiting on that lock in 1338/1338 frames while
    // audio (a different path) ran on — the user sees a frozen picture with
    // working sound. Sweeps run when playback is paused or ended; on resume
    // the play handler cancels any sweep in flight.
    if (lifecycle.isPlaying) return;

    final service = _spriteService();
    if (service == null || service.isSweeping) return;

    // The episode being watched first; once it is covered, its neighbour —
    // detection needs a second episode to compare against, and the tile cache
    // dies with the controller, so waiting for the user to watch two in a row
    // means the feature would essentially never fire.
    //
    // Driven from the position tick rather than one-shot off sweep
    // completion: startSweep can decline (buffering cooldown, a sweep already
    // in flight), and a one-shot attempt that lands during a cooldown gives
    // up forever. Here the next tick just tries again.
    final target = _nextSweepTarget(service);
    if (target == null) return;

    final quality = SpriteSweepService.pickSweepQuality(
      media.episodes[target].qualities,
    );
    if (quality == null) return;
    service.startSweep(episodeIndex: target, url: quality.source.path);
  }

  /// The episode a sweep should cover next, or null when everything worth
  /// sweeping is covered.
  int? _nextSweepTarget(SpriteSweepService service) {
    final episodes = media.episodes;
    if (episodes.isEmpty) return null;
    final current = media.currentEpisodeIndex;
    if (!service.covers(current)) return current;
    // The neighbour sweep exists ONLY to give detection a partner. Once this
    // episode has markers — found here, or from a stored hash set, or placed
    // by hand — it has nothing left to buy, and a second five-minute 16x sweep
    // is bandwidth taken from the stream the user is watching.
    if (media.episodeMarkers.containsKey(current)) return null;
    // One neighbour is enough: detection needs a pair, not a season.
    for (final index in [current + 1, current - 1]) {
      if (index < 0 || index >= episodes.length) continue;
      if (!service.covers(index)) return index;
    }
    return null;
  }

  /// Lazily create the sprite service — only when an adapter package has
  /// registered a [FrameSweeper] factory. Null otherwise, and every sprite
  /// path degrades to the pre-sprite behavior.
  SpriteSweepService? _spriteService() {
    if (_isDisposed || !VidraPlayer.hasFrameSweeper) return null;
    final existing = _spriteSweepService;
    if (existing != null) return existing;
    final created = SpriteSweepService(
      createSweeper: () => VidraPlayer.createFrameSweeper()!,
      onHashesReady: _onEpisodeSwept,
    );
    _spriteSweepService = created;
    // Hashes from previous sessions, so the first sweep of this one already
    // has something to compare against. Fire-and-forget: a sweep takes
    // minutes, so this always lands first, and if it does not the next
    // completed sweep runs detection again anyway.
    _loadStoredHashes(created);
    return created;
  }

  Future<void> _loadStoredHashes(SpriteSweepService service) async {
    final stored = await _mediaManager.loadEpisodeHashes();
    if (_isDisposed || _spriteSweepService != service) return;
    for (final entry in stored.entries) {
      service.importHashes(entry.key, entry.value);
    }
    if (stored.isEmpty) return;
    logger.i('[Detect] loaded stored hashes for ${stored.length} episodes');

    // Compare them RIGHT NOW rather than waiting for this episode's own sweep.
    // Two stored episodes are already a comparable pair, so a series detected
    // in an earlier session can set its skip point the moment the player
    // opens — otherwise the viewer waits ~40s of sweeping for an answer that
    // has been on disk since yesterday, and an episode nobody ever sweeps
    // (episode 3 onwards) never gets one at all.
    final ready = service.episodesWithHashes();
    if (ready.length >= 2) _detectSharedRuns(ready.first);
  }

  /// A sweep finished: look for an intro/outro this episode shares with
  /// another swept one, and queue the next episode so the comparison has a
  /// partner to find.
  void _onEpisodeSwept(int episodeIndex) {
    if (_isDisposed) return;
    final blob = _spriteSweepService?.exportHashes(episodeIndex);
    if (blob != null) _mediaManager.saveEpisodeHashes(episodeIndex, blob);
    _detectSharedRuns(episodeIndex);
    // The neighbour sweep is NOT kicked off here — the position tick picks
    // the next target, so a decline (cooldown, in-flight) retries instead of
    // being lost.
  }

  /// Compare [episodeIndex] against every other swept episode and write
  /// `MarkerSource.detected` markers for both sides of the first match.
  ///
  /// Both sides on purpose: the partner is usually an episode the user has
  /// already watched, so writing only the new one would leave the series
  /// half-marked for no reason. Detected markers rank below manual ones, so
  /// this can never overwrite a skip point the user placed by hand.
  void _detectSharedRuns(int episodeIndex) {
    final service = _spriteSweepService;
    if (service == null) return;
    final mine = service.hashedTiles(episodeIndex);
    if (mine.length < 4) {
      logger.i('[Detect] ep=$episodeIndex has ${mine.length} tiles, too few');
      return;
    }

    final partners = service.episodesWithHashes()
      ..removeWhere((e) => e == episodeIndex);
    if (partners.isEmpty) {
      // The common case early on, and previously silent — which reads
      // identically to "detection is broken".
      logger.i(
        '[Detect] ep=$episodeIndex swept (${mine.length} tiles); '
        'no other episode swept yet, nothing to compare against',
      );
      return;
    }

    for (final other in partners) {
      if (other == episodeIndex) continue;
      final theirs = service.hashedTiles(other);

      final intro = SharedRunDetector.detectIntro(mine, theirs);

      // The tail is only searchable when BOTH sweeps actually reached the end
      // of their media: detectOutro measures backwards from the last tile, so
      // a half-swept episode makes it treat wherever the sweep stopped as the
      // credits. Measured — a mid-sweep episode against a complete one gave
      // `outro=23s`, and that got written as a detected marker.
      final tailUsable =
          service.isComplete(episodeIndex) && service.isComplete(other);
      final outro = tailUsable
          ? SharedRunDetector.detectOutro(mine, theirs)
          : null;

      // Every null carries its reason. A bare "outro=null" cannot be told
      // apart from "detection never ran" or "the bar was one bit too tight",
      // and those need completely different fixes — measured twice now, each
      // time costing an offline probe over dumped hashes to resolve.
      String side(String kind, SharedRun? run, DetectionMiss Function() miss) {
        if (run != null) return '$kind=${run.aSeconds}s';
        final m = miss();
        return '$kind=none(closest=${m.bestDistance}/64,'
            'longestRun=${m.bestRunTiles})';
      }

      logger.i(
        '[Detect] ep=$episodeIndex vs ep=$other '
        '${side('intro', intro, () => SharedRunDetector.describeIntroMiss(mine, theirs))} '
        '${tailUsable ? side('outro', outro, () => SharedRunDetector.describeOutroMiss(mine, theirs)) : 'outro=waiting(sweep incomplete)'} '
        '(${mine.length}v${theirs.length} tiles)',
      );
      if (intro == null && outro == null) continue;

      _writeDetected(episodeIndex, intro?.aSeconds, outro?.aSeconds);
      _writeDetected(other, intro?.bSeconds, outro?.bSeconds);
      _generaliseToSeries(intro, outro);
      _maybeSkipIntroNow();
      return; // One partner is enough; more would only re-confirm.
    }
  }

  /// Carry a detected run to the SERIES-wide setting, so episodes that were
  /// never swept skip too.
  ///
  /// Without this the feature only ever helps the two episodes that happened
  /// to be compared: detection writes per-episode markers, every other episode
  /// has none, and a viewer reaching episode 3 sits through the intro with the
  /// answer already on disk. The manual path (`setSkipPoint`) has always
  /// written both layers for exactly this reason.
  ///
  /// Two deliberate limits:
  /// - only when the series-wide value is UNSET. It is a single number for the
  ///   whole show and the user may have typed it; a detector must not overwrite
  ///   a hand-entered one, and [EpisodeMarkers.outranks] cannot protect a
  ///   [PlayerSetting], which carries no source.
  /// - the SMALLER of the pair. The two episodes disagree (measured: 116s and
  ///   102s for the same series), and this value is applied blind to episodes
  ///   nobody has looked at. Skipping too little leaves a few seconds of intro;
  ///   skipping too much eats the opening scene.
  void _generaliseToSeries(SharedRun? intro, SharedRun? outro) {
    if (intro == null) return;
    if (playerSetting.skipIntro > 0) return;
    final seconds = intro.aSeconds < intro.bSeconds
        ? intro.aSeconds
        : intro.bSeconds;
    if (seconds <= 0) return;
    logger.i('[Detect] series-wide skipIntro set to ${seconds}s');
    updateSkipIntro(seconds);
  }

  /// Apply a marker that arrived WHILE the intro is still playing.
  ///
  /// The intro skip is decided once, at episode start, by the resume delegate.
  /// Detection finishes ~40s into playback, long after that decision — so the
  /// episode the intro was just found on would play its intro in full, with the
  /// marker sitting unused. Measured as "第二集不会自动跳".
  void _maybeSkipIntroNow() {
    if (_isDisposed || _isSwitchingEpisode || _isSwitchingQuality) return;
    final setting = effectiveSkipSetting;
    if (!setting.autoSkip || setting.skipIntro <= 0) return;
    final target = Duration(seconds: setting.skipIntro);
    final position = _lastPosition.position;
    // Only forward, and only from inside the intro: past it the user has
    // already watched through, and yanking them forward would cut content.
    if (position >= target || position < Duration.zero) return;
    logger.i(
      '[Detect] intro marker landed mid-intro; skipping '
      '${position.inSeconds}s -> ${target.inSeconds}s',
    );
    seek(target, SeekSource.external);
    _uiManager.showSkipIntroNotification();
  }

  void _writeDetected(int index, int? introEndSec, int? outroStartSec) {
    if (introEndSec == null && outroStartSec == null) return;
    _mediaManager.updateEpisodeMarkers(
      EpisodeMarkers(
        episodeIndex: index,
        introEnd: introEndSec == null ? null : Duration(seconds: introEndSec),
        outroStart: outroStartSec == null
            ? null
            : Duration(seconds: outroStartSec),
        source: MarkerSource.detected,
      ),
    );
  }

  /// Emit [EpisodeEnded] and, when this is the final episode, [PlaylistEnded].
  /// Centralizes the end-of-episode event sequence shared by the auto-skip-outro
  /// and natural-end paths so the two can never drift apart.
  ///
  /// The `episode*`/`hasNext*` overrides let callers pass values SNAPSHOTTED
  /// BEFORE an await that may advance the episode (auto-skip's playNextEpisode)
  /// so the events are attributed to the episode that actually ended.
  ///
  /// Returns true when the events were emitted (false when already emitted or
  /// no episode) — callers use this to trigger auto-advance exactly once.
  bool _emitEpisodeEndAndMaybePlaylistEnd({
    required bool showReplayOnPlaylistEnd,
    required bool markEndedWhenHasNext,
    Duration? endPosition,
    Duration? endDuration,
    VideoEpisode? episodeOverride,
    int? episodeIndexOverride,
    bool? hasNextOverride,
  }) {
    final currentEp = episodeOverride ?? media.currentEpisode;
    if (currentEp == null) return false;

    final result = _events.emitEpisodeEnd(
      episode: currentEp,
      episodeIndex: episodeIndexOverride ?? media.currentEpisodeIndex,
      hasNext: hasNextOverride ?? hasNextEpisode,
      markEndedWhenHasNext: markEndedWhenHasNext,
      video: media.video,
      episodes: media.episodes,
    );

    if (result.playlistEnded &&
        showReplayOnPlaylistEnd &&
        endPosition != null &&
        endDuration != null) {
      _uiManager.showReplayDialog(
        ResumeState(
          positionMillis: endPosition.inMilliseconds,
          durationMillis: endDuration.inMilliseconds,
        ),
      );
    }
    return result.emitted;
  }

  /// Keep the screen awake while playing; release it otherwise.
  bool _wakelockEnabled = false;
  void _applyWakelock(bool keepAwake) {
    if (_isDisposed && keepAwake) return;
    if (_wakelockEnabled == keepAwake) return;
    _wakelockEnabled = keepAwake;
    // Fire-and-forget, but await internally so the plugin's async errors (it
    // can throw / be a no-op on some targets and in tests with no platform
    // channel) are caught instead of escaping as unhandled exceptions.
    _setWakelock(keepAwake);
  }

  Future<void> _setWakelock(bool keepAwake) async {
    try {
      if (keepAwake) {
        await WakelockPlus.enable();
      } else {
        await WakelockPlus.disable();
      }
    } catch (e) {
      logger.w('[PlayerController] Wakelock toggle failed: $e');
    }
  }

  void _bindWindowEvents() {
    _windowSub = _windowManager.eventStream.listen((event) {
      if (_isDisposed) return;

      switch (event.type) {
        case WindowEventType.focusGained:
          _uiManager.updateWindowState(hasFocus: true);
          _playbackManager.refreshState();
          break;
        case WindowEventType.focusLost:
          _uiManager.updateWindowState(hasFocus: false);
          break;
        case WindowEventType.minimized:
          _uiManager.updateWindowState(isMinimized: true);

          final isPip = view.isPip;
          if (config.behavior.pauseOnMinimize &&
              lifecycle.isPlaying &&
              !isPip) {
            pause();
          }
          // Do NOT force pause updates here.
          // If paused above, the listener on lifecycleStream will pause updates.
          // If not paused (e.g. background audio or PiP), we keep updates running.
          break;
        case WindowEventType.restored:
          _uiManager.updateWindowState(isMinimized: false);
          break;
        // NOTE: system-initiated fullscreen/PiP reconciliation is NOT handled
        // here. WindowEventManager only observes app-lifecycle transitions and
        // never emits fullscreen/PiP events (there is no external sink), so
        // those cases were unreachable. The single reconciliation path is the
        // public notifyViewMode() API — hosts relay native fullscreen/PiP
        // callbacks through it.
        case WindowEventType.visibilityChanged:
          final isVisible = event.data as bool;
          _uiManager.updateWindowState(isMinimized: !isVisible);
          if (isVisible) {
            _playbackManager.refreshState();
          } else {
            final isPip = view.isPip;
            if (!isPip &&
                config.behavior.pauseOnMinimize &&
                lifecycle.isPlaying) {
              pause();
            }
            // Same logic: let pause() status change handle the stream pausing.
          }
          break;
        default:
          break;
      }
    });
  }

  void setLocale(VidraLocale locale) {
    if (_isDisposed) return;
    config = config.copyWith(locale: locale);
    localization = VidraLocalization(locale);
    // Trigger a visibility update to force UI rebuilds of components watching the controller
    _uiManager.refresh();
  }

  /// Update the player theme dynamically.
  void setTheme(PlayerUITheme theme) {
    if (_isDisposed) return;
    config = config.copyWith(theme: theme);
    // Trigger a visibility update to force UI rebuilds of components watching the controller
    _uiManager.refresh();
  }

  /// Applies platform invariants that every config write path must enforce.
  /// Currently: thumbnails are backed by a macOS-only native generator, so
  /// force `enableThumbnail` off elsewhere. Centralized here so no write path
  /// (constructor / [setEnableThumbnail] / [updateConfig]) can forget it.
  static PlayerConfig _normalizeConfig(PlayerConfig c) {
    // enableThumbnail used to be forced off away from macOS because the
    // native generator was the only preview source. With a FrameSweeper
    // registered, sprite previews work everywhere — forcing the flag off
    // would kill the sweep on exactly the platforms it exists for.
    if (!Platform.isMacOS &&
        !VidraPlayer.hasFrameSweeper &&
        c.behavior.enableThumbnail) {
      return c.copyWith(behavior: c.behavior.copyWith(enableThumbnail: false));
    }
    return c;
  }

  void setEnableThumbnail(bool enabled) {
    if (_isDisposed) return;
    config = _normalizeConfig(
      config.copyWith(
        behavior: config.behavior.copyWith(enableThumbnail: enabled),
      ),
    );
    _uiManager.updateBehavior(config.behavior);
    _uiManager.refresh();
  }

  /// Update the entire player configuration dynamically.
  void updateConfig(PlayerConfig newConfig) {
    if (_isDisposed) return;
    config = _normalizeConfig(newConfig);

    // Apply specific changes that require immediate logic updates
    if (config.locale != null) {
      localization = VidraLocalization(config.locale!);
    }

    // Propagate to managers that snapshot config at construction, otherwise
    // runtime changes to loop / auto-hide / hover would silently no-op.
    // Use the normalized config so managers never see the un-gated behavior.
    _playbackManager.updateConfig(config);
    _uiManager.updateBehavior(config.behavior);

    // Trigger UI refresh
    _uiManager.refresh();
  }

  bool get enableThumbnail {
    return config.behavior.enableThumbnail && media.currentEpisode != null;
  }

  // Controller-owned thumbnail manager, keyed by media URL, so the LRU cache
  // and native generator survive across hover sessions instead of being
  // recreated (and their cache dropped) on every preview mount.
  ThumbnailManager? _thumbnailManager;
  String? _thumbnailUrl;
  SpriteSweepService? _spriteSweepService;

  /// Get (or lazily create) the shared [ThumbnailManager] for [url].
  /// Switching to a different URL disposes the previous manager.
  ThumbnailManager thumbnailManagerFor(String url) {
    if (_isDisposed) {
      // A preview mounting during the dispose window must not resurrect a
      // cached manager nobody will ever dispose. Hand out an already-disposed
      // throwaway: its getThumbnail() short-circuits to null.
      return ThumbnailManager(url: url)..dispose();
    }
    if (_thumbnailManager == null || _thumbnailUrl != url) {
      _thumbnailManager?.dispose();
      _thumbnailManager = ThumbnailManager(
        url: url,
        // Bound to the CURRENT episode at lookup time, not creation time —
        // hover only ever previews the playing episode, and the manager is
        // recreated on every url change anyway.
        spriteLookup: (seconds) =>
            _spriteSweepService?.lookup(media.currentEpisodeIndex, seconds),
      );
      _thumbnailUrl = url;
    }
    return _thumbnailManager!;
  }

  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;

    // Stop audio/video output immediately — the final progress save below
    // must not keep media audibly playing behind a slow host repository.
    unawaited(_player.pause().catchError((_) {}));

    // Persist the final position before tearing down managers — a plain dispose
    // while still playing would otherwise lose up to the 10s save-throttle
    // window of progress. Bounded by a short timeout so an unresponsive host
    // repository can't stall teardown. Safe: MediaManager's token is
    // invalidated only by its own dispose() below.
    if (media.video != null &&
        media.currentEpisode != null &&
        position.position > Duration.zero &&
        position.duration > Duration.zero) {
      try {
        await _mediaManager
            .saveProgressImmediate(
              episodeIndex: media.currentEpisodeIndex,
              positionMillis: position.position.inMilliseconds,
              durationMillis: position.duration.inMilliseconds,
            )
            .timeout(const Duration(seconds: 2));
      } catch (e) {
        logger.w('[PlayerController] Final progress save failed: $e');
      }
    }

    // Release the screen wakelock.
    _applyWakelock(false);

    // Disposal cleanup (fire-and-forget: broadcast-stream cancels complete
    // synchronously and the sources are closed right after).
    unawaited(_lifecycleSub?.cancel());
    unawaited(_positionSub?.cancel());
    unawaited(_errorSub?.cancel());
    unawaited(_windowSub?.cancel());
    unawaited(_sweepBufferingSub?.cancel());

    // Internal
    _mouseMoveDebounce.dispose();
    _thumbnailManager?.dispose();
    _thumbnailManager = null;
    _spriteSweepService?.dispose();
    _spriteSweepService = null;

    // Managers
    _uiManager.dispose();
    _mediaManager.dispose();
    _audioManager.dispose();
    _playbackManager.dispose();
    _windowManager.dispose();

    _events.emit(const PlayerDisposed());
    unawaited(_events.close());

    await _player.dispose();
  }
}
