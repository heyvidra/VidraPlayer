// Regression tests for "controls become unclickable after playing a while":
// 1. Touch tap must summon hidden controls (no hover-show/toggle race).
// 2. A hung platform open() must not wedge openWithRetry (and with it the
//    input-blocking switching overlay) forever.
// 3. An open dropdown menu must hold the auto-hide timer so controls can't
//    hide underneath the menu's full-screen close barrier.

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vidra_player/controller/player_controller.dart';
import 'package:vidra_player/core/adapters/base_video_player_adapter.dart';
import 'package:vidra_player/core/interfaces/video_player.dart';
import 'package:vidra_player/core/lifecycle/lifecycle_token.dart';
import 'package:vidra_player/core/model/model.dart';
import 'package:vidra_player/core/state/states.dart';
import 'package:vidra_player/managers/ui_manager.dart';
import 'package:vidra_player/ui/controls/volume_control.dart';
import 'package:vidra_player/ui/layers/gesture_detector_layer.dart';
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

PlayerController _buildController(IVideoPlayer player) {
  return PlayerController(
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
}

/// Minimal adapter exposing the protected [openWithRetry] for direct testing.
class _TestAdapter extends BaseVideoPlayerAdapter {
  @override
  Future<void> onInitialize(VideoSource source, LifecycleToken token) async {}
  @override
  Future<void> onReset() async {}
  @override
  Widget buildRenderWidget(Key? key, BoxFit fit, Alignment alignment) =>
      const SizedBox.shrink();

  @override
  Duration get duration => Duration.zero;
  @override
  Duration get position => Duration.zero;
  @override
  bool get isPlaying => false;
  @override
  bool get isLive => false;
  @override
  VideoSize? get videoSize => null;

  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> setPlaybackSpeed(double speed) async {}

  Future<void> callOpenWithRetry({
    required Future<void> Function() open,
    required Duration openCallTimeout,
  }) {
    return openWithRetry(
      maxRetries: 1,
      token: lifecycleToken,
      open: open,
      errorStream: const Stream<String>.empty(),
      isFatalError: (_) => true,
      waitForFormat: (cancelToken) async {},
      openCallTimeout: openCallTimeout,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('touch tap summons hidden controls (hover/toggle race)', () {
    testWidgets('jittery touch tap shows controls and they stay', (
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

      // A real-device tap: down + small jitter move + up. The move must NOT
      // pre-show the controls (that would make the later onTap toggle them
      // straight back off).
      final gesture = await tester.createGesture(kind: PointerDeviceKind.touch);
      await gesture.down(tester.getCenter(find.byType(GestureDetectorLayer)));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.moveBy(const Offset(2, 1));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.up();

      // Past kDoubleTapTimeout (~300ms, the single-tap disambiguation delay)
      // plus the ui manager's 50ms show debounce.
      await tester.pump(const Duration(milliseconds: 500));
      expect(controller.visibility.showControls, isTrue);

      // And they stay up (forced-show window is 5s).
      await tester.pump(const Duration(seconds: 1));
      expect(controller.visibility.showControls, isTrue);

      await controller.dispose();
      await tester.pump();
    });

    testWidgets('mouse hover still shows controls (desktop regression)', (
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

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await tester.pump();
      await gesture.moveTo(tester.getCenter(find.byType(GestureDetectorLayer)));
      await tester.pump(const Duration(milliseconds: 200));

      expect(controller.visibility.showControls, isTrue);

      await controller.dispose();
      await tester.pump();
    });

    testWidgets('hovering visible control bar prevents auto-hide', (
      tester,
    ) async {
      final player = _FakeVideoPlayer();
      final controller = _buildController(player);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.macOS),
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 450,
              child: VideoPlayerWidget(controller: controller),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 150));

      await controller.play();
      controller.showControlsTemporarily();
      await tester.pump(const Duration(milliseconds: 100));
      expect(controller.visibility.showControls, isTrue);

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await tester.pump();
      await gesture.moveTo(
        tester.getCenter(find.byKey(const ValueKey('playback_controls'))),
      );
      await tester.pump(const Duration(milliseconds: 100));

      await tester.pump(const Duration(seconds: 4));
      expect(
        controller.visibility.showControls,
        isTrue,
        reason: 'controls must not hide while the pointer is over the bar',
      );

      await controller.dispose();
      await tester.pump();
    });
  });

  test(
    'openWithRetry: a hung open() times out instead of wedging forever',
    () async {
      final adapter = _TestAdapter();

      // Without the open-call timeout this future would never complete and
      // the switching overlay would block all player input forever.
      await expectLater(
        adapter.callOpenWithRetry(
          open: () => Completer<void>().future,
          openCallTimeout: const Duration(milliseconds: 50),
        ),
        throwsException,
      );

      await adapter.dispose();
    },
  );

  testWidgets(
    'volume control unmounted while hovered does not pin controls visible',
    (tester) async {
      final player = _FakeVideoPlayer();
      final controller = _buildController(player);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: VolumeControl(controller: controller)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 150));

      // Hover the volume control, then unmount it while still hovered —
      // MouseRegion.onExit never fires in that case (Flutter caveat).
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await tester.pump();
      await gesture.moveTo(tester.getCenter(find.byType(VolumeControl)));
      await tester.pump();

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));

      // Auto-hide must still work: a stuck isHoveringControls flag would
      // re-arm the timer forever and keep the controls visible.
      await controller.play();
      controller.showControlsTemporarily();
      await tester.pump(const Duration(milliseconds: 100));
      expect(controller.visibility.showControls, isTrue);

      await tester.pump(const Duration(seconds: 4)); // > 3s autoHideDelay
      expect(controller.visibility.showControls, isFalse);

      await controller.dispose();
      await tester.pump();
    },
  );

  test('paused/buffering does not force-show controls behind a dialog', () {
    fakeAsync((async) {
      final ui = UIStateManager(behavior: const PlayerBehavior());
      ui.updatePlaybackState(isPlaying: true, isInitialized: true);

      ui.showResumeDialog(
        const ResumeState(positionMillis: 45000, durationMillis: 120000),
      );
      expect(ui.currentVisibility.showControls, isFalse);

      // Pause + buffering flips used to re-assert fully visible but
      // pointer-dead controls behind the dialog.
      ui.updatePlaybackState(isPlaying: false);
      expect(ui.currentVisibility.showControls, isFalse);

      ui.hideResumeDialog();
      expect(ui.currentVisibility.resumeState, isNull);

      ui.dispose();
    });
  });

  test('copyWith force-clear flags null out dialog states', () {
    const state = UIVisibilityState(
      resumeState: ResumeState(positionMillis: 1, durationMillis: 2),
      replayState: ResumeState(positionMillis: 3, durationMillis: 4),
    );

    // Plain `field: null` is swallowed by copyWith's ?? — documented trap.
    expect(state.copyWith().resumeState, isNotNull);

    expect(state.copyWith(forceClearResumeState: true).resumeState, isNull);
    expect(state.copyWith(forceClearResumeState: true).replayState, isNotNull);
    expect(state.copyWith(forceClearReplayState: true).replayState, isNull);
  });

  test('open menu holds auto-hide even when playback re-arms the timer', () {
    fakeAsync((async) {
      final ui = UIStateManager(behavior: const PlayerBehavior());
      ui.updatePlaybackState(isPlaying: true, isInitialized: true);
      ui.showControlsTemporarily();
      async.elapse(const Duration(milliseconds: 100));
      expect(ui.currentVisibility.showControls, isTrue);

      ui.showMoreMenu();
      // The backstop path that used to re-arm the timer behind an open menu:
      // a "still playing" report with controls visible and no active timer.
      ui.updatePlaybackState(isPlaying: true);
      async.elapse(const Duration(seconds: 10));
      expect(
        ui.currentVisibility.showControls,
        isTrue,
        reason: 'controls must not hide under an open menu',
      );

      ui.hideMoreMenu();
      async.elapse(const Duration(seconds: 5));
      expect(
        ui.currentVisibility.showControls,
        isFalse,
        reason: 'auto-hide resumes after the menu closes',
      );

      ui.dispose();
    });
  });

  test('a minimize while a menu is open must not hide controls (menu strand)',
      () {
    final ui = UIStateManager(behavior: const PlayerBehavior());
    ui.updatePlaybackState(isPlaying: true, isInitialized: true);
    ui.showControlsForced(duration: Duration.zero);
    expect(ui.currentVisibility.showControls, isTrue);

    // Menu open: a spurious "minimized" (e.g. transient host window-occlusion)
    // must NOT collapse the controls — that strands the menu overlay at the
    // top-left because its LayerLink leader (a control button) stops painting.
    ui.showMoreMenu();
    ui.updateWindowState(isMinimized: true);
    expect(ui.currentVisibility.showControls, isTrue,
        reason: 'controls must stay while a menu is open, even on minimize');

    // Sanity: with no menu open, minimize DOES hide everything.
    ui.hideMoreMenu();
    ui.updateWindowState(isMinimized: false);
    ui.showControlsForced(duration: Duration.zero);
    expect(ui.currentVisibility.showControls, isTrue);
    ui.updateWindowState(isMinimized: true);
    expect(ui.currentVisibility.showControls, isFalse,
        reason: 'minimize hides controls when no menu is open');

    ui.dispose();
  });
}
