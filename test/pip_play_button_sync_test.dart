// Diagnostic repro: PiP (macOS = same window resized to 500x280) desyncs the
// center PlayPauseButton (stateful morph icon) from the bottom-bar play/pause
// StreamBuilder icon.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vidra_player/controller/player_controller.dart';
import 'package:vidra_player/core/interfaces/video_player.dart';
import 'package:vidra_player/core/interfaces/window_delegate.dart';
import 'package:vidra_player/core/model/model.dart';
import 'package:vidra_player/core/state/states.dart';
import 'package:vidra_player/ui/player_widget.dart';
import 'package:vidra_player/ui/widget/toggle_icon_button.dart';

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
  bool playShouldThrow = false;

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

  /// Simulates a play/pause initiated OUTSIDE the Flutter UI (native window
  /// control, media keys, OS audio interruption).
  void emitExternalPlaying(bool playing) {
    _isPlaying = playing;
    _playingCtrl.add(playing);
  }

  @override
  Future<void> initialize(VideoSource source) async {}

  @override
  Future<void> play() async {
    if (playShouldThrow) throw StateError('play blocked');
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

/// Reads the center PlayPauseButton's effective glyph: the pause icon's
/// opacity is the morph controller's value (1 = pause glyph, 0 = play glyph).
double _centerPauseOpacity(WidgetTester tester) {
  final opacities = tester.widgetList<Opacity>(
    find.descendant(
      of: find.byType(PlayPauseButton),
      matching: find.byType(Opacity),
    ),
  );
  for (final o in opacities) {
    final iconFinder = find.descendant(
      of: find.byWidget(o),
      matching: find.byIcon(Icons.pause),
    );
    if (iconFinder.evaluate().isNotEmpty) return o.opacity;
  }
  fail('pause glyph not found inside PlayPauseButton');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('PiP roundtrip with external pause keeps both buttons in sync', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final player = _FakeVideoPlayer();
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
          title: 'E1',
          qualities: [
            VideoQuality(
              label: '1080p',
              source: VideoSource.network('https://example.com/v0.mp4'),
            ),
          ],
        ),
      ],
      windowDelegate: _FakeWindowDelegate(),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.macOS),
        home: Scaffold(body: VideoPlayerWidget(controller: controller)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    await controller.play();
    controller.showControls();
    await tester.pump(); // deliver emissions, start morph
    await tester.pump(const Duration(milliseconds: 400)); // finish morph

    expect(controller.lifecycle.isPlaying, isTrue);
    expect(_centerPauseOpacity(tester), 1.0,
        reason: 'playing: center must show pause glyph');

    // Enter PiP: macOS shrinks the SAME window to ~500x280.
    controller.togglePip();
    await tester.pump(const Duration(milliseconds: 100));
    tester.view.physicalSize = const Size(500, 280);
    await tester.pump(const Duration(milliseconds: 400));
    expect(controller.view.isPip, isTrue);

    // Pause from OUTSIDE the Flutter UI while in PiP.
    player.emitExternalPlaying(false);
    await tester.pump(); // deliver reconciliation emission
    await tester.pump(const Duration(milliseconds: 400)); // finish morph
    expect(controller.lifecycle.isPlaying, isFalse,
        reason: 'external pause must reconcile lifecycle');

    // Exit PiP: window restored.
    controller.togglePip();
    await tester.pump(const Duration(milliseconds: 100));
    tester.view.physicalSize = const Size(1280, 800);
    await tester.pump(const Duration(milliseconds: 100));
    controller.showControls();
    await tester.pump(const Duration(milliseconds: 500));

    // Both buttons must agree with reality (paused -> play glyphs).
    expect(controller.lifecycle.isPlaying, isFalse);
    expect(_centerPauseOpacity(tester), 0.0,
        reason: 'paused: center must show play glyph');
    final bottomPlay = find.descendant(
      of: find.byKey(const ValueKey('bottom_bar_play_pause_button')),
      matching: find.byIcon(Icons.play_arrow),
    );
    expect(bottomPlay, findsOneWidget,
        reason: 'paused: bottom bar must show play glyph');

    await controller.dispose();
    await tester.pump();
  });

  testWidgets(
      'failed play() (optimistic flip + revert coalesced into one frame) '
      'must not strand the center morph on the wrong glyph', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final player = _FakeVideoPlayer();
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
          title: 'E1',
          qualities: [
            VideoQuality(
              label: '1080p',
              source: VideoSource.network('https://example.com/v0.mp4'),
            ),
          ],
        ),
      ],
      windowDelegate: _FakeWindowDelegate(),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.macOS),
        home: Scaffold(body: VideoPlayerWidget(controller: controller)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // Paused, controls visible: both buttons show the play glyph.
    controller.showControls();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(controller.lifecycle.isPlaying, isFalse);
    expect(_centerPauseOpacity(tester), 0.0);

    // Tap center while play() is rejected (PiP/native quirk, autoplay
    // block...): the optimistic playing emission and its rollback coalesce
    // into one rebuild, so the prop edge never reaches didUpdateWidget.
    player.playShouldThrow = true;
    await tester.tap(find.byType(PlayPauseButton), warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(controller.lifecycle.isPlaying, isFalse,
        reason: 'play() failed — state must stay paused');
    expect(_centerPauseOpacity(tester), 0.0,
        reason: 'center morph must converge back to the play glyph, '
            'matching the bottom-bar icon');

    await controller.dispose();
    await tester.pump();
  });
}
