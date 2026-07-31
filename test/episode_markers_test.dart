// Per-episode markers vs the series-wide PlayerSetting: which one the skip
// logic ends up acting on, and who is allowed to overwrite whom.

import 'package:flutter_test/flutter_test.dart';
import 'package:vidra_player/core/interfaces/media_repository.dart';
import 'package:vidra_player/core/model/model.dart';
import 'package:vidra_player/managers/media_manager.dart';

/// Implements ONLY MediaRepository — the shape every existing host has. It must
/// keep working, markers just don't persist.
class _LegacyRepository implements MediaRepository {
  @override
  Future<List<EpisodeHistory>> getEpisodeHistories({
    required String videoId,
  }) async => const [];
  @override
  Future<void> saveEpisodeHistory(String v, EpisodeHistory h) async {}
  @override
  Future<void> savePlayerSettings(PlayerSetting s) async {}
  @override
  Future<PlayerSetting> getPlayerSettings({required String videoId}) async =>
      PlayerSetting(videoId: videoId);
}

class _MarkerRepository extends _LegacyRepository
    implements EpisodeMarkerStore {
  final Map<int, EpisodeMarkers> stored = {};
  int saveCalls = 0;

  @override
  Future<List<EpisodeMarkers>> getEpisodeMarkers({
    required String videoId,
  }) async => stored.values.toList();

  @override
  Future<void> saveEpisodeMarkers(String videoId, EpisodeMarkers m) async {
    saveCalls++;
    stored[m.episodeIndex] = m;
  }
}

const _video = VideoMetadata(id: 'v1', title: 'T', coverUrl: 'c');
const _episodes = [
  VideoEpisode(index: 0, title: 'E1'),
  VideoEpisode(index: 1, title: 'E2'),
];

MediaManager _manager(MediaRepository repo) {
  final manager = MediaManager(repository: repo);
  manager.initialize(video: _video, episodes: _episodes);
  return manager;
}

void main() {
  group('EpisodeMarkers', () {
    test('outro tail is the distance from the end, clamped at zero', () {
      const m = EpisodeMarkers(
        episodeIndex: 0,
        outroStart: Duration(minutes: 22),
      );
      expect(m.outroTailSeconds(const Duration(minutes: 24)), 120);
      // Marker past the end of a shorter media must not go negative.
      expect(m.outroTailSeconds(const Duration(minutes: 10)), 0);
      expect(m.outroTailSeconds(Duration.zero), 0);
    });

    test('precedence runs chapter < detected < manual', () {
      const chapter = EpisodeMarkers(
        episodeIndex: 0,
        source: MarkerSource.chapter,
      );
      const manual = EpisodeMarkers(
        episodeIndex: 0,
        source: MarkerSource.manual,
      );
      expect(manual.outranks(chapter), isTrue);
      expect(chapter.outranks(manual), isFalse);
      // Same source re-runs, so a second probe can refresh its own value.
      expect(chapter.outranks(chapter), isTrue);
    });
  });

  group('MediaManager markers', () {
    test('a manual marker is not clobbered by a later chapter probe', () async {
      final repo = _MarkerRepository();
      final manager = _manager(repo);

      await manager.updateEpisodeMarkers(
        const EpisodeMarkers(
          episodeIndex: 0,
          introEnd: Duration(seconds: 90),
          source: MarkerSource.manual,
        ),
      );
      await manager.updateEpisodeMarkers(
        const EpisodeMarkers(
          episodeIndex: 0,
          introEnd: Duration(seconds: 5),
          source: MarkerSource.chapter,
        ),
      );

      expect(
        manager.state.currentMarkers?.introEnd,
        const Duration(seconds: 90),
      );
      expect(manager.state.currentMarkers?.source, MarkerSource.manual);
      expect(repo.saveCalls, 1, reason: 'the rejected write must not persist');

      manager.dispose();
    });

    test('markers are per episode, not per video', () async {
      final manager = _manager(_MarkerRepository());

      await manager.updateEpisodeMarkers(
        const EpisodeMarkers(episodeIndex: 1, introEnd: Duration(seconds: 60)),
      );

      expect(manager.state.currentMarkers, isNull, reason: 'on episode 0');
      manager.switchEpisode(1);
      expect(
        manager.state.currentMarkers?.introEnd,
        const Duration(seconds: 60),
      );

      manager.dispose();
    });

    test('stored markers load back on init', () async {
      final repo = _MarkerRepository();
      repo.stored[1] = const EpisodeMarkers(
        episodeIndex: 1,
        introEnd: Duration(seconds: 42),
        source: MarkerSource.detected,
      );

      final manager = _manager(repo);
      await manager.loadEpisodeMarkers();

      expect(
        manager.state.episodeMarkers[1]?.introEnd,
        const Duration(seconds: 42),
      );
      manager.dispose();
    });

    test('a repository without a marker store still works', () async {
      final manager = _manager(_LegacyRepository());

      // Must not throw, and markers stay live for the session.
      await manager.loadEpisodeMarkers();
      await manager.updateEpisodeMarkers(
        const EpisodeMarkers(episodeIndex: 0, introEnd: Duration(seconds: 30)),
      );

      expect(
        manager.state.currentMarkers?.introEnd,
        const Duration(seconds: 30),
      );
      manager.dispose();
    });
  });
}
