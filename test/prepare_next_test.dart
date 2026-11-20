// A short drama is hundreds of two-minute episodes. The next one is opened
// while this one is finishing, so the switch does not start from a spinner.
// These pin WHEN that happens: once, near the end, for the right episode.

import 'package:flutter_test/flutter_test.dart';
import 'package:vidra_player/vidra_player.dart';

import 'player_controller_test.dart' show FakeVideoPlayer, FakeWindowDelegate;

const _episodes = [
  VideoEpisode(
    index: 0,
    title: 'Episode 1',
    qualities: [
      VideoQuality(
        label: 'SD',
        source: VideoSource.network('https://x/1.m3u8'),
      ),
    ],
  ),
  VideoEpisode(
    index: 1,
    title: 'Episode 2',
    qualities: [
      VideoQuality(
        label: 'SD',
        source: VideoSource.network('https://x/2.m3u8'),
      ),
    ],
  ),
];

PlayerController _controller(
  FakeVideoPlayer player,
  List<String> resolved, {
  bool preload = true,
}) => PlayerController(
  config: PlayerConfig(
    features: const PlayerFeatures(enableHistory: false),
    behavior: PlayerBehavior(autoPlay: false, preloadNextEpisode: preload),
  ),
  player: player,
  windowDelegate: FakeWindowDelegate(),
  video: const VideoMetadata(id: 'v', title: 'T', coverUrl: ''),
  episodes: _episodes,
  sourceResolver: (source) async {
    resolved.add(source.path);
    return source;
  },
);

Future<void> _tick() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the next episode is prepared once, in the last seconds', () async {
    final player = FakeVideoPlayer(); // 2 minutes long
    final resolved = <String>[];
    final controller = _controller(player, resolved);
    await _tick();
    await _tick();
    resolved.clear(); // The first episode's own open.

    player.emitPosition(const Duration(seconds: 60));
    await _tick();
    expect(resolved, isEmpty, reason: 'a minute from the end is too early');

    player.emitPosition(const Duration(seconds: 108));
    await _tick();
    player.emitPosition(const Duration(seconds: 109));
    await _tick();
    expect(resolved, ['https://x/2.m3u8'], reason: 'once, not per tick');

    await controller.dispose();
  });

  test('a host that turned it off gets nothing opened early', () async {
    final player = FakeVideoPlayer();
    final resolved = <String>[];
    final controller = _controller(player, resolved, preload: false);
    await _tick();
    await _tick();
    resolved.clear();

    player.emitPosition(const Duration(seconds: 110));
    await _tick();
    expect(resolved, isEmpty);

    await controller.dispose();
  });
}
