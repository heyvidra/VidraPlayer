import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vidra_player/controller/player_controller.dart';
import 'package:vidra_player/core/events/player_lifecycle_event.dart';
import 'package:vidra_player/core/interfaces/frame_sweeper.dart';
import 'package:vidra_player/core/interfaces/window_delegate.dart';
import 'package:vidra_player/core/interfaces/media_repository.dart';
import 'package:vidra_player/core/interfaces/video_player.dart';
import 'package:vidra_player/core/model/model.dart';
import 'package:vidra_player/core/state/states.dart';
import 'package:vidra_player/ui/overlays/switching_overlay.dart';
import 'package:vidra_player/vidra_player_sdk.dart';

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

/// [FakeVideoPlayer] whose initialize()/reset() can be held open — the shape
/// of a stalled network open or a wedged teardown, which is exactly what
/// cancelSwitching exists for. Gates are captured per call, so two flights
/// can hang on different completers.
class HangingOpenPlayer extends FakeVideoPlayer {
  /// When set, initialize() waits on it before completing.
  Completer<void>? openGate;

  /// When set, reset() waits on it before completing.
  Completer<void>? resetGate;
  int playCalls = 0;

  @override
  Future<void> initialize(VideoSource source) async {
    final gate = openGate;
    if (gate != null) await gate.future;
    await super.initialize(source);
  }

  @override
  Future<void> reset() async {
    final gate = resetGate;
    if (gate != null) await gate.future;
    await super.reset();
  }

