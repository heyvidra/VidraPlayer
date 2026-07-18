// Repro: after playing a while, tapping the top-right episodes button does
// nothing; hiding controls and tapping again works. Drive REAL taps through
// the full widget tree so gesture propagation / animated-switcher barriers
// are exercised, not just the controller methods.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vidra_player/controller/player_controller.dart';
import 'package:vidra_player/core/interfaces/video_player.dart';
import 'package:vidra_player/core/interfaces/window_delegate.dart';
import 'package:vidra_player/core/model/model.dart';
import 'package:vidra_player/core/state/states.dart';
import 'package:vidra_player/ui/overlays/episode_list.dart';
import 'package:vidra_player/ui/player_widget.dart';

class _FakeWindowDelegate implements WindowDelegate {
  @override
  Future<void> enterFullscreen() async {}
  @override
  Future<void> exitFullscreen() async {}
  @override
  Future<void> toggleFullscreen() async {}
  @override
  Future<void> enterPip({dynamic pipWidget}) async {}
  @override
  Future<void> exitPip() async {}
  @override
  Future<void> minimize() async {}
  @override
  Future<void> maximize() async {}
  @override
  Future<void> restore() async {}
  @override
  Future<void> close() async {}
  @override
  Future<void> setTitle(String title) async {}
}

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

  @override
  Duration get duration => const Duration(minutes: 37);
  @override
  Duration get position => Duration.zero;
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
        behavior: PlayerBehavior(
          autoPlay: false,
          autoHideDelay: Duration(seconds: 3),
        ),
      ),
      player: player,
      video: const VideoMetadata(
        id: 'v1',
        title: '二龙湖',
        coverUrl: 'http://test.com/cover.jpg',
      ),
      episodes: const [
        VideoEpisode(index: 0, title: '第1集', qualities: [
          VideoQuality(
              label: '1080p',
              source: VideoSource.network('https://example.com/v0.mp4')),
        ]),
        VideoEpisode(index: 1, title: '第2集', qualities: [
          VideoQuality(
              label: '1080p',
              source: VideoSource.network('https://example.com/v1.mp4')),
        ]),
      ],
      windowDelegate: _FakeWindowDelegate(),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<PlayerController> pump(WidgetTester tester, _FakeVideoPlayer p) async {
    final controller = _build(p);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.macOS),
        home: Scaffold(body: VideoPlayerWidget(controller: controller)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    return controller;
  }

  testWidgets('open -> close -> reopen: second open must not be eaten', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final player = _FakeVideoPlayer();
    final controller = await pump(tester, player);
    await controller.play();
    controller.showControls();
    await tester.pump(const Duration(milliseconds: 400));

    final button = find.byKey(const ValueKey('top_bar_episode_list_button'));
    expect(button, findsOneWidget);

    // Open.
    await tester.tap(button, warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(controller.visibility.showEpisodeList, isTrue,
        reason: 'first open must show the panel');

    // Close it, then reopen WHILE the 300ms SlidePanel exit transition still
    // has the old panel (and its full-screen opaque onClose barrier) mounted.
    // The barrier sits on top of the top bar; without the IgnorePointer gate
    // it eats the reopen tap and the panel stays closed ("stuck").
    controller.hideEpisodeList();
    await tester.pump(); // begin exit transition
    expect(find.byType(EpisodeList), findsOneWidget,
        reason: 'exit transition keeps the old panel mounted for 300ms');

    controller.showControls();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(button, warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(controller.visibility.showEpisodeList, isTrue,
        reason: 'reopen during exit transition must re-show the panel');
    expect(find.byType(EpisodeList), findsOneWidget);

    await controller.dispose();
    await tester.pump();
  });

  testWidgets('played a while then real tap opens the panel', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final player = _FakeVideoPlayer();
    final controller = await pump(tester, player);
    await controller.play();

    // Simulate "played a while": show via hover, let time pass, hover again.
    final playerCenter = tester.getCenter(find.byType(VideoPlayerWidget));
    controller.handleMouseMove(playerCenter);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 2));
    controller.handleMouseMove(playerCenter);
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.visibility.showControls, isTrue);

    final button = find.byKey(const ValueKey('top_bar_episode_list_button'));
    await tester.tap(button, warnIfMissed: false);
    // Through the background double-tap disambiguation window.
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 350));

    expect(controller.visibility.showEpisodeList, isTrue,
        reason: 'tap after playing a while must open the panel');

    await controller.dispose();
    await tester.pump();
  });
}
