// Invariant guard: tapping the top-right episodes button opens the panel and
// must NOT also fire the background gesture layer's toggleControls (which
// would hide the controls). Confirmed green with instrumented handlers — only
// toggleEpisodeList fires, toggleControls does not — so the reported
// intermittent "click hides controls" is NOT reproducible in the SDK's own
// widget tree and points to the host embedding (e.g. a bitsdojo_window
// title-bar drag region overlapping the player's top bar). Kept as a
// regression net so a future change can't start leaking taps to the
// background.

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vidra_player/controller/player_controller.dart';
import 'package:vidra_player/core/interfaces/video_player.dart';
import 'package:vidra_player/core/model/model.dart';
import 'package:vidra_player/core/state/states.dart';
import 'package:vidra_player/ui/overlays/episode_list.dart';
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
        behavior: PlayerBehavior(autoPlay: false),
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
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('tapping the episodes button must NOT also toggle controls off',
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
    controller.showControls();
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.visibility.showControls, isTrue);

    final button = find.byKey(const ValueKey('top_bar_episode_list_button'));
    expect(button, findsOneWidget);

    // Real mouse click with tiny drift (trackpad/mouse never lands perfectly
    // still): down, a few px move, up — still within touch slop, still a tap.
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.down(tester.getCenter(button));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(3, 2));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();
    await tester.pump();

    // Past the background GestureDetector's double-tap disambiguation (~300ms):
    // if the tap leaked through the button to the background, toggleControls
    // fires here and hides the controls.
    await tester.pump(const Duration(milliseconds: 400));

    expect(controller.visibility.showEpisodeList, isTrue,
        reason: 'tapping the button must open the episode panel');
    expect(controller.visibility.showControls, isTrue,
        reason: 'tapping the button must NOT leak to the background '
            'toggleControls and hide the controls');
    expect(find.byType(EpisodeList), findsOneWidget);

    await controller.dispose();
    await tester.pump();
  });
}