  @override
  Future<void> play() async {
    playCalls++;
    await super.play();
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

/// Sweeper whose stream never emits. The deferral cases below care about
/// WHETHER the second decode pipeline spins up — the factory call is the
/// observable — never about frames.
class IdleSweeper implements FrameSweeper {
  @override
  Stream<SweptFrame> sweep(SweepRequest request) =>
      StreamController<SweptFrame>().stream;
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
      // Modal resume is opt-in now; these cases assert the dialog.
      behavior: const PlayerBehavior(
        autoPlay: false,
        resumeMode: ResumeMode.prompt,
      ),
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

  group('cancelSwitching', () {
    test('drops the overlay at once and the stale flight never plays',
        () async {
      final player = HangingOpenPlayer();
      final controller = _buildController(player: player);
      // Let the initial (ungated) load finish.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final events = <PlayerLifecycleEvent>[];
      final sub = controller.lifecycleEvents.listen(events.add);

      // Gate the next open and start a switch that will hang on it.
      final gate = Completer<void>();
      player.openGate = gate;
      final flight = controller.switchEpisode(1);
      await Future<void>.delayed(Duration.zero);
      expect(controller.switching.isSwitching, isTrue);

      controller.cancelSwitching();
      // Overlay must drop immediately — this is the whole point.
      expect(controller.switching.isSwitching, isFalse);

      // Release the hung open and let the abandoned flight unwind. It must
      // not play, not re-raise switching, not claim the episode started.
      gate.complete();
      await flight;
      await Future<void>.delayed(Duration.zero);
      expect(player.playCalls, 0);
      expect(controller.switching.isSwitching, isFalse);
      expect(
        events.whereType<EpisodeStarted>().where((e) => e.index == 1),
        isEmpty,
      );
      // Cancellation is a user decision, not a failure.
      expect(events.whereType<MediaLoadFailed>(), isEmpty);

      await sub.cancel();
      await controller.dispose();
    });

    test('the switch target can be re-opened after a cancel', () async {
      final player = HangingOpenPlayer();
      final controller = _buildController(player: player);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final gate = Completer<void>();
      player.openGate = gate;
      final flight = controller.switchEpisode(1);
      await Future<void>.delayed(Duration.zero);
      controller.cancelSwitching();
      gate.complete();
      await flight;

      // Media state committed episode 1 but the player never opened it.
      // Clicking episode 1 again must NOT be swallowed by the
      // "already on this episode" guard. Count loads, don't inspect the
      // last source: the ABANDONED flight also records one when its gated
      // open finally resolves, so `last` passes even when the guard eats
      // the re-click.
      player.openGate = null;
      final loadsBefore = player.initializedSources.length;
      await controller.switchEpisode(1);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(controller.media.currentEpisodeIndex, 1);
      expect(player.initializedSources.length, loadsBefore + 1);
      expect(
        player.initializedSources.last,
        'https://example.com/video-2.mp4',
      );
      expect(controller.switching.isSwitching, isFalse);

      await controller.dispose();
    });

    test('cancel while the player is still resetting kills the flight '
        'before it can open', () async {
      // The token mechanism alone misses this: the flight has not called
      // initialize yet, so a later initialize would mint a FRESH token and
      // the open would proceed as if never cancelled — EpisodeStarted,
      // auto-play and all. The generation checks are what catch it.
      final player = HangingOpenPlayer();
      final controller = _buildController(player: player);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final events = <PlayerLifecycleEvent>[];
      final sub = controller.lifecycleEvents.listen(events.add);
      final loadsBefore = player.initializedSources.length;

      player.resetGate = Completer<void>();
      final flight = controller.switchEpisode(1);
      await Future<void>.delayed(Duration.zero);
      expect(controller.switching.isSwitching, isTrue);

      controller.cancelSwitching();
      player.resetGate!.complete();
      await flight;
      await Future<void>.delayed(Duration.zero);

      // The target episode was never even opened.
      expect(player.initializedSources.length, loadsBefore);
      expect(player.playCalls, 0);
      expect(events.whereType<EpisodeStarted>(), isEmpty);

      // And the target can still be opened afterwards.
      player.resetGate = null;
      await controller.switchEpisode(1);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(player.initializedSources.length, loadsBefore + 1);

      await sub.cancel();
      await controller.dispose();
    });

    test('a cancelled flight unwinding late never tears down a newer '
        'switch\'s overlay', () async {
      final player = HangingOpenPlayer();
      final controller = _buildController(player: player);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Quality switch hangs inside its open.
      final gateA = Completer<void>();
      player.openGate = gateA;
      final flightA = controller.switchQuality(0);
      await Future<void>.delayed(Duration.zero);
      expect(controller.switching.isSwitching, isTrue);

      controller.cancelSwitching();
      expect(controller.switching.isSwitching, isFalse);

      // User immediately starts an episode switch, which hangs on ITS open.
      final gateB = Completer<void>();
      player.openGate = gateB;
      final flightB = controller.switchEpisode(1);
      await Future<void>.delayed(Duration.zero);
      expect(controller.switching.isSwitching, isTrue);

      // The stale quality flight finally unwinds. It must not endSwitch the
      // NEW flight's input-blocking overlay out from under it.
      gateA.complete();
      await flightA;
      await Future<void>.delayed(Duration.zero);
      expect(controller.switching.isSwitching, isTrue);

      // The new flight completes normally.
      gateB.complete();
      await flightB;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(controller.switching.isSwitching, isFalse);
      expect(controller.media.currentEpisodeIndex, 1);

      await controller.dispose();
    });

    testWidgets('cancel reveal timer restarts for a back-to-back switch', (
      tester,
    ) async {
      // Cancel + immediate re-switch reaches the overlay as ONE update where
      // isSwitching never flips — only the attempt id moves. The reveal
      // timer must restart on it, or the new overlay shows the cancel button
      // from frame one (and a stale timer can fire into the new switch).
      final player = HangingOpenPlayer();
      final controller = _buildController(player: player);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );

      Widget build(SwitchingState s) => MaterialApp(
        home: SwitchingOverlay(
          controller: controller,
          state: s,
          theme: controller.config.theme,
        ),
      );
      TextButton button() => tester.widget<TextButton>(find.byType(TextButton));

      await tester.pumpWidget(
        build(const SwitchingState(isSwitching: true, attempt: 1)),
      );
      expect(button().onPressed, isNull); // hidden before the delay
      await tester.pump(const Duration(milliseconds: 3100));
      expect(button().onPressed, isNotNull); // revealed

      // One rebuild, still switching, new attempt — the same-task case.
      await tester.pumpWidget(
        build(const SwitchingState(isSwitching: true, attempt: 2)),
      );
      expect(button().onPressed, isNull); // timer restarted
      await tester.pump(const Duration(milliseconds: 3100));
      expect(button().onPressed, isNotNull);

      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => controller.dispose());
    });

    testWidgets('overlay fits a short viewport instead of overflowing', (
      tester,
    ) async {
      // Real-hardware regression: the cancel button pushed the fixed-height
      // column past a small window ("BOTTOM OVERFLOWED BY 11 PIXELS" over the
      // switching overlay). RenderFlex overflow throws in widget tests, so a
      // clean pump at a tight size is the assertion.
      final player = HangingOpenPlayer();
      final controller = _buildController(player: player);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );

      // Short enough that the button-bearing column (~190px without a cover
      // image) cannot fit unscaled — the case the fix exists for.
      tester.view.physicalSize = const Size(500, 150);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: SwitchingOverlay(
            controller: controller,
            state: const SwitchingState(isSwitching: true, attempt: 1),
            theme: controller.config.theme,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 3100));
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => controller.dispose());
    });

    test('is a no-op when nothing is switching', () async {
      final player = HangingOpenPlayer();
      final controller = _buildController(player: player);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      controller.cancelSwitching();
      expect(controller.switching.isSwitching, isFalse);

      // The guard still works: already-current episode stays a no-op.
      final loads = player.initializedSources.length;
      await controller.switchEpisode(0);
      expect(player.initializedSources.length, loads);

      await controller.dispose();
    });
  });

  group('pause->sweep deferral', () {
    // The sweep must not start until a pause has HELD for ~3s: most pauses
    // die within a breath (tap-pause/tap-play, seeks, episode switches), and
    // each false start spins up a whole second decode pipeline — on a 2016
    // 4c/8t Intel MBP that is fans-on while the machine looks idle. These
    // cases run against the real deferral, so this group costs wall time.
    var sweepsStarted = 0;

    setUp(() {
      sweepsStarted = 0;
      VidraPlayer.setFrameSweeperFactory(() {
        sweepsStarted++;
        return IdleSweeper();
      });
    });

    tearDown(() => VidraPlayer.setFrameSweeperFactory(null));

    // Playing past the 10s stability gate, so a pause is sweep-eligible.
    Future<void> playTo30s(
      PlayerController controller,
      FakeVideoPlayer player,
    ) async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await controller.play();
      player.emitPosition(const Duration(seconds: 30));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    test(
      'a pause that holds starts the sweep after the window, not at the pause',
      () async {
        final player = FakeVideoPlayer();
        final controller = _buildController(player: player);
        await playTo30s(controller, player);

        await player.pause();
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        expect(
          sweepsStarted,
          0,
          reason: 'inside the deferral window nothing may decode',
        );

        await Future<void>.delayed(const Duration(milliseconds: 2200));
        expect(
          sweepsStarted,
          1,
          reason: 'a held pause is exactly what the sweep waits for',
        );

        await controller.dispose();
      },
    );

    test(
      'a pause shorter than the deferral never spins up the pipeline',
      () async {
        final player = FakeVideoPlayer();
        final controller = _buildController(player: player);
        await playTo30s(controller, player);

        await player.pause();
        await Future<void>.delayed(const Duration(seconds: 1));
        await player.play();

        // Well past the instant the deferral would have fired.
        await Future<void>.delayed(const Duration(seconds: 3));
        expect(
          sweepsStarted,
          0,
          reason: 'a tap-pause/tap-play must cost nothing',
        );

        await controller.dispose();
      },
    );

    test('play during the deferral cancels it — a re-pause waits its own '
        'full window', () async {
      final player = FakeVideoPlayer();
      final controller = _buildController(player: player);
      await playTo30s(controller, player);

      await player.pause(); // t=0: this window would fire at 3s.
      await Future<void>.delayed(const Duration(seconds: 2));
      await player.play(); // t=2: must kill that timer.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await player.pause(); // t~2.1: a fresh window, firing ~5.1s.

      // t~3.9: past the FIRST timer's fire instant. A leaked timer would
      // have started a sweep into the second pause's window right here.
      await Future<void>.delayed(const Duration(milliseconds: 1850));
      expect(
        sweepsStarted,
        0,
        reason: "the first pause's timer must be dead, not inherited",
      );

      // t~5.6: the second pause has now held its own full window.
      await Future<void>.delayed(const Duration(milliseconds: 1700));
      expect(sweepsStarted, 1);

      await controller.dispose();
    });
  });
}
