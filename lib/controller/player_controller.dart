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
import '../managers/thumbnail_manager.dart';
import '../managers/ui_manager.dart';
import '../managers/window_event_manager.dart';
import '../core/interfaces/video_player.dart';
import '../core/model/model.dart';
import '../core/state/states.dart';
import '../utils/event_control.dart';
import '../utils/log.dart';
import 'delegates/resume_delegate.dart';
import 'delegates/skip_delegate.dart';
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
  bool _isSkippingOutro = false; // Currently executing a skip action
  bool _hasSkippedOutro = false; // Already skipped for this episode

  // Subscriptions
  StreamSubscription<PlaybackLifecycleState>? _lifecycleSub;
  StreamSubscription<PlaybackPositionState>? _positionSub;
  StreamSubscription<ErrorState>? _errorSub;
  StreamSubscription<WindowEvent>? _windowSub;

  // Event System
  final _eventCtrl = StreamController<PlayerLifecycleEvent>.broadcast();
  bool _hasEmittedPlaylistEnded = false;
  bool _wasSeeking = false;

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
      _safeEmit(const PlayerCreated());
    });
  }

  void _safeEmit(PlayerLifecycleEvent event) {
    if (!_eventCtrl.isClosed) {
      _eventCtrl.add(event);
    }
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
  Stream<PlayerLifecycleEvent> get lifecycleEvents => _eventCtrl.stream;
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

    if (playerSetting.autoSkip && playerSetting.skipIntro > 0) {
      await seek(
        Duration(seconds: playerSetting.skipIntro),
        SeekSource.external,
      );
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
    if (_isDisposed || _mediaManager.state.currentEpisodeIndex == index) return;

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

    try {
      // Get target episode for display
      final targetEpisode =
          _mediaManager.state.episodes.isNotEmpty &&
              index < _mediaManager.state.episodes.length
          ? _mediaManager.state.episodes[index]
          : null;

      _hasEmittedPlaylistEnded = false; // Reset for new episode

      // Emit Change Event
      if (_mediaManager.state.currentEpisode != null && targetEpisode != null) {
        _safeEmit(
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
                logger.w('[PlayerController] Pre-switch progress save failed: $e');
              }),
        );
      }

      _mediaManager.switchEpisode(index);

      await _loadEpisode(index, switchEpisode: true);
      await play();

      // End switching state
      _playbackManager.endSwitching();

      // PERFORMANCE FIX: Removed unnecessary 500ms delay
      // The delay served no purpose and added latency to episode switches
    } catch (e) {
      logger.e('Error switching episode: $e');
      // Ensure switching state is cleared on error
      _playbackManager.endSwitching();
      rethrow;
    } finally {
      // Always reset the switching flag
      _isSwitchingEpisode = false;
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
    try {
      // Start switching state
      _playbackManager.startSwitching(targetQuality.label);

      final currentPosition = position.position;
      final wasPlaying = lifecycle.status == PlaybackStatus.playing;

      await _playbackManager.resetPlayer();

      // Open the target quality's source directly (we already resolved it as
      // targetQuality above — no need to mutate media state first).
      final ok = await _playbackManager.initialize(targetQuality.source);
      if (_isDisposed) {
        _playbackManager.endSwitching();
        return;
      }
      if (!ok) {
        // Open failed — keep the OLD quality index committed in media state so
        // the selector and currentSource stay truthful, and surface the error.
        _playbackManager.endSwitching();
        return;
      }

      _hasEmittedPlaylistEnded = false;

      // Restore audio/speed state after player reset
      await _audioManager.restoreState();

      // Commit the new quality only on success.
      _mediaManager.switchQuality(index);

      if (currentPosition > Duration.zero) {
        await seek(currentPosition, SeekSource.external);
      }
      if (wasPlaying || forcePlay) {
        await play();
      }
      // End switching state
      _playbackManager.endSwitching();
    } catch (e) {
      // Ensure state is cleared on error
      _playbackManager.endSwitching();
      rethrow;
    } finally {
      _isSwitchingQuality = false;
    }
  }

  Future<void> _loadEpisode(int index, {bool switchEpisode = false}) async {
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
    }
    // Resolve from the single source authority (media state was already
    // advanced to this episode+quality before _loadEpisode ran).
    final ok = await _playbackManager.initialize(
      _mediaManager.state.currentSource,
    );
    if (_isDisposed) return;
    if (!ok) {
      // Load failed — error already emitted. Don't drive audio/resume/play
      // against a player that never opened. Unblock saves: the resume check
      // that would normally clear the flag never runs on this path.
      _pendingResumeCheck = false;
      return;
    }
    // Restore audio/speed state after player reset
    await _audioManager.restoreState();
    if (_isDisposed) return;
    showControls();

    // Emit EpisodeStarted
    final currentEp = _mediaManager.state.currentEpisode;
    if (currentEp != null) {
      _safeEmit(EpisodeStarted(index: index, episode: currentEp));
    }

    // if (config.behavior.autoPlay) {
    //   // Optimisation: If history is enabled, we delay auto-play until
    //   // ResumeDelegate decides whether to seek (intro skip) or prompt (resume).
    //   // This prevents playing immediately then jumping, or playing then pausing.
    //   if (!config.features.enableHistory) {
    //     await play();
    //   }
    // }
    // Check restore for new episode (flag was set at the top of this method)
    _checkResumePlayback(index);
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

  void _checkResumePlayback(int episodeIndex) async {
    if (_isDisposed) {
      _pendingResumeCheck = false;
      return;
    }

    if (!config.features.enableHistory) {
      _pendingResumeCheck = false;
      // If history is disabled but auto-play is on, we play immediately here
      // because _loadEpisode deferred it.
      if (config.behavior.autoPlay) {
        await play();
      }
      return;
    }
    try {
      await _resumeDelegate.checkAndPromptResume(
        episodeIndex: episodeIndex,
        isInitialized: lifecycle.isInitialized,
        isDisposed: () => _isDisposed,
        seek: seek,
        pause: pause,
        play: play,
        getPlayerSetting: () => playerSetting,
        autoPlay: config.behavior.autoPlay,
      );
    } catch (e) {
      logger.e('[PlayerController] Resume check failed: $e');
      // If check fails, fallback to auto-play
      if (config.behavior.autoPlay) {
        await play();
      }
    } finally {
      // Clear checking flag so we can start saving new progress
      _pendingResumeCheck = false;
    }
  }

  Future<void> replayEpisode() async {
    if (_isDisposed) return;

    await seek(Duration.zero, SeekSource.external);
    _uiManager.hideReplayDialog();
    await play();
    _uiManager.showControlsTemporarily();
  }

  Future<void> dismissReplayDialog() async {
    if (_isDisposed) return;

    _uiManager.hideReplayDialog();
    await play();
    _uiManager.showControlsTemporarily();
  }

  PlayerSetting get playerSetting =>
      media.playerSetting ?? PlayerSetting(videoId: media.video!.id);

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

      // Emit Events - Initialized
      if (state.isInitialized && !previousState.isInitialized) {
        _safeEmit(
          MediaInitialized(
            duration: position.duration,
            aspectRatio: state.aspectRatio,
          ),
        );
      }

      // Status Transitions
      if (state.status != previousState.status) {
        if (state.isPlaying) {
          _safeEmit(const PlaybackStarted());
          _applyWakelock(true);
        } else if (state.status == PlaybackStatus.paused) {
          _safeEmit(const PlaybackPaused());
          _applyWakelock(false);

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
          // fallback; _hasEmittedPlaylistEnded guards against double-emission.
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
        _safeEmit(MediaLoadFailed(state.error!));
      }
    });
  }

  /// Extracted frame-dependent logic: Runs ONLY when explicitly allowed
  Future<void> _onPositionUpdate(PlaybackPositionState state) async {
    if (_isDisposed) return;

    // --- Seek Events ---
    if (state.isSeeking && !_wasSeeking) {
      _wasSeeking = true;
      _safeEmit(PlaybackSeekStarted(from: _lastPosition.position));
      _hasEmittedPlaylistEnded = false; // Reset on seek
    } else if (!state.isSeeking && _wasSeeking) {
      _wasSeeking = false;
      _safeEmit(PlaybackSeekCompleted(to: state.position));
    }

    _lastPosition = state;

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
        setting: playerSetting,
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
        !_hasEmittedPlaylistEnded &&
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
      // (_hasEmittedPlaylistEnded, set above, makes this fire exactly once
      // across the heuristic and ended-status paths.)
      if (didEmit && hasNextEpisode && autoPlayNext) {
        await playNextEpisode();
        return;
      }
    }

    // Save history periodically
    final isResumeDialogShowing = visibility.showResumeDialog;
    final isReplayDialogShowing = visibility.showReplayDialog;

    if (!_pendingResumeCheck &&
        !_isSwitchingEpisode &&
        !isResumeDialogShowing &&
        !isReplayDialogShowing &&
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
    if (_hasEmittedPlaylistEnded) return false;
    final currentEp = episodeOverride ?? media.currentEpisode;
    if (currentEp == null) return false;
    final episodeIndex = episodeIndexOverride ?? media.currentEpisodeIndex;
    final hasNext = hasNextOverride ?? hasNextEpisode;

    _safeEmit(EpisodeEnded(index: episodeIndex, episode: currentEp));

    if (!hasNext) {
      _safeEmit(PlaylistEnded(video: media.video, episodes: media.episodes));
      _hasEmittedPlaylistEnded = true;

      if (showReplayOnPlaylistEnd &&
          endPosition != null &&
          endDuration != null) {
        _uiManager.showReplayDialog(
          ResumeState(
            positionMillis: endPosition.inMilliseconds,
            durationMillis: endDuration.inMilliseconds,
          ),
        );
      }
    } else if (markEndedWhenHasNext) {
      _hasEmittedPlaylistEnded = true;
    }
    return true;
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
    if (!Platform.isMacOS && c.behavior.enableThumbnail) {
      return c.copyWith(
        behavior: c.behavior.copyWith(enableThumbnail: false),
      );
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
      _thumbnailManager = ThumbnailManager(url: url);
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

    // Internal
    _mouseMoveDebounce.dispose();
    _thumbnailManager?.dispose();
    _thumbnailManager = null;

    // Managers
    _uiManager.dispose();
    _mediaManager.dispose();
    _audioManager.dispose();
    _playbackManager.dispose();
    _windowManager.dispose();

    _safeEmit(const PlayerDisposed());
    unawaited(_eventCtrl.close());

    await _player.dispose();
  }
}
