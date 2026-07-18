import 'core/interfaces/video_player.dart';
import 'utils/log.dart';

/// Factory function alias for resolving a video player adapter.
typedef VidraPlayerFactory = IVideoPlayer Function();

/// Top-level SDK configuration and Dependency Injection (IoC) container.
///
/// To prevent Flutter from statically linking heavy C++ media decoder plugins
/// (like `media_kit` or `video_player`) on all platforms even when unused,
/// the core `vidra_player` SDK no longer depends on them directly.
///
/// ## Setup
///
/// In your host App, import the adapter alias package you want to use
/// (`vidra_player_kit` in this repository layout), and initialize it in `main()`:
///
/// ```dart
/// import 'package:vidra_player_kit/vidra_player_kit.dart';
///
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   VidraPlayerKit.ensureInitialized();
///   runApp(const MyApp());
/// }
/// ```
///
/// Alternatively, you can inject a factory manually:
/// ```dart
/// VidraPlayer.setPlayerFactory(() => MyCustomPlayerAdapter());
/// ```
///
/// After that, [PlayerController] will automatically use this factory
/// to create the player instance.
abstract final class VidraPlayer {
  VidraPlayer._();

  static VidraPlayerFactory? _factory;
  static String? _adapterLabel;

  /// Whether a player factory has been registered.
  static bool get isInitialized => _factory != null;
  static String? get adapterLabel => _adapterLabel;

  /// Register a factory function that creates an [IVideoPlayer] instance.
  ///
  /// This must be called before creating any [PlayerController] that doesn't
  /// explicitly provide a `player:` argument.
  static void setPlayerFactory(
    VidraPlayerFactory factory, {
    String adapterLabel = 'custom',
  }) {
    _factory = factory;
    _adapterLabel = adapterLabel;
    loggerNoStack.i('[VidraPlayer] Registered adapter: $adapterLabel');
  }

  /// Create a new [IVideoPlayer] instance using the registered factory.
  ///
  /// This is called automatically by [PlayerController]. You should rarely
  /// need to call this directly.
  ///
  /// Throws [StateError] if no factory has been registered.
  static IVideoPlayer createPlayer() {
    if (_factory == null) {
      throw StateError(
        'VidraPlayer has not been initialized with an adapter. '
        'You must either call an adapter\'s ensureInitialized() method '
        '(e.g. VidraPlayerKit.ensureInitialized()) in main(), '
        'or manually register a factory via VidraPlayer.setPlayerFactory().',
      );
    }
    if (_adapterLabel != null) {
      loggerNoStack.d('[VidraPlayer] Creating player via $_adapterLabel');
    }
    return _factory!();
  }
}
