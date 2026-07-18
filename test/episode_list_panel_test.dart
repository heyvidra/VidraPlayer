// Repro harness for "右上角切出 episodes 有问题": drive the full player widget,
// open the episode panel from the top-right button, interact, close it.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vidra_player/controller/player_controller.dart';
import 'package:vidra_player/core/interfaces/media_repository.dart';
import 'package:vidra_player/core/interfaces/video_player.dart';
import 'package:vidra_player/core/model/model.dart';
import 'package:vidra_player/core/state/states.dart';
import 'package:vidra_player/ui/overlays/episode_list.dart';
import 'package:vidra_player/ui/overlays/resume_dialog.dart';
import 'package:vidra_player/ui/player_widget.dart';

class _SeededRepository implements MediaRepository {
  final List<EpisodeHistory> histories;
  _SeededRepository(this.histories);

  @override
  Future<List<EpisodeHistory>> getEpisodeHistories({
    required String videoId,
  }) async => histories;

  @override
  Future<PlayerSetting> getPlayerSettings({required String videoId}) async =>
      const PlayerSetting(videoId: 'v1');

  @override
  Future<void> saveEpisodeHistory(
    String videoId,
    EpisodeHistory history,
  ) async {}

  @override
  Future<void> savePlayerSettings(PlayerSetting setting) async {}
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
  final initializedSources = <String>[];

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
  Future<void> initialize(VideoSource source) async {
    initializedSources.add(source.path);
  }

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

VideoEpisode _episode(int i) => VideoEpisode(
      index: i,
      title: '第${i + 1}集',
      qualities: [
        VideoQuality(
          label: '1080p',
          source: VideoSource.network('https://example.com/v$i.mp4'),
        ),
      ],
    );

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
    episodes: [_episode(0), _episode(1), _episode(2)],
  );
}

