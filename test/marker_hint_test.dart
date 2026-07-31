// The one-off "right-click the progress bar" nudge: it must appear for a video
// with no skip points, and must NOT appear for one that already has them —
// whether they came from the series-wide setting or a per-episode marker.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vidra_player/controller/player_controller.dart';
import 'package:vidra_player/core/interfaces/video_player.dart';
import 'package:vidra_player/core/model/model.dart';
import 'package:vidra_player/core/model/player_locale.dart';
import 'package:vidra_player/core/state/states.dart';
import 'package:vidra_player/ui/controls/skip_prompt.dart';
import 'package:vidra_player/ui/player_widget.dart';

class _FakeVideoPlayer implements IVideoPlayer {
  final _positionCtrl = StreamController<Duration>.broadcast();
  final _bufferingCtrl = StreamController<BufferingState>.broadcast();
  final _playingCtrl = StreamController<bool>.broadcast();
  final _liveCtrl = StreamController<bool>.broadcast();
  final _errorCtrl = StreamController<PlayerError?>.broadcast();
  final _bufferedCtrl = StreamController<List<BufferRange>>.broadcast();
  final _videoSizeCtrl = StreamController<VideoSize?>.broadcast();
  final _completedCtrl = StreamController<bool>.broadcast();

  bool _isPlaying = false;
  Duration _position = Duration.zero;

  @override
  Duration get duration => const Duration(minutes: 40);
  @override
  Duration get position => _position;
  @override
  bool get isPlaying => _isPlaying;
  @override
  bool get isLive => false;
  @override
  VideoSize? get videoSize => const VideoSize(1920, 1080);

  @override
  Stream<Duration> get positionStream => _positionCtrl.stream;
  @override
  Stream<BufferingState> get bufferingStream => _bufferingCtrl.stream;
  @override
  Stream<bool> get isPlayingStream => _playingCtrl.stream;
  @override
  Stream<bool> get isLiveStream => _liveCtrl.stream;
  @override
  Stream<PlayerError?> get errorStream => _errorCtrl.stream;
  @override
  Stream<List<BufferRange>> get bufferedStream => _bufferedCtrl.stream;
  @override
  Stream<VideoSize?> get videoSizeStream => _videoSizeCtrl.stream;
  @override
  Stream<bool> get completedStream => _completedCtrl.stream;

  void emitPosition(Duration d) {
    _position = d;
    _positionCtrl.add(d);
  }

  @override
  Future<void> initialize(VideoSource source) async {}
  @override
  Future<void> play() async {
    _isPlaying = true;
    _playingCtrl.add(true);
  }

  @override
  Future<void> pause() async {
    _isPlaying = false;
    _playingCtrl.add(false);
  }

  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> setPlaybackSpeed(double speed) async {}
  @override
  Future<void> reset() async {}

  @override
  Widget render({
    Key? key,
    BoxFit fit = BoxFit.contain,
    Alignment alignment = Alignment.center,
  }) => SizedBox(key: key);

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
}

PlayerController _build(_FakeVideoPlayer player) => PlayerController(
  config: const PlayerConfig(
    features: PlayerFeatures(enableHistory: false),
    behavior: PlayerBehavior(autoPlay: false, showControlsOnHover: true),
    locale: VidraLocale.zhCN,
  ),
  player: player,
  video: const VideoMetadata(id: 'v1', title: 'T', coverUrl: 'c'),
  episodes: const [
    VideoEpisode(
      index: 0,
      title: 'E1',
      qualities: [
        VideoQuality(
          label: '1080p',
          source: VideoSource.network('https://example.com/v0.mp4'),
        ),
      ],
    ),
  ],
);

/// Pump the player, start playback, and run past the hint's 4s threshold.
Future<PlayerController> _playPast4s(
  WidgetTester tester,
  _FakeVideoPlayer player, {
  void Function(PlayerController)? configure,
}) async {
  final controller = _build(player);
  configure?.call(controller);

  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: TargetPlatform.macOS),
      home: Scaffold(body: VideoPlayerWidget(controller: controller)),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
  await controller.play();
  player.emitPosition(const Duration(seconds: 1));
  await tester.pump(const Duration(milliseconds: 100));

  player.emitPosition(const Duration(seconds: 5));
  // The controls-show path is debounced 50ms inside the UI manager.
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
  return controller;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('hints once when no skip points are set', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final player = _FakeVideoPlayer();
    final controller = await _playPast4s(tester, player);

    expect(
      controller.visibility.skipNotification,
      SkipNotificationType.markerHint,
    );
    expect(find.byType(SkipPrompt), findsOneWidget);
    expect(find.text('提示：右键进度条可设置跳过片头/片尾'), findsOneWidget);

    // Auto-dismisses, and does not come back on later ticks.
    await tester.pump(const Duration(seconds: 6));
    expect(controller.visibility.skipNotification, SkipNotificationType.none);

    player.emitPosition(const Duration(seconds: 30));
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      controller.visibility.skipNotification,
      SkipNotificationType.none,
      reason: 'once per session, not once per tick',
    );

    await controller.dispose();
    await tester.pump();
  });

  testWidgets('stays quiet when a per-episode marker exists', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final player = _FakeVideoPlayer();
    final controller = await _playPast4s(
      tester,
      player,
      configure: (c) =>
          c.setEpisodeMarkers(introEnd: const Duration(seconds: 90)),
    );

    expect(controller.visibility.skipNotification, SkipNotificationType.none);
    expect(find.byType(SkipPrompt), findsNothing);

    await controller.dispose();
    await tester.pump();
  });

  testWidgets('stays quiet when the series-wide setting is set', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final player = _FakeVideoPlayer();
    final controller = await _playPast4s(
      tester,
      player,
      configure: (c) => c.updateSkipIntro(85),
    );

    expect(controller.visibility.skipNotification, SkipNotificationType.none);

    await controller.dispose();
    await tester.pump();
  });
}
