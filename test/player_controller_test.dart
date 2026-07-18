import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vidra_player/controller/player_controller.dart';
import 'package:vidra_player/core/events/player_lifecycle_event.dart';
import 'package:vidra_player/core/interfaces/window_delegate.dart';
import 'package:vidra_player/core/interfaces/media_repository.dart';
import 'package:vidra_player/core/interfaces/video_player.dart';
import 'package:vidra_player/core/model/model.dart';
import 'package:vidra_player/core/state/states.dart';

class FakeVideoPlayer implements IVideoPlayer {
  final _positionCtrl = StreamController<Duration>.broadcast();
  final _bufferingCtrl = StreamController<BufferingState>.broadcast();
  final _playingCtrl = StreamController<bool>.broadcast();
  final _liveCtrl = StreamController<bool>.broadcast();
  final _errorCtrl = StreamController<PlayerError?>.broadcast();
  final _bufferedCtrl = StreamController<List<BufferRange>>.broadcast();
  final _videoSizeCtrl = StreamController<VideoSize?>.broadcast();
  final _completedCtrl = StreamController<bool>.broadcast();

  final Duration _duration = const Duration(minutes: 2);
  Duration _position = Duration.zero;
  bool _isPlaying = false;
  bool _isLive = false;
  bool autoCompleteSeek = false;
  double lastPlaybackSpeed = 1.0;
  Duration? pendingSeekTarget;
  int resetCount = 0;
  final List<String> initializedSources = [];

  Completer<void>? _seekCompleter;

  @override
  Duration get duration => _duration;

  @override
  bool get isLive => _isLive;

  @override
  bool get isPlaying => _isPlaying;

  @override
  Duration get position => _position;

  @override
  VideoSize? get videoSize => const VideoSize(1920, 1080);

  @override
  Stream<List<BufferRange>> get bufferedStream => _bufferedCtrl.stream;

  @override
  Stream<BufferingState> get bufferingStream => _bufferingCtrl.stream;

  @override
  Stream<PlayerError?> get errorStream => _errorCtrl.stream;

  @override
  Stream<bool> get isLiveStream => _liveCtrl.stream;

  @override
  Stream<bool> get isPlayingStream => _playingCtrl.stream;

  @override
  Stream<Duration> get positionStream => _positionCtrl.stream;

  @override
  Stream<VideoSize?> get videoSizeStream => _videoSizeCtrl.stream;

  @override
  Stream<bool> get completedStream => _completedCtrl.stream;

  void emitCompleted(bool completed) {
    _completedCtrl.add(completed);
  }

  @override
  Future<void> dispose() async {
    await _positionCtrl.close();
    await _bufferingCtrl.close();
    await _playingCtrl.close();
    await _liveCtrl.close();
    await _errorCtrl.close();
    await _bufferedCtrl.close();
    await _videoSizeCtrl.close();
    await _completedCtrl.close();
  }

  @override
  Future<void> initialize(VideoSource source) async {
    initializedSources.add(source.path);
    _position = Duration.zero;
    _isPlaying = false;
    _isLive = false;
    _videoSizeCtrl.add(const VideoSize(1920, 1080));
    _bufferingCtrl.add(const BufferingState(isBuffering: false));
    _liveCtrl.add(false);
    _playingCtrl.add(false);
    _positionCtrl.add(Duration.zero);
  }

  @override
  Future<void> pause() async {
    _isPlaying = false;
    _playingCtrl.add(false);
  }

  @override
  Future<void> play() async {
    _isPlaying = true;
    _playingCtrl.add(true);
  }

  @override
  Future<void> reset() async {
    resetCount++;
    _position = Duration.zero;
    _isPlaying = false;
    _playingCtrl.add(false);
    _positionCtrl.add(Duration.zero);
  }

  @override
  Widget render({
    Key? key,
    BoxFit fit = BoxFit.contain,
    Alignment alignment = Alignment.center,
  }) {
    return SizedBox(key: key);
  }

  @override
  Future<void> seek(Duration position) {
    pendingSeekTarget = position;
    _position = position;
    _positionCtrl.add(position);
    if (autoCompleteSeek) {
      return Future.value();
    }
    _seekCompleter = Completer<void>();
    return _seekCompleter!.future;
  }

  void completePendingSeek() {
    final target = pendingSeekTarget;
    final completer = _seekCompleter;
    if (target == null || completer == null || completer.isCompleted) return;

    _position = target;
    _positionCtrl.add(target);
    completer.complete();
  }

  @override
  Future<void> setPlaybackSpeed(double speed) async {
    lastPlaybackSpeed = speed;
  }

  @override
  Future<void> setVolume(double volume) async {}

  void emitError(PlayerError error) {
    _errorCtrl.add(error);
  }