Future<PlayerController> _pumpPlayer(
  WidgetTester tester,
  _FakeVideoPlayer player, {
  TargetPlatform? platform,
}) async {
  final controller = _buildController(player);
  await tester.pumpWidget(
    MaterialApp(
      // ScreenHelper.isMobileLayout reads Theme.of(ctx).platform — passing
      // the platform via theme selects the desktop/mobile layout branch
      // without global debug overrides.
      theme: platform != null ? ThemeData(platform: platform) : null,
      home: Scaffold(body: VideoPlayerWidget(controller: controller)),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
  return controller;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('top-right button opens the episode panel', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final player = _FakeVideoPlayer();
    final controller = await _pumpPlayer(tester, player);

    await controller.play();
    controller.showControls();
    await tester.pump(const Duration(milliseconds: 100));

    // Default test platform is android -> mobile layout renders the plain
    // Icon branch (the desktop IconButton key doesn't exist here).
    final button = find.byIcon(Icons.list);
    expect(button, findsWidgets, reason: 'episodes button must render');

    await tester.tap(button.first, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 400)); // slide-in

    expect(controller.visibility.showEpisodeList, isTrue,
        reason: 'panel state must flip on');
    expect(find.byType(EpisodeList), findsOneWidget,
        reason: 'panel widget must be mounted');

    await controller.dispose();
    await tester.pump();
  });

  testWidgets('tapping an episode switches and closes the panel',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final player = _FakeVideoPlayer();
    final controller = await _pumpPlayer(tester, player);

    await controller.play();
    controller.showEpisodeList();
    await tester.pump(); // deliver visibility emission, start slide
    await tester.pump(const Duration(milliseconds: 350)); // finish slide
    expect(find.byType(EpisodeList), findsOneWidget);

    final episode2 = find.text('第2集');
    expect(episode2, findsWidgets, reason: 'episode entries must render');

    await tester.tap(episode2.first);
    await tester.pump(const Duration(milliseconds: 100));
    // Let the switch settle (load + play are fake-fast).
    await tester.pump(const Duration(milliseconds: 600));

    expect(controller.media.currentEpisodeIndex, 1,
        reason: 'switch must land on episode 2');
    expect(controller.visibility.showEpisodeList, isFalse,
        reason: 'panel must close after selection');

    await controller.dispose();
    await tester.pump();
  });

  group('desktop layout (macOS)', () {
    // The user-reported symptoms are on macOS: desktop layout renders the
    // IconButton top bar + DesktopVideoControls branch, which the default
    // android test platform never exercises. Platform is injected via
    // ThemeData(platform:) — ScreenHelper reads Theme.of(ctx).platform.

    testWidgets('top-right IconButton opens the episode panel', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final player = _FakeVideoPlayer();
      final controller = await _pumpPlayer(tester, player,
          platform: TargetPlatform.macOS);

      await controller.play();
      controller.showControls();
      await tester.pump(const Duration(milliseconds: 400));

      final button =
          find.byKey(const ValueKey('top_bar_episode_list_button'));
      expect(button, findsOneWidget,
          reason: 'desktop episodes IconButton must render');

      await tester.tap(button, warnIfMissed: false);
      await tester.pump(); // deliver emission, start slide
      await tester.pump(const Duration(milliseconds: 350)); // finish slide

      expect(controller.visibility.showEpisodeList, isTrue,
          reason: 'top-right tap must open the panel');
      expect(find.byType(EpisodeList), findsOneWidget);

      await controller.dispose();
      await tester.pump();
    });

    testWidgets('pause via center button flips its icon', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final player = _FakeVideoPlayer();
      final controller = await _pumpPlayer(tester, player,
          platform: TargetPlatform.macOS);

      await controller.play();
      controller.showControls();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byIcon(Icons.pause), findsWidgets,
          reason: 'playing state must show pause icon(s)');

      // Tap the center pause button.
      await tester.tap(find.byIcon(Icons.pause).first, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 300));

      expect(controller.lifecycle.isPlaying, isFalse,
          reason: 'playback must actually pause');
      expect(find.byIcon(Icons.play_arrow), findsWidgets,
          reason: 'button must flip to play icon after pausing');

      // And back.
      await tester.tap(find.byIcon(Icons.play_arrow).first,
          warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 300));
      expect(controller.lifecycle.isPlaying, isTrue);
      expect(find.byIcon(Icons.pause), findsWidgets,
          reason: 'button must flip back to pause icon');

      await controller.dispose();
      await tester.pump();
    });

    testWidgets('shown controls sit at full fade opacity (not dimmed)',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final player = _FakeVideoPlayer();
      final controller = await _pumpPlayer(tester, player,
          platform: TargetPlatform.macOS);

      await controller.play();
      // Hide, then re-show: exercises the fade both ways.
      controller.hideControls();
      await tester.pump(const Duration(milliseconds: 400));
      controller.showControls();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400)); // finish fade-in

      final fades = tester
          .widgetList<FadeTransition>(find.byType(FadeTransition))
          .toList();
      expect(fades, isNotEmpty);
      for (final fade in fades) {
        expect(fade.opacity.value, anyOf(0.0, 1.0),
            reason: 'no fade may be stuck mid-way after settling');
      }

      await controller.dispose();
      await tester.pump();
    });
  });

  group('startup resume-dialog window', () {
    // Repro of "启动后短暂无法点击控制栏，过一会儿自己好了": with watch history
    // present (the example app has history enabled), startup shows the resume
    // dialog, which owns the screen — control bars are hidden AND
    // IgnorePointer-blocked until it closes (auto-close default 10s).
    testWidgets(
        'while the dialog is up controls stay hidden — even on keypress — '
        'and come back interactive after continuing', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final player = _FakeVideoPlayer();
      final controller = PlayerController(
        config: const PlayerConfig(
          features: PlayerFeatures(enableHistory: true),
          behavior: PlayerBehavior(autoPlay: true),
        ),
        player: player,
        video: const VideoMetadata(
          id: 'v1',
          title: 'Test Video',
          coverUrl: 'http://test.com/cover.jpg',
        ),
        episodes: [_episode(0), _episode(1)],
        mediaRepository: _SeededRepository(const [
          EpisodeHistory(index: 0, positionMillis: 45000, durationMillis: 120000),
        ]),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.macOS),
          home: Scaffold(body: VideoPlayerWidget(controller: controller)),
        ),
      );
      // Startup: load + 100ms resume-delegate delay + history read.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(controller.visibility.showResumeDialog, isTrue,
          reason: 'mid-progress history must prompt resume at startup');
      expect(find.byType(ResumeDialog), findsOneWidget);
      expect(controller.visibility.showControls, isFalse,
          reason: 'dialog owns the screen — control bars must be hidden, '
              'not visible-but-unclickable');

      // A keypress during the dialog must NOT summon the (pointer-dead)
      // control bars.
      controller.handleKeyboardShortcut('m');
      await tester.pump(const Duration(milliseconds: 100));
      expect(controller.visibility.showControls, isFalse,
          reason: 'keyboard interaction must not paint dead controls '
              'behind the dialog');

      // Continue playback (what the countdown/继续播放 button does).
      await controller.continuePlayback(45000);
      await tester.pump(const Duration(milliseconds: 200));

      expect(controller.visibility.showResumeDialog, isFalse);
      expect(controller.visibility.showControls, isTrue,
          reason: 'controls must return after the dialog closes');
      expect(controller.lifecycle.isPlaying, isTrue);

      await controller.dispose();
      await tester.pump();
    });
  });

  testWidgets('toggle button closes an open panel', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final player = _FakeVideoPlayer();
    final controller = await _pumpPlayer(tester, player);

    await controller.play();
    controller.showControls();
    await tester.pump(const Duration(milliseconds: 100));

    final button = find.byIcon(Icons.list);
    await tester.tap(button.first, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 400));
    expect(controller.visibility.showEpisodeList, isTrue);

    await tester.tap(button.first, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 400));
    expect(controller.visibility.showEpisodeList, isFalse,
        reason: 'second tap must close the panel');

    await controller.dispose();
    await tester.pump();
  });
}
