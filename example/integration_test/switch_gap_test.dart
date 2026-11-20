// Measures what a viewer sits through between two episodes: from the last
// moment the first one was moving to the first moment the second one is.
// Real backend, real network, no mouse. Run with:
//   flutter test integration_test/switch_gap_test.dart -d macos


import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vidra_player/vidra_player.dart';
import 'package:vidra_player_kit/vidra_player_kit.dart';

const _stream = String.fromEnvironment(
  'STREAM',
  defaultValue: 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
);

List<VideoEpisode> _episodes() => [
  for (var i = 0; i < 2; i++)
    VideoEpisode(
      index: i,
      title: 'E${i + 1}',
      qualities: [
        VideoQuality(
          label: 'auto',
          // Same stream, distinct URLs: the player must treat them as two.
          source: VideoSource.network('$_stream?episode=$i'),
        ),
      ],
    ),
];

Future<int> _measure(WidgetTester tester, {required bool preload}) async {
  final controller = PlayerController(
    config: PlayerConfig(
      features: const PlayerFeatures(enableHistory: false),
      behavior: PlayerBehavior(
        autoPlay: true,
        muteOnStart: true,
        preloadNextEpisode: preload,
      ),
    ),
    video: const VideoMetadata(id: 'gap', title: 'gap', coverUrl: ''),
    episodes: _episodes(),
    windowDelegate: const StandardWindowDelegate(),
  );
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: VideoPlayerWidget(controller: controller),
      ),
    ),
  );

  final clock = Stopwatch()..start();
  int? lastMovingOnFirst;
  int? firstMovingOnSecond;
  var lastPos = Duration.zero;
  final sub = controller.positionStream.listen((p) {
    final index = controller.media.currentEpisodeIndex;
    final moved = p.position > lastPos;
    lastPos = p.position;
    if (index == 0 && moved) lastMovingOnFirst = clock.elapsedMilliseconds;
    if (index == 1 &&
        firstMovingOnSecond == null &&
        p.position > const Duration(milliseconds: 300)) {
      firstMovingOnSecond = clock.elapsedMilliseconds;
    }
  });

  Future<void> until(bool Function() done, String what) async {
    for (var i = 0; i < 600 && !done(); i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(done(), isTrue, reason: 'timed out waiting for $what');
  }

  await until(
    () => controller.position.duration > const Duration(seconds: 30),
    'the first episode to open',
  );
  final duration = controller.position.duration;
  // Far enough out that the pre-open has its full lead.
  await controller.seek(
    duration - const Duration(seconds: 22),
    SeekSource.external,
  );
  await until(() => firstMovingOnSecond != null, 'the second episode to play');

  final gap = firstMovingOnSecond! - lastMovingOnFirst!;
  await sub.cancel();
  await tester.pumpWidget(const SizedBox());
  await controller.dispose();
  await tester.pump(const Duration(seconds: 1));
  return gap;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  VidraPlayerKit.ensureInitialized();

  testWidgets('gap between episodes, cold open vs pre-opened', (tester) async {
    final cold = await _measure(tester, preload: false);
    final warm = await _measure(tester, preload: true);
    // ignore: avoid_print
    print('SWITCH_GAP cold_ms=$cold preopened_ms=$warm');
    expect(warm, lessThan(cold), reason: 'pre-opening must not be slower');
  });
}
