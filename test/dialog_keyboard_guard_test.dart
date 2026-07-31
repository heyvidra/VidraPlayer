// Regression: a modal resume/replay dialog must own the keyboard.
//
// Space is the most reflexive "just play it" key on desktop. It used to reach
// the player straight through the dialog: playback started from 0:00 BEHIND a
// dialog that never closed, over control bars that are IgnorePointer-blocked
// while it is up — no pause, no seek, no way out. And "cancel" on the finished
// -episode dialog called play() too, so all three buttons replayed the episode
// and none of them meant "I'm done".

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vidra_player/controller/player_controller.dart';
import 'package:vidra_player/core/interfaces/video_player.dart';
import 'package:vidra_player/core/model/model.dart';
import 'package:vidra_player/core/state/states.dart';
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

  int playCalls = 0;

  @override
  Future<void> play() async {
    playCalls++;
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

  Future<(PlayerController, _FakeVideoPlayer)> pumpToReplayDialog(
    WidgetTester tester,
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

    player.emitPosition(const Duration(minutes: 2));
    player.emitCompleted();
    await tester.pump(const Duration(milliseconds: 100));

    expect(controller.visibility.showReplayDialog, isTrue);
    return (controller, player);
  }

  testWidgets('space does not start playback behind the replay dialog', (
    tester,
  ) async {
    final (controller, player) = await pumpToReplayDialog(tester);
    final playsBefore = player.playCalls;

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      player.playCalls,
      playsBefore,
      reason: 'space must not reach the player while a dialog is modal',
    );
    expect(
      controller.visibility.showReplayDialog,
      isTrue,
      reason: 'and it must not silently dismiss the dialog either',
    );

    await controller.dispose();
    await tester.pump();
  });

  testWidgets('escape closes the replay dialog without playing', (
    tester,
  ) async {
    final (controller, player) = await pumpToReplayDialog(tester);
    final playsBefore = player.playCalls;

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 100));

    expect(controller.visibility.showReplayDialog, isFalse);
    expect(
      player.playCalls,
      playsBefore,
      reason: 'the exit from a finished episode must be a real exit',
    );

    await controller.dispose();
    await tester.pump();
  });

  testWidgets('dismissing the finished-episode dialog does not replay it', (
    tester,
  ) async {
    final (controller, player) = await pumpToReplayDialog(tester);
    final playsBefore = player.playCalls;

    await controller.dismissReplayDialog();
    await tester.pump(const Duration(milliseconds: 100));

    expect(controller.visibility.showReplayDialog, isFalse);
    expect(player.playCalls, playsBefore);
    expect(
      controller.lifecycle.isPlaying,
      isFalse,
      reason: 'cancel means stop, not "replay from 0:00 like the other button"',
    );

    await controller.dispose();
    await tester.pump();
  });

  testWidgets('enter takes the primary action: replay when there is no next', (
    tester,
  ) async {
    final (controller, player) = await pumpToReplayDialog(tester);
    final playsBefore = player.playCalls;

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 200));

    expect(controller.visibility.showReplayDialog, isFalse);
    expect(
      player.playCalls,
      greaterThan(playsBefore),
      reason: 'enter confirms the dialog',
    );

    await controller.dispose();
    await tester.pump();
  });

  testWidgets('enter is handed back to the host when no dialog is up', (
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

    var hostEnter = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.macOS),
        home: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.enter): () => hostEnter++,
          },
          child: Scaffold(body: VideoPlayerWidget(controller: controller)),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(controller.visibility.showReplayDialog, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      hostEnter,
      1,
      reason:
          'the player only owns Enter while a dialog is modal; claiming it '
          'the rest of the time silently eats the host app binding',
    );

    await controller.dispose();
    await tester.pump();
  });
}