  void emitPosition(Duration position) {
    _position = position;
    _positionCtrl.add(position);
  }
}

class FakeWindowDelegate implements WindowDelegate {
  bool isFullscreen = false;
  bool isPip = false;

  @override
  Future<void> close() async {}

  @override
  Future<void> enterFullscreen() async {
    isFullscreen = true;
  }

  @override
  Future<void> enterPip() async {
    isPip = true;
  }

  @override
  Future<void> exitFullscreen() async {
    isFullscreen = false;
  }

  @override
  Future<void> exitPip() async {
    isPip = false;
  }

  @override
  Future<void> maximize() async {}

  @override
  Future<void> minimize() async {}

  @override
  Future<void> restore() async {}

  @override
  Future<void> setTitle(String title) async {}

  @override
  Future<void> toggleFullscreen() async {
    isFullscreen = !isFullscreen;
  }
}

class FakeControllerMediaRepository implements MediaRepository {
  final List<EpisodeHistory> histories;
  final PlayerSetting setting;

  FakeControllerMediaRepository({
    this.histories = const [],
    PlayerSetting? setting,
  }) : setting = setting ?? const PlayerSetting(videoId: 'v1');

  @override
  Future<List<EpisodeHistory>> getEpisodeHistories({
    required String videoId,
  }) async {
    return histories;
  }

  @override
  Future<PlayerSetting> getPlayerSettings({required String videoId}) async {
    return setting;
  }

  @override
  Future<void> saveEpisodeHistory(
    String videoId,
    EpisodeHistory history,
  ) async {}

  @override
  Future<void> savePlayerSettings(PlayerSetting setting) async {}
}

