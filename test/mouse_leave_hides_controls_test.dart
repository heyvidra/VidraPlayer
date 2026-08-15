// The pointer leaving the player takes the controls with it, instead of
// leaving them on screen for the 3s auto-hide to collect.
//
// The trap this has to avoid: Flutter's mouse tracker dispatches every EXIT
// before any ENTER, so sliding the cursor from the picture onto the bottom bar
// momentarily looks identical to leaving the player. Hiding on that would yank
// the bar out from under the pointer that was reaching for it.

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vidra_player/controller/player_controller.dart';
import 'package:vidra_player/core/interfaces/video_player.dart';
import 'package:vidra_player/core/model/model.dart';
import 'package:vidra_player/core/state/states.dart';
import 'package:vidra_player/ui/controls/bottom_bar.dart';
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
  Duration get duration => const Duration(minutes: 2);
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

PlayerController _buildController(IVideoPlayer player) => PlayerController(
  config: const PlayerConfig(
    features: PlayerFeatures(enableHistory: false),
    behavior: PlayerBehavior(autoPlay: false),
  ),
  player: player,
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
  ],
);

/// Mounts the player at desktop size, playing, controls up, mouse in the
/// middle of the picture.
Future<TestGesture> _hoveringPlayer(
  WidgetTester tester,
  PlayerController controller,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: TargetPlatform.macOS),
      home: Scaffold(body: VideoPlayerWidget(controller: controller)),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
  await controller.play();
  await tester.pump();

  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: const Offset(640, 300));
  addTearDown(mouse.removePointer);
  await tester.pump(const Duration(milliseconds: 200));
  expect(controller.visibility.showControls, isTrue);
  return mouse;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Desktop layout, so the top/bottom bars exist to hover.
  });

  testWidgets('leaving the player hides the controls without the 3s wait', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final player = _FakeVideoPlayer();
    final controller = _buildController(player);
    final mouse = await _hoveringPlayer(tester, controller);

    // Move INSIDE first, then straight out — that's what leaving actually
    // looks like, and it means the last interaction is milliseconds old. The
    // auto-hide path debounces on exactly that, so without an explicit bypass
    // the leave would re-arm at the full 3s and this would still be visible.
    await mouse.moveTo(const Offset(640, 700));
    await tester.pump(const Duration(milliseconds: 16));
    await mouse.moveTo(const Offset(-100, -100));

    // Well inside the 3s auto-hide window — only the leave path can have done
    // this.
    await tester.pump(const Duration(milliseconds: 300));

    expect(controller.visibility.showControls, isFalse,
        reason: 'pointer gone from the player -> controls gone with it');

    await controller.dispose();
    await tester.pump();
  });

  testWidgets('sliding onto the bottom bar must NOT hide it', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final player = _FakeVideoPlayer();
    final controller = _buildController(player);
    final mouse = await _hoveringPlayer(tester, controller);

    // Watch every emission, not just the end state: entering the bar re-shows
    // the controls ~50ms later, so a hide on the exit would be repaired before
    // any end-state assertion could notice — while still being a visible
    // flicker on screen.
    final seen = <bool>[];
    final sub = controller.visibilityStream.listen(
      (v) => seen.add(v.showControls),
    );
    addTearDown(sub.cancel);

    await mouse.moveTo(tester.getCenter(find.byType(BottomBar)));
    await tester.pump(const Duration(milliseconds: 300));

    expect(seen, isNot(contains(false)),
        reason: 'the exit-before-enter dispatch order must not read as '
            'leaving the player, not even for one frame');
    expect(controller.visibility.showControls, isTrue);

    // And it stays up while the pointer rests there — hovering a control bar
    // pins the controls, same as before.
    await tester.pump(const Duration(seconds: 5));
    expect(controller.visibility.showControls, isTrue);

    await controller.dispose();
    await tester.pump();
  });

  testWidgets('leaving straight off the bottom bar hides too', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final player = _FakeVideoPlayer();
    final controller = _buildController(player);
    final mouse = await _hoveringPlayer(tester, controller);

    // Onto the bar, then out of the window — the video's MouseRegion never
    // sees this exit, so the control bar's is the only signal.
    await mouse.moveTo(tester.getCenter(find.byType(BottomBar)));
    await tester.pump(const Duration(milliseconds: 200));
    await mouse.moveTo(const Offset(-100, -100));
    await tester.pump(const Duration(milliseconds: 300));

    expect(controller.visibility.showControls, isFalse);

    await controller.dispose();
    await tester.pump();
  });

  testWidgets('paused: leaving leaves the controls alone', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final player = _FakeVideoPlayer();
    final controller = _buildController(player);
    final mouse = await _hoveringPlayer(tester, controller);

    await controller.pause();
    await tester.pump();

    await mouse.moveTo(const Offset(-100, -100));
    await tester.pump(const Duration(milliseconds: 300));

    expect(controller.visibility.showControls, isTrue,
        reason: 'same rule as the auto-hide timer: nothing hides the controls '
            'while playback is paused');

    await controller.dispose();
    await tester.pump();
  });
}
