// The feedback loop around a hand-placed skip point: it must confirm, be
// undoable, be clearable, and never cut away the instant it is set.
//
// Before this, right-clicking produced no visible change whatsoever — no
// toast, no mark on the bar, and the intro only takes effect on the NEXT
// episode — so the honest reading was "it didn't work". And a marker placed
// at or behind the playhead satisfied the outro condition on the very next
// tick, jumping straight to the next episode.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vidra_player/controller/player_controller.dart';
import 'package:vidra_player/core/interfaces/video_player.dart';
import 'package:vidra_player/core/model/model.dart';
import 'package:vidra_player/core/model/player_locale.dart';
import 'package:vidra_player/core/state/states.dart';
import 'package:vidra_player/ui/controls/skip_prompt.dart';
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
  Duration get duration => const Duration(minutes: 40);
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

  void emitPosition(Duration d) {
    _position = d;
    _positionCtrl.add(d);
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

PlayerController _build(_FakeVideoPlayer player) => PlayerController(
  config: const PlayerConfig(
    features: PlayerFeatures(enableHistory: false, enableAutoPlayNext: true),
    behavior: PlayerBehavior(autoPlay: false),
    locale: VidraLocale.zhCN,
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
    VideoEpisode(
      index: 1,
      title: 'E2',
      qualities: [
        VideoQuality(
          label: '1080p',
          source: VideoSource.network('https://example.com/v1.mp4'),
        ),
      ],
    ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(PlayerController, _FakeVideoPlayer)> pump(WidgetTester tester) async {
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
    player.emitPosition(const Duration(minutes: 10));
    await tester.pump(const Duration(milliseconds: 100));
    return (controller, player);
  }

  testWidgets('setting a skip point confirms on screen and can be undone', (
    tester,
  ) async {
    final (controller, _) = await pump(tester);

    controller.setSkipPoint(introEnd: const Duration(seconds: 90));
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      controller.visibility.skipNotification,
      SkipNotificationType.markerSet,
    );
    expect(find.byType(SkipPrompt), findsOneWidget);
    expect(find.textContaining('01:30'), findsOneWidget);
    expect(controller.effectiveSkipSetting.skipIntro, 90);

    await tester.tap(find.text('撤销'));
    await tester.pump(const Duration(milliseconds: 200));

    expect(controller.playerSetting.skipIntro, 0);
    expect(controller.currentMarkers?.introEnd, isNull);
    expect(controller.visibility.skipNotification, SkipNotificationType.none);

    await controller.dispose();
    await tester.pump();
  });

  testWidgets('clearing removes both the marker and the series-wide value', (
    tester,
  ) async {
    final (controller, _) = await pump(tester);

    controller.setSkipPoint(introEnd: const Duration(seconds: 90));
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.hasSkipPoints, isTrue);

    controller.clearSkipPoints();
    await tester.pump(const Duration(milliseconds: 100));

    expect(controller.hasSkipPoints, isFalse);
    expect(controller.playerSetting.skipIntro, 0);
    expect(controller.effectiveSkipSetting.skipIntro, 0);

    await controller.dispose();
    await tester.pump();
  });

  testWidgets('an outro marked behind the playhead does not cut away at once', (
    tester,
  ) async {
    final (controller, player) = await pump(tester);
    expect(controller.media.currentEpisodeIndex, 0);

    // Right-click at the current position: remaining == skipOutro exactly, so
    // the auto-skip condition is satisfied immediately.
    controller.setSkipPoint(outroStart: const Duration(minutes: 10));
    await tester.pump(const Duration(milliseconds: 100));

    player.emitPosition(const Duration(minutes: 10, seconds: 1));
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      controller.media.currentEpisodeIndex,
      0,
      reason:
          'setting a skip point must not yank the viewer to the next '
          'episode a tick later',
    );

    await controller.dispose();
    await tester.pump();
  });
}
