// Right-click on the progress bar opens the intro/outro marker menu, and
// picking an entry writes the skip setting. Drives the real secondary-button
// gesture through the real widget tree — the Slider sitting on top of the bar
// must not swallow it.

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vidra_player/controller/player_controller.dart';
import 'package:vidra_player/core/interfaces/media_repository.dart';
import 'package:vidra_player/core/interfaces/video_player.dart';
import 'package:vidra_player/core/model/model.dart';
import 'package:vidra_player/core/model/player_locale.dart';
import 'package:vidra_player/core/state/states.dart';
import 'package:vidra_player/ui/controls/progress_bar.dart';
import 'package:vidra_player/ui/player_widget.dart';
import 'package:vidra_player/ui/widget/dropdown_menu.dart';

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
  Duration get duration => const Duration(minutes: 40);
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

  void emitPosition(Duration d) => _positionCtrl.add(d);

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

/// Implements ONLY MediaRepository, like the hosts in the wild — it never opted
/// into EpisodeMarkerStore, so a per-episode marker alone would never reach it.
class _SpyRepository implements MediaRepository {
  final List<PlayerSetting> saved = [];

  @override
  Future<List<EpisodeHistory>> getEpisodeHistories({
    required String videoId,
  }) async => const [];
  @override
  Future<void> saveEpisodeHistory(String v, EpisodeHistory h) async {}
  @override
  Future<PlayerSetting> getPlayerSettings({required String videoId}) async =>
      PlayerSetting(videoId: videoId);
  @override
  Future<void> savePlayerSettings(PlayerSetting setting) async {
    saved.add(setting);
  }
}

PlayerController _build(_FakeVideoPlayer player, {MediaRepository? repo}) =>
    PlayerController(
      mediaRepository: repo,
      config: const PlayerConfig(
        features: PlayerFeatures(enableHistory: false),
        behavior: PlayerBehavior(autoPlay: false, showControlsOnHover: true),
        locale: VidraLocale.zhCN,
      ),
      player: player,
      video: const VideoMetadata(
        id: 'v1',
        title: 'T',
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
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('right-click on the bar sets the outro marker', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final player = _FakeVideoPlayer();
    final repo = _SpyRepository();
    final controller = _build(player, repo: repo);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.macOS),
        home: Scaffold(body: VideoPlayerWidget(controller: controller)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await controller.play();
    // Duration only reaches the progress bar on a position tick.
    player.emitPosition(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 100));

    // Hover the video so the desktop controls (and the bar) are up.
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(10, 400));
    addTearDown(() => mouse.removePointer());
    await mouse.moveTo(tester.getCenter(find.byType(VideoPlayerWidget)));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    final bar = find.byType(VideoProgressBar);
    expect(bar, findsOneWidget);

    // Secondary-click three quarters along the bar: 30 min in, 10 min left.
    final rect = tester.getRect(bar);
    await tester.tapAt(
      Offset(rect.left + rect.width * 0.75, rect.center.dy),
      buttons: kSecondaryButton,
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(PlayerMenuPanel), findsOneWidget);
    expect(find.text('片头到此结束'), findsOneWidget);
    expect(find.text('片尾从此开始'), findsOneWidget);
    // Both rows quote the SAME clicked time. The intro row reading as an
    // absolute time while the outro row read as a remaining duration is what
    // made users stop and do arithmetic to realise they'd clicked one spot.
    final times = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byType(PlayerMenuPanel),
            matching: find.byType(Text),
          ),
        )
        .map((t) => t.data)
        .whereType<String>()
        .where((d) => RegExp(r'^\d+:\d{2}$').hasMatch(d))
        .toList();
    expect(times, hasLength(2));
    expect(times.first, times.last, reason: 'one click, one time');

    await tester.tap(find.text('片尾从此开始'));
    await tester.pump(const Duration(milliseconds: 100));

    // Menu closes; the marker lands on THIS episode as a manual edit, at the
    // clicked absolute time.
    expect(find.byType(PlayerMenuPanel), findsNothing);
    final markers = controller.currentMarkers;
    expect(markers, isNotNull);
    expect(markers!.episodeIndex, 0);
    expect(markers.source, MarkerSource.manual);
    expect(markers.outroStart!.inSeconds, closeTo(1800, 30), reason: '~30 min');
    expect(markers.introEnd, isNull);

    // And the skip logic sees it as a TAIL length, not the elapsed head.
    expect(
      controller.effectiveSkipSetting.skipOutro,
      closeTo(600, 30),
      reason: 'roughly 10 minutes of tail',
    );

    // The series-wide setting is written too. This is the part hosts actually
    // persist (MediaRepository.savePlayerSettings) and the part that carries to
    // the other episodes — a marker alone is session-only for any host that
    // hasn't opted into EpisodeMarkerStore.
    expect(
      controller.playerSetting.skipOutro,
      closeTo(600, 30),
      reason: 'right-click must reach the persisted, series-wide value',
    );
    expect(controller.playerSetting.skipIntro, 0);

    // ...and it reaches the host's persistence. Regression guard: routing the
    // right-click to markers only made it session-only for these hosts.
    await tester.pump(const Duration(milliseconds: 300));
    expect(repo.saved, isNotEmpty);
    expect(repo.saved.last.skipOutro, closeTo(600, 30));

    await controller.dispose();
    await tester.pump();
  });
}
