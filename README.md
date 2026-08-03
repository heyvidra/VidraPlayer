# Vidra Player

A production-quality video player SDK for Flutter desktop, built around a
strict public-API boundary and swappable playback engines. One controller
API; the engine underneath (fvp/mdk or media_kit/mpv) is an implementation
detail chosen at initialization.

## ✨ Features

- **Swappable engines** — `vidra_player_fvp` (mdk) and
  `vidra_player_media_kit` (mpv) implement the same adapter interface;
  hosts switch by changing one dependency. Feature parity includes
  thumbnails and background sweeping on both.
- **Episode management** — multi-episode series, auto-advance,
  cancellable episode/quality switching (a switch in flight can be
  aborted without corrupting state).
- **Quality switching** — seamless, carrying the current position across.
- **Smart resume** — remembers position per episode and prompts to resume.
- **Intro/outro skip** — three marker layers with strict precedence
  (`manual > detected > chapter`), series-wide fallback seconds, and
  auto-skip.
- **Cross-episode intro/outro detection** — the background sweep
  perceptual-hashes frames (dHash, 64-bit); two episodes of a series are
  compared for a shared run and skip markers are written automatically.
  Hashes persist through an opt-in store, so detection works across
  restarts and never re-pays the sweep.
- **Sprite thumbnails** — a background `FrameSweeper` decodes the episode
  at 16x (lowest variant, no seeking) and hover-scrubbing serves the
  pre-generated tiles on every platform. macOS additionally keeps native
  seek-accurate previews.
- **Progress bar** — buffered ranges, YouTube-style hover fill, hover
  thumbnail + time bubble, right-click marker menu.
- **Lifecycle events** — one typed stream (`PlayerCreated`,
  `MediaInitialized`, `EpisodeChanged`, `EpisodeEnded`, `PlaylistEnded`,
  `MediaLoadFailed`, …) instead of state polling.
- **Desktop-class input** — keyboard shortcuts, PiP, fullscreen,
  wakelock, window-delegate hooks.
- **Strict API boundary** — managers/delegates are never exported;
  internals can be refactored without breaking hosts.

## 📦 Packages

| Package | Role |
|---|---|
| `vidra_player` | Core SDK: controller, UI, models, interfaces. Engine-agnostic. |
| `packages/vidra_player_fvp` | Adapter on fvp/mdk. Registers a player factory + `FrameSweeper`. |
| `packages/vidra_player_media_kit` | Adapter on media_kit/mpv. Same surface, same sweeper contract. |

```yaml
dependencies:
  vidra_player:
    git:
      url: https://github.com/heyvidra/VidraPlayer.git
      ref: <commit>          # pin to a commit (see the host repo's pubspec for why)
  vidra_player_kit:
    git:
      url: https://github.com/heyvidra/VidraPlayer.git
      path: packages/vidra_player_fvp   # or packages/vidra_player_media_kit
      ref: <tag>
```

## 🚀 Quick Start

Register the engine once, before any controller exists. Startup logs print
the registered adapter (`fvp` or `media_kit`).

```dart
import 'package:flutter/widgets.dart';
import 'package:vidra_player_kit/vidra_player_kit.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  VidraPlayerKit.ensureInitialized(); // registers the engine + frame sweeper
  runApp(const MyApp());
}
```

```dart
import 'package:flutter/material.dart';
import 'package:vidra_player/vidra_player.dart';

class _MyPlayerPageState extends State<MyPlayerPage> {
  late final PlayerController _controller = PlayerController(
    config: PlayerConfig(
      behavior: const PlayerBehavior(autoPlay: true, enableThumbnail: true),
      features: const PlayerFeatures(enableHistory: true),
    ),
    video: const VideoMetadata(
      id: 'v1',
      title: 'Example Video',
      coverUrl: 'https://example.com/poster.jpg',
    ),
    episodes: const [
      VideoEpisode(
        index: 0,
        title: 'Episode 1',
        qualities: [
          VideoQuality(
            label: '1080p',
            source: VideoSource.network('https://example.com/video.m3u8'),
          ),
        ],
      ),
    ],
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: VideoPlayerWidget(controller: _controller));
}
```

## 💾 Persistence (opt-in interfaces)

Every host implements `MediaRepository` (history + settings). Two further
interfaces are deliberately separate so adding them never breaks existing
repositories:

| Interface | Persists | Without it |
|---|---|---|
| `MediaRepository` | Playback history, series-wide skip seconds | required |
| `EpisodeMarkerStore` | Per-episode intro/outro markers | markers last one session |
| `EpisodeHashStore` | Sweep hashes (~4 KB/episode, versioned blob) | detection needs two fresh sweeps per session |

```dart
class MyRepo implements MediaRepository, EpisodeMarkerStore, EpisodeHashStore {
  // store and return the hash blob unchanged — the SDK versions it and
  // discards anything it does not recognise
}
```

Preview tiles are intentionally **not** persisted: ~2 MB/episode for
something the background sweep regenerates within minutes of playback.

## 🔄 Lifecycle Events

```dart
controller.lifecycleEvents.listen((event) {
  switch (event) {
    case MediaInitialized(duration: var d):
      print('loaded: $d');
    case EpisodeChanged(from: var a, to: var b):
      print('${a?.title} -> ${b.title}');
    case PlaylistEnded():          // last episode ended NATURALLY only
      showUpNext();
    case MediaLoadFailed(error: var e):
      print(e.message);
    default:
      break;
  }
});
```

| Event | Trigger |
|-------|---------|
| `MediaInitialized` | Metadata loaded, player ready to display |
| `EpisodeChanged` | Episode index changed (auto-advance or user) |
| `EpisodeEnded` | Any episode finished naturally |
| `PlaylistEnded` | The **last** episode finished naturally — never on manual skip |

## ⌨️ Keyboard Shortcuts

| Key | Action |
|-----|--------|
| Space | Play / Pause |
| F / Esc | Enter / exit fullscreen |
| M | Mute |
| ← / → | Seek ±5 s |
| J / L | Seek ±10 s |
| ↑ / ↓ | Volume ±10 % |
| < / > | Playback speed |

## 🏗️ Architecture

**Delegate–Manager** with a sealed public boundary:

- **Delegates (logic)** — `ResumeDelegate`, `SkipDelegate`,
  `EpisodeDelegate`: focused decision-making pulled out of the controller.
- **Managers (state)** — `PlaybackManager`, `MediaManager`,
  `UIStateManager`, `SpriteSweepService`: stream-owning internals.
- **Detection (pure)** — `SharedRunDetector` + `perceptual_hash`: hashes
  in, seconds out. Every threshold is a measured value with the
  measurement recorded beside it; real-data regression tests pin the
  defaults to production footage.
- **Engine seam** — `IVideoPlayer` + optional `FrameSweeper`, registered
  by the adapter package. Growing the sweeper never breaks adapters that
  lack it: hosts simply get no sprite thumbnails, as before.

Exports go through `lib/vidra_player.dart` with `show` lists — internals
are unreachable from outside.

## 🤝 Contributing

1. `flutter analyze` at the repo root, and in both `packages/*` adapters.
2. `flutter test` at the root — the suite includes real-data regression
   fixtures for detection; red/green any change to thresholds.
3. Check public exports in `lib/vidra_player.dart`.
4. Smoke-test `example/` against both engine packages.
