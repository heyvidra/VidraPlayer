// Regression: playback ends -> replay dialog -> taps OUTSIDE the card.
// The ReplayDialog is a centered card with no full-screen barrier, so outside
// taps fall through to the gesture layer's toggleControls — which used to
// paint visible-but-IgnorePointer-dead control bars behind the dialog (and
// alternate them off again on the next tap). While a dialog owns the screen,
// video-area taps must be no-ops; dialog buttons are the only exits.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vidra_player/controller/player_controller.dart';
import 'package:vidra_player/core/interfaces/video_player.dart';
import 'package:vidra_player/core/model/model.dart';
import 'package:vidra_player/core/state/states.dart';
import 'package:vidra_player/ui/overlays/resume_dialog.dart';
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
  Duration get duration => const Duration(minutes: 2);
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

  void emitPosition(Duration pos) {
    _position = pos;
    _positionCtrl.add(pos);
  }

  void emitCompleted() {
    _isPlaying = false;
    _playingCtrl.add(false);
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
  Future<void> seek(Duration position) async {
    _position = position;
  }

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('outside taps during the replay dialog are no-ops; '
      'replay restores interactive controls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final player = _FakeVideoPlayer();
    // Single episode => playlist end shows the replay dialog.
    final controller = PlayerController(
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
          title: 'Only Episode',
          qualities: [
            VideoQuality(
              label: '1080p',
              source: VideoSource.network('https://example.com/v0.mp4'),
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.macOS),
        home: Scaffold(body: VideoPlayerWidget(controller: controller)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    await controller.play();
    await tester.pump(const Duration(milliseconds: 100));

    // Drive to EOF -> replay dialog.
    player.emitPosition(const Duration(minutes: 2));
    player.emitCompleted();
    await tester.pump(const Duration(milliseconds: 100));

    expect(controller.visibility.showReplayDialog, isTrue);
    expect(find.byType(ReplayDialog), findsOneWidget);
    expect(controller.visibility.showControls, isFalse);

    // Tap OUTSIDE the centered card (top-left corner of the player), then
    // wait past the double-tap disambiguation window (~300ms) + debounce.
    await tester.tapAt(const Offset(40, 40));
    await tester.pump(const Duration(milliseconds: 450));

    expect(controller.visibility.showReplayDialog, isTrue,
        reason: 'outside tap must not dismiss the dialog');
    expect(controller.visibility.showControls, isFalse,
        reason: 'outside tap must not paint pointer-dead controls '
            'behind the dialog');

    // A second outside tap must be an identical no-op (used to alternate
    // dead controls on/off).
    await tester.tapAt(const Offset(40, 40));
    await tester.pump(const Duration(milliseconds: 450));
    expect(controller.visibility.showControls, isFalse);
    expect(controller.visibility.showReplayDialog, isTrue);

    // The dialog's own action is the exit: replay closes it and restores
    // interactive controls.
    await controller.replayEpisode();
    await tester.pump(const Duration(milliseconds: 200));
    expect(controller.visibility.showReplayDialog, isFalse);
    expect(controller.visibility.showControls, isTrue,
        reason: 'controls must return after the dialog closes');
    expect(controller.lifecycle.isPlaying, isTrue);

    await controller.dispose();
    await tester.pump();
  });
}
