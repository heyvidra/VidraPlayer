// Regression: backing out of the resume prompt must not cost the viewer their
// place. Hiding the dialog clears resumeState and nothing else on screen shows
// where they had got to, so dismissing at 0:00 would strand them at the start —
// and the next position tick would write that 0 straight over the stored
// history, after which a run under 30s stops offering to resume at all.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vidra_player/controller/player_controller.dart';
import 'package:vidra_player/core/interfaces/media_repository.dart';
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

class _Repo implements MediaRepository {
  _Repo(this.stored);

  final EpisodeHistory stored;
  final List<EpisodeHistory> writes = [];

  @override
  Future<List<EpisodeHistory>> getEpisodeHistories({
    required String videoId,
  }) async => [stored];
  @override
  Future<void> saveEpisodeHistory(String v, EpisodeHistory h) async {
    writes.add(h);
  }

  @override
  Future<PlayerSetting> getPlayerSettings({required String videoId}) async =>
      PlayerSetting(videoId: videoId);
  @override
  Future<void> savePlayerSettings(PlayerSetting setting) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('escaping the resume prompt keeps the position and the history', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Watched to 1:20 of a 2:00 episode: past the 30s floor, under the 95%
    // ceiling, so loading it raises the resume prompt.
    final repo = _Repo(
      const EpisodeHistory(
        index: 0,
        positionMillis: 80000,
        durationMillis: 120000,
      ),
    );
    final player = _FakeVideoPlayer();
    final controller = PlayerController(
      config: const PlayerConfig(
        features: PlayerFeatures(enableHistory: true),
        behavior: PlayerBehavior(
          autoPlay: false,
          resumeMode: ResumeMode.prompt,
        ),
      ),
      player: player,
      mediaRepository: repo,
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
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.macOS),
        home: Scaffold(body: VideoPlayerWidget(controller: controller)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    expect(
      controller.visibility.showResumeDialog,
      isTrue,
      reason: 'a mid-progress history must raise the prompt',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 200));

    expect(controller.visibility.showResumeDialog, isFalse);
    expect(
      player.position,
      const Duration(milliseconds: 80000),
      reason: 'dismissing parks on the remembered position, not on 0:00',
    );

    // Now let playback run: the periodic save must never write a 0 over it.
    repo.writes.clear();
    player.emitPosition(Duration.zero);
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      repo.writes.where((h) => h.positionMillis == 0),
      isEmpty,
      reason: 'position 0 must not overwrite a real stored position',
    );

    await controller.dispose();
    await tester.pump();
  });
}
