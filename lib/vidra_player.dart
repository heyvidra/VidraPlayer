/// VidraPlayer - A powerful Flutter video player SDK
///
/// This library provides a comprehensive video player solution with:
/// - Multi-episode support
/// - Quality switching
/// - History and resume functionality
/// - Customizable themes and behaviors
/// - Keyboard shortcuts
///
/// ## Setup
///
/// Register a player factory before creating a controller:
///
/// ```dart
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   VidraPlayerKit.ensureInitialized();
///   runApp(const MyApp());
/// }
/// ```
///
/// ## Basic Usage
///
/// ```dart
/// import 'package:vidra_player/vidra_player.dart';
///
/// // player: is optional — adapter is auto-created from ensureInitialized
/// final controller = PlayerController(
///   config: PlayerConfig(
///     theme: PlayerUITheme.dark(),
///     locale: VidraLocale.en,
///   ),
///   video: videoMetadata,
///   episodes: episodes,
/// );
///
/// // In your widget tree
/// VideoPlayerWidget(controller: controller);
///
/// // Don't forget to dispose
/// controller.dispose();
/// ```
library;

// ============================================
// PUBLIC API - SDK Users Interface
// ============================================

// SDK Initialization
export 'vidra_player_sdk.dart' show VidraPlayer, VidraPlayerFactory;

// Core Controller
export 'controller/player_controller.dart' show PlayerController;

// Main Widget
export 'ui/player_widget.dart' show VideoPlayerWidget;

// Configuration Models
export 'core/model/player_config.dart' show PlayerConfig;
export 'core/model/player_ui_theme.dart' show PlayerUITheme;
export 'core/model/player_locale.dart' show VidraLocale;
export 'core/model/player_behavior.dart' show PlayerBehavior;
export 'core/model/player_features.dart' show PlayerFeatures;

// Video Models
export 'core/model/video_metadata.dart' show VideoMetadata;
export 'core/model/video_episode.dart' show VideoEpisode, EpisodeHistory;
export 'core/model/video_quality.dart' show VideoQuality;
export 'core/model/video_source.dart' show VideoSource, VideoSize;

// Localization
export 'core/localization/localization.dart' show VidraLocalization;

// Lifecycle Events — the documented `controller.lifecycleEvents` stream API.
// Without these exports the README's pattern-matching example cannot compile.
export 'core/events/player_lifecycle_event.dart'
    show
        PlayerLifecycleEvent,
        PlayerCreated,
        MediaInitialized,
        MediaLoadFailed,
        PlaybackStarted,
        PlaybackPaused,
        PlaybackResumed,
        PlaybackStopped,
        PlaybackSeekStarted,
        PlaybackSeekCompleted,
        EpisodeStarted,
        EpisodeEnded,
        EpisodeChanged,
        PlaylistEnded,
        PlayerDisposed;

// State types surfaced by the controller's public streams & getters.
export 'core/state/playback_lifecycle.dart' show PlaybackLifecycleState;
export 'core/state/playback_position.dart'
    show PlaybackPositionState, SeekSource;
export 'core/state/media_context.dart' show MediaContextState;
export 'core/state/audio.dart' show AudioState;
export 'core/state/view_mode.dart' show ViewModeState;
export 'core/state/buffering.dart' show BufferingState;
export 'core/state/error.dart' show ErrorState;
export 'core/state/quality_switching.dart' show SwitchingState;
export 'core/state/ui_visibility.dart' show UIVisibilityState;
export 'core/state/resume.dart' show ResumeState;

// Supporting models referenced by the public surface.
export 'core/model/player_error.dart' show PlayerError;
export 'core/model/buffer_range.dart' show BufferRange;
export 'core/model/enums.dart' show PlaybackStatus, VideoSourceType;
export 'core/model/player_setting.dart' show PlayerSetting;

// Extension points — implementing a custom playback backend, history
// repository, or window integration requires these interfaces.
export 'core/interfaces/video_player.dart' show IVideoPlayer;
export 'core/adapters/base_video_player_adapter.dart'
    show BaseVideoPlayerAdapter, OpenResult;
export 'core/interfaces/media_repository.dart' show MediaRepository;
export 'core/interfaces/window_delegate.dart' show WindowDelegate;
export 'adapters/window/standard_window_delegate.dart'
    show StandardWindowDelegate;

// ============================================
// INTERNAL IMPLEMENTATION
// All other files are internal and should not
// be imported directly by SDK users.
// ============================================
