// A switch to an episode that is already open should be over before anyone
// could read an overlay — so it does not draw one, unless the handover stalls.

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vidra_player/ui/overlays/switching_overlay.dart';
import 'package:vidra_player/vidra_player.dart';

import 'player_controller_test.dart' show FakeVideoPlayer, FakeWindowDelegate;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<PlayerController> pump(WidgetTester tester, SwitchingState s) async {
    final controller = PlayerController(
      config: const PlayerConfig(
        features: PlayerFeatures(enableHistory: false),
        behavior: PlayerBehavior(autoPlay: false),
      ),
      player: FakeVideoPlayer(),
      windowDelegate: FakeWindowDelegate(),
      video: const VideoMetadata(id: 'v', title: 'T', coverUrl: ''),
      episodes: const [
        VideoEpisode(
          index: 0,
          title: 'E1',
          qualities: [
            VideoQuality(
              label: 'SD',
              source: VideoSource.network('https://x/1'),
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SwitchingOverlay(
          controller: controller,
          state: s,
          theme: const PlayerUITheme.dark(),
        ),
      ),
    );
    return controller;
  }

  testWidgets('an ordinary switch says so at once', (tester) async {
    final c = await pump(
      tester,
      const SwitchingState(isSwitching: true, targetQualityLabel: 'E2'),
    );
    expect(find.textContaining('E2'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await c.dispose();
  });

  testWidgets('a quiet switch draws nothing, until it drags on', (
    tester,
  ) async {
    final c = await pump(
      tester,
      const SwitchingState(
        isSwitching: true,
        targetQualityLabel: 'E2',
        quiet: true,
      ),
    );
    expect(find.textContaining('E2'), findsNothing);

    await tester.pump(const Duration(milliseconds: 1600));
    expect(find.textContaining('E2'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await c.dispose();
  });
}
