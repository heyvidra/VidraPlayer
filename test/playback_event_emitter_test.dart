// The emitter is the extracted transition->event derivation from
// PlayerController. These tests pin the rules in isolation; the end-to-end
// ordering (events interleaved with side effects) stays covered by
// player_controller_test.dart.

import 'package:flutter_test/flutter_test.dart';
import 'package:vidra_player/controller/playback_event_emitter.dart';
import 'package:vidra_player/core/events/player_lifecycle_event.dart';
import 'package:vidra_player/core/model/model.dart';
import 'package:vidra_player/core/state/states.dart';

const _ep = VideoEpisode(index: 0, title: 'ep1');

void main() {
  late PlaybackEventEmitter emitter;
  late List<PlayerLifecycleEvent> events;

  setUp(() {
    emitter = PlaybackEventEmitter();
    events = [];
    emitter.stream.listen(events.add);
  });

  tearDown(() => emitter.close());

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  group('lifecycle transitions', () {
    test('initialization edge emits MediaInitialized once', () async {
      const before = PlaybackLifecycleState();
      const after = PlaybackLifecycleState(isInitialized: true);
      emitter.onLifecycleTransition(
        previous: before,
        next: after,
        mediaDuration: const Duration(minutes: 5),
      );
      // Already-initialized -> initialized must NOT re-fire.
      emitter.onLifecycleTransition(
        previous: after,
        next: after,
        mediaDuration: const Duration(minutes: 5),
      );
      await settle();
      expect(events.whereType<MediaInitialized>(), hasLength(1));
      final init = events.single as MediaInitialized;
      expect(init.duration, const Duration(minutes: 5));
    });

    test('status change to playing/paused emits, same status is silent',
        () async {
      const idle = PlaybackLifecycleState();
      const playing = PlaybackLifecycleState(
        status: PlaybackStatus.playing,
        isPlaying: true,
      );
      const paused = PlaybackLifecycleState(status: PlaybackStatus.paused);

      emitter.onLifecycleTransition(
        previous: idle,
        next: playing,
        mediaDuration: Duration.zero,
      );
      emitter.onLifecycleTransition(
        previous: playing,
        next: playing, // no status change -> nothing
        mediaDuration: Duration.zero,
      );
      emitter.onLifecycleTransition(
        previous: playing,
        next: paused,
        mediaDuration: Duration.zero,
      );
      await settle();
      expect(events, hasLength(2));
      expect(events[0], isA<PlaybackStarted>());
      expect(events[1], isA<PlaybackPaused>());
    });
  });

  group('seek edges', () {
    test('rising edge carries the pre-seek position, falling edge the target',
        () async {
      const before = PlaybackPositionState(position: Duration(seconds: 10));
      const seeking = PlaybackPositionState(
        position: Duration(seconds: 90),
        isSeeking: true,
      );
      const landed = PlaybackPositionState(position: Duration(seconds: 90));

      emitter.onPositionUpdate(previous: before, next: seeking);
      // Still seeking -> no duplicate start.
      emitter.onPositionUpdate(previous: seeking, next: seeking);
      emitter.onPositionUpdate(previous: seeking, next: landed);
      await settle();

      expect(events, hasLength(2));
      expect(
        (events[0] as PlaybackSeekStarted).from,
        const Duration(seconds: 10),
      );
      expect(
        (events[1] as PlaybackSeekCompleted).to,
        const Duration(seconds: 90),
      );
    });

    test('a seek re-arms the end-of-episode latch', () async {
      emitter.emitEpisodeEnd(
        episode: _ep,
        episodeIndex: 0,
        hasNext: false,
        markEndedWhenHasNext: true,
        video: null,
        episodes: const [_ep],
      );
      expect(emitter.hasEmittedEpisodeEnd, isTrue);

      emitter.onPositionUpdate(
        previous: const PlaybackPositionState(),
        next: const PlaybackPositionState(isSeeking: true),
      );
      expect(emitter.hasEmittedEpisodeEnd, isFalse);
    });
  });

  group('episode end sequence', () {
    test('last episode: EpisodeEnded then PlaylistEnded, latched', () async {
      final first = emitter.emitEpisodeEnd(
        episode: _ep,
        episodeIndex: 0,
        hasNext: false,
        markEndedWhenHasNext: true,
        video: null,
        episodes: const [_ep],
      );
      final second = emitter.emitEpisodeEnd(
        episode: _ep,
        episodeIndex: 0,
        hasNext: false,
        markEndedWhenHasNext: true,
        video: null,
        episodes: const [_ep],
      );
      await settle();

      expect(first, (emitted: true, playlistEnded: true));
      expect(second, (emitted: false, playlistEnded: false));
      expect(events, hasLength(2));
      expect(events[0], isA<EpisodeEnded>());
      expect(events[1], isA<PlaylistEnded>());
    });

    test('has next + markEnded latches without PlaylistEnded', () async {
      final result = emitter.emitEpisodeEnd(
        episode: _ep,
        episodeIndex: 0,
        hasNext: true,
        markEndedWhenHasNext: true,
        video: null,
        episodes: const [_ep],
      );
      await settle();

      expect(result, (emitted: true, playlistEnded: false));
      expect(events.single, isA<EpisodeEnded>());
      expect(emitter.hasEmittedEpisodeEnd, isTrue);
    });

    test('rearm allows the sequence to fire again', () async {
      emitter.emitEpisodeEnd(
        episode: _ep,
        episodeIndex: 0,
        hasNext: true,
        markEndedWhenHasNext: true,
        video: null,
        episodes: const [_ep],
      );
      emitter.rearmEpisodeEnd();
      final again = emitter.emitEpisodeEnd(
        episode: _ep,
        episodeIndex: 0,
        hasNext: true,
        markEndedWhenHasNext: true,
        video: null,
        episodes: const [_ep],
      );
      expect(again.emitted, isTrue);
    });
  });

  test('emit after close is dropped, not thrown', () async {
    await emitter.close();
    expect(() => emitter.emit(const PlayerCreated()), returnsNormally);
  });
}