PlayerController _buildController({
  required IVideoPlayer player,
  WindowDelegate? windowDelegate,
  MediaRepository? mediaRepository,
  PlayerFeatures features = const PlayerFeatures(
    enableHistory: false,
    enablePlaybackSpeed: true,
  ),
}) {
  return PlayerController(
    config: PlayerConfig(
      features: features,
      behavior: const PlayerBehavior(autoPlay: false),
    ),
    player: player,
    windowDelegate: windowDelegate,
    mediaRepository: mediaRepository,
    video: const VideoMetadata(
      id: 'v1',
      title: 'Test Video',
      coverUrl: 'http://test.com/cover.jpg',
    ),
    episodes: const [
      VideoEpisode(
        index: 0,
        title: 'Episode 1',
        qualities: [
          VideoQuality(
            label: '1080p',
            source: VideoSource.network('https://example.com/video.mp4'),
          ),
        ],
      ),
      VideoEpisode(
        index: 1,
        title: 'Episode 2',
        qualities: [
          VideoQuality(
            label: '1080p',
            source: VideoSource.network('https://example.com/video-2.mp4'),
          ),
        ],
      ),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('seek awaits the underlying player seek completion', () async {
    final player = FakeVideoPlayer();
    final controller = _buildController(player: player);

    var completed = false;
    final future = controller.seek(
      const Duration(seconds: 30),
      SeekSource.external,
    );
    unawaited(future.then((_) => completed = true));

    await Future<void>.delayed(Duration.zero);

    expect(player.pendingSeekTarget, const Duration(seconds: 30));
    expect(completed, isFalse);

    player.completePendingSeek();
    await future;

    expect(completed, isTrue);
    expect(controller.position.position, const Duration(seconds: 30));

    await controller.dispose();
  });

  test('keyboard shortcuts step playback speed up and down', () async {
    final player = FakeVideoPlayer();
    final controller = _buildController(player: player);

    expect(controller.audio.playbackSpeed, 1.0);

    controller.handleKeyboardShortcut('>');
    await Future<void>.delayed(Duration.zero);

    expect(controller.audio.playbackSpeed, 1.25);
    expect(player.lastPlaybackSpeed, 1.25);

    controller.handleKeyboardShortcut('<');
    await Future<void>.delayed(Duration.zero);

    expect(controller.audio.playbackSpeed, 1.0);
    expect(player.lastPlaybackSpeed, 1.0);

    await controller.dispose();
  });

  test(
    'keyboard speed shortcuts do nothing when feature is disabled',
    () async {
      final player = FakeVideoPlayer();
      final controller = _buildController(
        player: player,
        features: const PlayerFeatures(
          enableHistory: false,
          enablePlaybackSpeed: false,
        ),
      );

      controller.handleKeyboardShortcut('>');
      await Future<void>.delayed(Duration.zero);

      expect(controller.audio.playbackSpeed, 1.0);
      expect(player.lastPlaybackSpeed, 1.0);

      await controller.dispose();
    },
  );

  test('switchQuality restores position and keeps playback state', () async {
    final player = FakeVideoPlayer()..autoCompleteSeek = true;
    final controller = _buildController(player: player);

    await controller.play();
    await controller.seek(const Duration(seconds: 42), SeekSource.external);

    expect(controller.audio.playbackSpeed, 1.0);

    controller.mediaStream.listen((_) {});

    await controller.switchQuality(0);

    expect(player.resetCount, greaterThanOrEqualTo(1));
    expect(player.pendingSeekTarget, const Duration(seconds: 42));
    expect(controller.lifecycle.isPlaying, isTrue);

    await controller.dispose();
  });

  test(
    'switchEpisode updates media state and emits lifecycle events',
    () async {
      final player = FakeVideoPlayer()..autoCompleteSeek = true;
      final controller = _buildController(player: player);
      final events = <PlayerLifecycleEvent>[];
      final sub = controller.lifecycleEvents.listen(events.add);

      await Future<void>.delayed(const Duration(milliseconds: 120));
      await controller.switchEpisode(1);
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(controller.media.currentEpisodeIndex, 1);
      expect(controller.media.currentEpisode?.title, 'Episode 2');
      expect(
        events.whereType<EpisodeChanged>().any(
          (e) => e.to.title == 'Episode 2',
        ),
        isTrue,
      );
      expect(
        events.whereType<EpisodeStarted>().any((e) => e.index == 1),
        isTrue,
      );

      await sub.cancel();
      await controller.dispose();
    },
  );

  test(
    'shows resume dialog when history indicates mid-progress playback',
    () async {
      final player = FakeVideoPlayer()..autoCompleteSeek = true;
      final repository = FakeControllerMediaRepository(
        histories: const [
          EpisodeHistory(
            index: 0,
            positionMillis: 45000,
            durationMillis: 120000,
          ),
        ],
      );
      final controller = _buildController(
        player: player,
        mediaRepository: repository,
        features: const PlayerFeatures(
          enableHistory: true,
          enablePlaybackSpeed: true,
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(controller.visibility.showResumeDialog, isTrue);
      expect(controller.visibility.resumeState?.positionMillis, 45000);
      expect(controller.visibility.showReplayDialog, isFalse);
      expect(controller.lifecycle.isPlaying, isFalse);

      await controller.dispose();
    },
  );

  test('shows replay dialog when history is near completion', () async {
    final player = FakeVideoPlayer()..autoCompleteSeek = true;
    final repository = FakeControllerMediaRepository(
      histories: const [
        EpisodeHistory(
          index: 0,
          positionMillis: 116000,
          durationMillis: 120000,
        ),
      ],
    );
    final controller = _buildController(
      player: player,
      mediaRepository: repository,
      features: const PlayerFeatures(
        enableHistory: true,
        enablePlaybackSpeed: true,
      ),
    );

    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(controller.visibility.showReplayDialog, isTrue);
    expect(controller.visibility.replayState?.positionMillis, 116000);
    expect(controller.visibility.showResumeDialog, isFalse);
    expect(controller.lifecycle.isPlaying, isFalse);

    await controller.dispose();
  });

  test('emits MediaLoadFailed when the player reports an error', () async {
    final player = FakeVideoPlayer();
    final controller = _buildController(player: player);
    final events = <PlayerLifecycleEvent>[];
    final sub = controller.lifecycleEvents.listen(events.add);

    player.emitError(
      PlayerError(code: 'NETWORK', message: 'Failed to load media'),
    );
    await Future<void>.delayed(Duration.zero);

    final failure = events.whereType<MediaLoadFailed>().lastOrNull;
    expect(failure, isNotNull);
    expect(failure!.error.code, 'NETWORK');
    expect(failure.error.message, 'Failed to load media');

    await sub.cancel();
    await controller.dispose();
  });

  test('last episode end shows replay dialog in normal mode', () async {
    final player = FakeVideoPlayer()..autoCompleteSeek = true;
    final controller = _buildController(player: player);

    await controller.switchEpisode(1);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    await controller.play();

    player.emitPosition(player.duration);
    await Future<void>.delayed(Duration.zero);
    await player.pause();
    await Future<void>.delayed(Duration.zero);

    expect(controller.visibility.showReplayDialog, isTrue);
    expect(controller.visibility.replayState?.durationMillis, 120000);

    await controller.dispose();
  });

  test('last episode end keeps replay dialog visible in pip mode', () async {
    final player = FakeVideoPlayer()..autoCompleteSeek = true;
    final windowDelegate = FakeWindowDelegate();
    final controller = _buildController(
      player: player,
      windowDelegate: windowDelegate,
    );

    await controller.switchEpisode(1);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    controller.togglePip();
    await Future<void>.delayed(Duration.zero);
    await controller.play();

    player.emitPosition(player.duration);
    await Future<void>.delayed(Duration.zero);
    await player.pause();
    await Future<void>.delayed(Duration.zero);

    expect(controller.view.isPip, isTrue);
    expect(windowDelegate.isPip, isTrue);
    expect(controller.visibility.showReplayDialog, isTrue);

    await controller.dispose();
  });

  test('last episode end shows replay dialog in fullscreen mode', () async {
    final player = FakeVideoPlayer()..autoCompleteSeek = true;
    final windowDelegate = FakeWindowDelegate();
    final controller = _buildController(
      player: player,
      windowDelegate: windowDelegate,
    );

    await controller.switchEpisode(1);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    controller.toggleFullscreen();
    await Future<void>.delayed(Duration.zero);
    await controller.play();

    player.emitPosition(player.duration);
    await Future<void>.delayed(Duration.zero);
    await player.pause();
    await Future<void>.delayed(Duration.zero);

    expect(controller.view.isFullscreen, isTrue);
    expect(windowDelegate.isFullscreen, isTrue);
    expect(controller.visibility.showReplayDialog, isTrue);

    await controller.dispose();
  });

  test('replay dialog remains visible after leaving pip mode', () async {
    final player = FakeVideoPlayer()..autoCompleteSeek = true;
    final windowDelegate = FakeWindowDelegate();
    final controller = _buildController(
      player: player,
      windowDelegate: windowDelegate,
    );

    await controller.switchEpisode(1);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    controller.togglePip();
    await Future<void>.delayed(Duration.zero);
    await controller.play();

    player.emitPosition(player.duration);
    await Future<void>.delayed(Duration.zero);
    await player.pause();
    await Future<void>.delayed(Duration.zero);

    expect(controller.visibility.showReplayDialog, isTrue);

    controller.togglePip();
    await Future<void>.delayed(Duration.zero);

    expect(controller.view.isPip, isFalse);
    expect(windowDelegate.isPip, isFalse);
    expect(controller.visibility.showReplayDialog, isTrue);

    await controller.dispose();
  });

  test(
    'skipOutro zero falls back to natural end instead of auto-skip logic',
    () async {
      final player = FakeVideoPlayer()..autoCompleteSeek = true;
      final repository = FakeControllerMediaRepository(
        setting: const PlayerSetting(
          videoId: 'v1',
          autoSkip: true,
          skipOutro: 0,
        ),
      );
      final controller = _buildController(
        player: player,
        mediaRepository: repository,
        features: const PlayerFeatures(
          enableHistory: true,
          enablePlaybackSpeed: true,
        ),
      );

      await controller.switchEpisode(1);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      await controller.play();

      player.emitPosition(player.duration);
      await Future<void>.delayed(Duration.zero);
      await player.pause();
      await Future<void>.delayed(Duration.zero);

      expect(controller.visibility.showReplayDialog, isTrue);
      expect(controller.visibility.skipNotification, SkipNotificationType.none);

      await controller.dispose();
    },
  );

  test('skipOutro zero advances to next episode on natural end', () async {
    final player = FakeVideoPlayer()..autoCompleteSeek = true;
    final repository = FakeControllerMediaRepository(
      setting: const PlayerSetting(
        videoId: 'v1',
        autoSkip: true,
        skipIntro: 0,
        skipOutro: 0,
      ),
    );
    final controller = _buildController(
      player: player,
      mediaRepository: repository,
      features: const PlayerFeatures(
        enableHistory: true,
        enablePlaybackSpeed: true,
        enableAutoPlayNext: true,
      ),
    );

    await Future<void>.delayed(const Duration(milliseconds: 150));
    await controller.play();

    player.emitPosition(player.duration);
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(controller.media.currentEpisodeIndex, 1);
    expect(controller.visibility.showReplayDialog, isFalse);
    expect(controller.visibility.skipNotification, SkipNotificationType.none);

    await controller.dispose();
  });

  test('auto skip outro advances without ending the playlist early', () async {
    final player = FakeVideoPlayer()..autoCompleteSeek = true;
    final repository = FakeControllerMediaRepository(
      setting: const PlayerSetting(videoId: 'v1', autoSkip: true, skipOutro: 5),
    );
    final controller = _buildController(
      player: player,
      mediaRepository: repository,
      features: const PlayerFeatures(
        enableHistory: true,
        enablePlaybackSpeed: true,
        enableAutoPlayNext: true,
      ),
    );
    final events = <PlayerLifecycleEvent>[];
    final sub = controller.lifecycleEvents.listen(events.add);

    await Future<void>.delayed(const Duration(milliseconds: 150));
    await controller.play();

    player.emitPosition(player.duration - const Duration(seconds: 4));
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(controller.media.currentEpisodeIndex, 1);
    expect(events.whereType<EpisodeEnded>().any((e) => e.index == 0), isTrue);
    expect(events.whereType<PlaylistEnded>(), isEmpty);

    await sub.cancel();
    await controller.dispose();
  });
}
