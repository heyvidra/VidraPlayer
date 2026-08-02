import 'package:media_kit/media_kit.dart';
import 'package:vidra_player/vidra_player.dart';
import 'src/frame_sweeper.dart';
import 'src/media_kit_player.dart';

export 'src/frame_sweeper.dart';
export 'src/media_kit_player.dart';

/// VidraPlayer MediaKit Plugin
///
/// This package provides the desktop playback engine for [VidraPlayer],
/// built on top of `media_kit` (libmpv).
abstract final class VidraPlayerKit {
  /// Ensures the `media_kit` plugin is initialized and registers
  /// [MediaKitPlayerAdapter] as the global video player factory
  /// for [VidraPlayer].
  ///
  /// Call this once in `main()` before `runApp()`.
  static void ensureInitialized() {
    MediaKit.ensureInitialized();
    VidraPlayer.setPlayerFactory(
      () => MediaKitPlayerAdapter(),
      adapterLabel: 'media_kit',
    );
    // Optional capability, registered by both adapter packages so hover
    // thumbnails behave identically whichever engine the host picks.
    VidraPlayer.setFrameSweeperFactory(MediaKitFrameSweeper.new);
  }
}
