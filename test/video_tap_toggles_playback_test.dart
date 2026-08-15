// Tapping the video picture: a MOUSE click plays/pauses (the controls are a
// mouse-move away, so a click doesn't need to fetch them), while a TOUCH tap
// still summons the controls — on a touch screen there is no hover, so if a
// tap toggled playback instead, the control bar would be unreachable.
//
// Either way, taps beside a resume/replay dialog stay no-ops: the card has no
// full-screen barrier, so they land on the gesture layer, and the dialog's own
// buttons must remain the only exits.

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vidra_player/controller/player_controller.dart';
import 'package:vidra_player/core/interfaces/video_player.dart';
import 'package:vidra_player/core/model/model.dart';
import 'package:vidra_player/core/state/states.dart';
import 'package:vidra_player/ui/layers/gesture_detector_layer.dart';

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

  /// Drive to end-of-media, which is what raises the replay dialog.
  void emitEof(Duration duration) {
    _positionCtrl.add(duration);
    _completedCtrl.add(true);
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

/// One tap of [kind] in the middle of the gesture layer, waited out past the
/// ~300ms single-tap disambiguation delay and the 50ms show debounce.
Future<void> _tap(WidgetTester tester, PointerDeviceKind kind) async {
  final gesture = await tester.createGesture(kind: kind);
  await gesture.down(tester.getCenter(find.byType(GestureDetectorLayer)));
  await tester.pump(const Duration(milliseconds: 16));
  await gesture.up();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  testWidgets('mouse click toggles playback, not control visibility', (
    tester,
  ) async {
    final player = _FakeVideoPlayer();
    final controller = _buildController(player);
    await tester.pumpWidget(GestureDetectorLayer(controller: controller));
    await tester.pump(const Duration(milliseconds: 150));

    await controller.play();
    await tester.pump();
    expect(controller.lifecycle.isPlaying, isTrue);

    await _tap(tester, PointerDeviceKind.mouse);
    expect(controller.lifecycle.isPlaying, isFalse,
        reason: 'click on the picture must pause');
    expect(controller.visibility.showControls, isTrue,
        reason: 'the click brings the controls up as feedback — pausing into '
            'a bare picture shows nothing registered');

    await _tap(tester, PointerDeviceKind.mouse);
    expect(controller.lifecycle.isPlaying, isTrue,
        reason: 'a second click must resume');

    await controller.dispose();
    await tester.pump();
  });

  testWidgets('touch tap still toggles the controls and leaves playback alone', (
    tester,
  ) async {
    final player = _FakeVideoPlayer();
    final controller = _buildController(player);
    await tester.pumpWidget(GestureDetectorLayer(controller: controller));
    await tester.pump(const Duration(milliseconds: 150));

    await controller.play();
    controller.hideControls();
    await tester.pump();
    expect(controller.visibility.showControls, isFalse);

    await _tap(tester, PointerDeviceKind.touch);
    expect(controller.visibility.showControls, isTrue,
        reason: 'touch has no hover — a tap is the only way to the controls');
    expect(controller.lifecycle.isPlaying, isTrue,
        reason: 'touch tap must NOT toggle playback');

    await controller.dispose();
    await tester.pump();
  });

  testWidgets('a click beside a replay dialog is a no-op', (tester) async {
    final player = _FakeVideoPlayer();
    final controller = _buildController(player);
    await tester.pumpWidget(GestureDetectorLayer(controller: controller));
    await tester.pump(const Duration(milliseconds: 150));

    await controller.play();
    await tester.pump(const Duration(milliseconds: 100));
    player.emitEof(const Duration(minutes: 2));
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.visibility.showReplayDialog, isTrue);

    final wasPlaying = controller.lifecycle.isPlaying;
    await _tap(tester, PointerDeviceKind.mouse);

    expect(controller.lifecycle.isPlaying, wasPlaying,
        reason: 'the dialog owns the screen — a click behind it must not '
            'start or stop playback');
    expect(controller.visibility.showReplayDialog, isTrue,
        reason: 'and must not dismiss the dialog');

    await controller.dispose();
    await tester.pump();
  });
}
