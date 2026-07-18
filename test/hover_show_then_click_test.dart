// Repro: mouse over the video -> controls appear (hover path) -> click does
// nothing / controls stuck. Drive the REAL hover path (handleMouseMove) and a
// real mouse click on the center button, assert the click actually toggles.

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vidra_player/controller/player_controller.dart';
import 'package:vidra_player/core/interfaces/video_player.dart';
import 'package:vidra_player/core/model/model.dart';
import 'package:vidra_player/core/state/states.dart';
import 'package:vidra_player/ui/player_widget.dart';
import 'package:vidra_player/ui/widget/toggle_icon_button.dart';

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
  int playCalls = 0;
  int pauseCalls = 0;

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
    playCalls++;
    _isPlaying = true;
    _playingCtrl.add(true);
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
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
          showControlsOnHover: true,
          autoHideDelay: Duration(seconds: 3),
        ),
      ),
      player: player,
      video: const VideoMetadata(
        id: 'v1',
        title: 'T',
        coverUrl: 'http://test.com/cover.jpg',
      ),
      episodes: const [
        VideoEpisode(index: 0, title: 'E1', qualities: [
          VideoQuality(
              label: '1080p',
              source: VideoSource.network('https://example.com/v0.mp4')),
        ]),
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('hover shows controls; center button click toggles pause',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final player = _FakeVideoPlayer();
    final controller = _build(player);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.macOS),
        home: Scaffold(body: VideoPlayerWidget(controller: controller)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await controller.play();
    await tester.pump(const Duration(milliseconds: 100));

    // REAL hover path: move a mouse over the video surface.
    final center = tester.getCenter(find.byType(VideoPlayerWidget));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(10, 400));
    addTearDown(() => mouse.removePointer());
    await mouse.moveTo(center);
    await tester.pump(const Duration(milliseconds: 100)); // flush 50ms debounce
    await tester.pump(const Duration(milliseconds: 100));

    expect(controller.visibility.showControls, isTrue,
        reason: 'hover must show controls');
    expect(find.byType(PlayPauseButton), findsOneWidget);
    expect(controller.lifecycle.isPlaying, isTrue);

    // Now click the center play/pause button (real mouse click at its center).
    final btnCenter = tester.getCenter(find.byType(PlayPauseButton));
    await mouse.moveTo(btnCenter);
    await tester.pump(const Duration(milliseconds: 16));
    await mouse.down(btnCenter);
    await tester.pump(const Duration(milliseconds: 16));
    await mouse.up();
    await tester.pump(const Duration(milliseconds: 100));

    expect(player.pauseCalls, greaterThan(0),
        reason: 'clicking the center button must pause playback');
    expect(controller.lifecycle.isPlaying, isFalse,
        reason: 'click must be live, not eaten');

    await controller.dispose();
    await tester.pump();
  });
}
