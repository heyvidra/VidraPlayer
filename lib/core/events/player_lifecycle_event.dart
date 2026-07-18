import '../model/model.dart';

/// Base class for all player lifecycle events.
///
/// This event system describes "what happened" in the player, primarily
/// used for external tracking, analytics, or UI coordination.
///
/// It does NOT drive the player's internal logic.
sealed class PlayerLifecycleEvent {
  const PlayerLifecycleEvent();
}

// ===================================
// Initialization / Media Events
// ===================================

/// Triggered when the PlayerController is fully constructed and ready for interaction.
class PlayerCreated extends PlayerLifecycleEvent {
  const PlayerCreated();
}

/// Triggered when media (video/metadata) is successfully initialized and ready to play.
///
/// Contains basic media properties like [duration] and [aspectRatio].
class MediaInitialized extends PlayerLifecycleEvent {
  final Duration duration;
  final double aspectRatio;

  const MediaInitialized({required this.duration, required this.aspectRatio});
}

/// Triggered when media fails to load due to network or decoding errors.
class MediaLoadFailed extends PlayerLifecycleEvent {
  final PlayerError error;

  const MediaLoadFailed(this.error);
}

// ===================================
// Playback Behavior Events
// ===================================

/// Triggered when playback state changes to valid "playing".
class PlaybackStarted extends PlayerLifecycleEvent {
  const PlaybackStarted();
}

/// Triggered when playback is paused by user or system.
class PlaybackPaused extends PlayerLifecycleEvent {
  const PlaybackPaused();
}

/// Triggered when playback resumes from a paused state.
class PlaybackResumed extends PlayerLifecycleEvent {
  const PlaybackResumed();
}

/// Triggered when playback is explicitly stopped.
class PlaybackStopped extends PlayerLifecycleEvent {
  const PlaybackStopped();
}

/// Triggered when a seek operation begins.
class PlaybackSeekStarted extends PlayerLifecycleEvent {
  final Duration from;

  const PlaybackSeekStarted({required this.from});
}

/// Triggered when a seek operation completes.
class PlaybackSeekCompleted extends PlayerLifecycleEvent {
  final Duration to;

  const PlaybackSeekCompleted({required this.to});
}

// ===================================
// Episode Lifecycle Events
// ===================================

/// Triggered when an episode actually starts playing (initially or after switch).
class EpisodeStarted extends PlayerLifecycleEvent {
  final int index;
  final VideoEpisode episode;

  const EpisodeStarted({required this.index, required this.episode});
}

/// Triggered when an episode finishes playing naturally (reaches end).
///
/// NOTE: This does NOT trigger on user-initiated skips or disposal.
class EpisodeEnded extends PlayerLifecycleEvent {
  final int index;
  final VideoEpisode episode;

  const EpisodeEnded({required this.index, required this.episode});
}

/// Triggered when the current episode index changes.
class EpisodeChanged extends PlayerLifecycleEvent {
  final VideoEpisode? from;
  final VideoEpisode to;

  const EpisodeChanged({required this.from, required this.to});
}

// ===================================
// Playlist Events
// ===================================

/// Triggered ONLY when the *last* episode in the playlist finishes naturally.
///
/// Use this for "Series Finished", "Show Next Flow", or "Up Next" signals.
///
/// **Triggers when:**
/// - The last episode reaches its end naturally.
/// - Auto-skip outro logic skips the end of the last episode.
///
/// **Does NOT trigger when:**
/// - User manually seeks to end.
/// - User manually switches episodes.
/// - Player is disposed.
class PlaylistEnded extends PlayerLifecycleEvent {
  final VideoMetadata? video;
  final List<VideoEpisode> episodes;

  const PlaylistEnded({required this.video, required this.episodes});
}

// ===================================
// Lifecycle Events
// ===================================

/// Triggered when the player is disposed and no longer usable.
class PlayerDisposed extends PlayerLifecycleEvent {
  const PlayerDisposed();
}
