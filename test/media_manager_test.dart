import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vidra_player/core/interfaces/media_repository.dart';
import 'package:vidra_player/core/model/model.dart';
import 'package:vidra_player/core/state/media_context.dart';
import 'package:vidra_player/managers/media_manager.dart';

class FakeMediaRepository implements MediaRepository {
  final Completer<void> _saveCompleter = Completer<void>();
  PlayerSetting? savedSetting;
  EpisodeHistory? savedHistory;

  Future<void> get saveFuture => _saveCompleter.future;

  @override
  Future<List<EpisodeHistory>> getEpisodeHistories({
    required String videoId,
  }) async {
    return [];
  }

  @override
  Future<PlayerSetting> getPlayerSettings({required String videoId}) async {
    return PlayerSetting(videoId: videoId);
  }

  @override
  Future<void> saveEpisodeHistory(
    String videoId,
    EpisodeHistory history,
  ) async {
    savedHistory = history;
    // Simulate delay
    await Future.delayed(const Duration(milliseconds: 50));
    _saveCompleter.complete();
  }

  @override
  Future<void> savePlayerSettings(PlayerSetting setting) async {
    savedSetting = setting;
  }
}

void main() {
  test(
    'saveProgress does not throw StateError if disposed during async save',
    () async {
      final repository = FakeMediaRepository();
      final manager = MediaManager(repository: repository);

      // Initialize with some data so we can save progress
      manager.initialize(
        video: const VideoMetadata(
          id: 'v1',
          title: 'Test Video',
          coverUrl: 'http://test.com/cover.jpg',
        ),
        episodes: [const VideoEpisode(index: 0, title: 'Ep 1')],
      );

      // Trigger saveProgress
      // This uses a Throttle internally, so the first call runs immediately.
      unawaited(manager.saveProgress(
        episodeIndex: 0,
        positionMillis: 1000,
        durationMillis: 10000,
      ));

      // Dispose immediately while save is pending (awaiting repository)
      manager.dispose();

      // Wait for the async operation inside Throttle to complete.
      // The repository delay is 50ms. Waiting 100ms should be enough.
      // The unhandled exception should be caught by the test framework.
      await Future.delayed(const Duration(milliseconds: 100));
    },
  );

  test('saveProgress adds a new history entry to in-memory state', () async {
    final repository = FakeMediaRepository();
    final manager = MediaManager(repository: repository);

    manager.initialize(
      video: const VideoMetadata(
        id: 'v1',
        title: 'Test Video',
        coverUrl: 'http://test.com/cover.jpg',
      ),
      episodes: const [VideoEpisode(index: 0, title: 'Ep 1')],
    );

    await manager.saveProgress(
      episodeIndex: 0,
      positionMillis: 1000,
      durationMillis: 10000,
    );

    await Future.delayed(const Duration(milliseconds: 100));

    expect(manager.state.episodeHistory, hasLength(1));
    expect(manager.state.episodeHistory.first.positionMillis, 1000);
  });

  // Two episodes: ep0 has 3 qualities (360p/720p/1080p), ep1 has only 2
  // (360p/720p). Exercises quality carry-over-by-label and index clamping so a
  // switch never plays the wrong quality or RangeErrors on currentQuality.
  List<VideoEpisode> twoEpisodes() => const [
    VideoEpisode(index: 0, title: 'Ep 1', qualities: [
      VideoQuality(label: '360p', source: VideoSource.network('e0-360')),
      VideoQuality(label: '720p', source: VideoSource.network('e0-720')),
      VideoQuality(label: '1080p', source: VideoSource.network('e0-1080')),
    ]),
    VideoEpisode(index: 1, title: 'Ep 2', qualities: [
      VideoQuality(label: '360p', source: VideoSource.network('e1-360')),
      VideoQuality(label: '720p', source: VideoSource.network('e1-720')),
    ]),
  ];

  MediaManager managerWithEpisodes() {
    final manager = MediaManager(repository: FakeMediaRepository());
    manager.initialize(
      video: const VideoMetadata(id: 'v1', title: 'V', coverUrl: 'c'),
      episodes: twoEpisodes(),
    );
    return manager;
  }

  test('switchEpisode carries the selected quality across by label', () {
    final manager = managerWithEpisodes();
    manager.switchQuality(1); // 720p on ep0
    expect(manager.state.currentQuality?.label, '720p');

    manager.switchEpisode(1);
    // ep1 also has 720p → carried over, source resolves to ep1's 720p.
    expect(manager.state.currentQualityIndex, 1);
    expect(manager.state.currentQuality?.label, '720p');
    expect(manager.state.currentSource?.path, 'e1-720');
    manager.dispose();
  });

  test('switchEpisode resets quality index when the target lacks that label',
      () {
    final manager = managerWithEpisodes();
    manager.switchQuality(2); // 1080p on ep0 (index 2)
    expect(manager.state.currentQualityIndex, 2);

    manager.switchEpisode(1); // ep1 has no 1080p and only 2 qualities
    // Must not keep index 2 (would RangeError) — falls back to the first.
    expect(manager.state.currentQualityIndex, 0);
    expect(manager.state.currentQuality?.label, '360p');
    expect(manager.state.currentSource?.path, 'e1-360');
    manager.dispose();
  });

  test('currentQuality clamps a stale index instead of throwing', () {
    // A state whose quality index exceeds the current episode's range must not
    // throw from the UI-facing getters.
    const state = MediaContextState(
      episodes: [
        VideoEpisode(index: 0, title: 'Ep', qualities: [
          VideoQuality(label: '360p', source: VideoSource.network('x')),
        ]),
      ],
      currentQualityIndex: 5,
    );
    expect(state.currentQuality?.label, '360p');
    expect(state.currentSource?.path, 'x');
  });

  test('updateAutoSkip uses a default setting before settings load', () async {
    final repository = FakeMediaRepository();
    final manager = MediaManager(repository: repository);

    manager.initialize(
      video: const VideoMetadata(
        id: 'v1',
        title: 'Test Video',
        coverUrl: 'http://test.com/cover.jpg',
      ),
      episodes: const [VideoEpisode(index: 0, title: 'Ep 1')],
    );

    await manager.updateAutoSkip(false);

    expect(manager.state.playerSetting, isNotNull);
    expect(manager.state.playerSetting!.videoId, 'v1');
    expect(manager.state.playerSetting!.autoSkip, isFalse);
    expect(repository.savedSetting?.autoSkip, isFalse);
  });
}
