import 'dart:async';

import '../core/events/player_lifecycle_event.dart';
import '../core/model/model.dart';
import '../core/state/states.dart';

/// Distills raw state transitions into the public [PlayerLifecycleEvent]
/// stream.
///
/// Owns the derivation rules and their bookkeeping — seek edge detection, the
/// once-per-episode end sequence — and nothing else: no managers, no UI, no
/// side effects. PlayerController listens to state, hands each transition
/// here, and keeps its side effects (wakelock, history saves, auto-advance,
/// dialogs) next to the same transitions.
class PlaybackEventEmitter {
  final _ctrl = StreamController<PlayerLifecycleEvent>.broadcast();

  bool _wasSeeking = false;

  /// "End events already fired for the episode currently playing." Set by
  /// [emitEpisodeEnd], re-armed by [rearmEpisodeEnd] (new episode / quality
  /// retry) and by a seek. The field this replaced was called
  /// `_hasEmittedPlaylistEnded`, which lied: it is set even when the playlist
  /// did NOT end, so that the natural-end heuristic and the ended-status path
  /// fire exactly once per episode between them.
  bool _episodeEndEmitted = false;

  /// The public `controller.lifecycleEvents` stream.
  Stream<PlayerLifecycleEvent> get stream => _ctrl.stream;

  /// Whether end-of-episode events already fired for the current episode.
  bool get hasEmittedEpisodeEnd => _episodeEndEmitted;

  /// Emit [event], silently dropping it after [close].
  void emit(PlayerLifecycleEvent event) {
    if (!_ctrl.isClosed) _ctrl.add(event);
  }

  /// Lifecycle transition -> [MediaInitialized] / [PlaybackStarted] /
  /// [PlaybackPaused].
  ///
  /// [mediaDuration] is the position state's duration at transition time —
  /// [MediaInitialized] carries it alongside the aspect ratio.
  void onLifecycleTransition({
    required PlaybackLifecycleState previous,
    required PlaybackLifecycleState next,
    required Duration mediaDuration,
  }) {
    if (next.isInitialized && !previous.isInitialized) {
      emit(
        MediaInitialized(duration: mediaDuration, aspectRatio: next.aspectRatio),
      );
    }

    if (next.status != previous.status) {
      if (next.isPlaying) {
        emit(const PlaybackStarted());
      } else if (next.status == PlaybackStatus.paused) {
        emit(const PlaybackPaused());
      }
    }
  }

  /// Seek edge detection: rising edge -> [PlaybackSeekStarted] carrying the
  /// pre-seek position, falling edge -> [PlaybackSeekCompleted]. A seek also
  /// re-arms the end-of-episode events — seeking away from the end means the
  /// episode can end again.
  void onPositionUpdate({
    required PlaybackPositionState previous,
    required PlaybackPositionState next,
  }) {
    if (next.isSeeking && !_wasSeeking) {
      _wasSeeking = true;
      emit(PlaybackSeekStarted(from: previous.position));
      _episodeEndEmitted = false;
    } else if (!next.isSeeking && _wasSeeking) {
      _wasSeeking = false;
      emit(PlaybackSeekCompleted(to: next.position));
    }
  }

  /// Emit [EpisodeEnded] and, when [hasNext] is false, [PlaylistEnded] — at
  /// most once per episode until [rearmEpisodeEnd].
  ///
  /// [markEndedWhenHasNext] controls whether an end WITH a next episode also
  /// latches the once-only guard (the natural-end paths pass true so the
  /// heuristic and the ended-status signal can't double-fire).
  ///
  /// Returns what fired so the caller can attach its side effects (replay
  /// dialog, auto-advance) without this class knowing about them.
  ({bool emitted, bool playlistEnded}) emitEpisodeEnd({
    required VideoEpisode episode,
    required int episodeIndex,
    required bool hasNext,
    required bool markEndedWhenHasNext,
    required VideoMetadata? video,
    required List<VideoEpisode> episodes,
  }) {
    if (_episodeEndEmitted) return (emitted: false, playlistEnded: false);

    emit(EpisodeEnded(index: episodeIndex, episode: episode));

    if (!hasNext) {
      emit(PlaylistEnded(video: video, episodes: episodes));
      _episodeEndEmitted = true;
      return (emitted: true, playlistEnded: true);
    }
    if (markEndedWhenHasNext) {
      _episodeEndEmitted = true;
    }
    return (emitted: true, playlistEnded: false);
  }

  /// Allow end-of-episode events to fire again (new episode, quality retry).
  void rearmEpisodeEnd() => _episodeEndEmitted = false;

  Future<void> close() => _ctrl.close();
}
