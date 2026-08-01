import 'package:fvp/fvp.dart' as fvp;
import 'package:vidra_player/vidra_player.dart';
import 'src/frame_sweeper.dart';
import 'src/video_player.dart';

export 'src/frame_sweeper.dart';
export 'src/video_player.dart';

/// VidraPlayer FVP Plugin
///
/// This package provides the fallback/alternate playback engine for [VidraPlayer],
/// built on top of `video_player` and `fvp`.
abstract final class VidraPlayerKit {
  /// Ensures the `fvp` plugin is initialized and registers
  /// [VideoPlayerAdapter] as the global video player factory
  /// for [VidraPlayer].
  ///
  /// Call this once in `main()` before `runApp()`.
  static void ensureInitialized() {
    fvp.registerWith();
    VidraPlayer.setPlayerFactory(
      () => VideoPlayerAdapter(),
      adapterLabel: 'fvp',
    );
    // Optional capability: with this registered, PlayerController generates
    // sprite thumbnails in the background and progress-bar hover previews
    // work on every platform, not just macOS.
    VidraPlayer.setFrameSweeperFactory(MdkFrameSweeper.new);
  }
}
