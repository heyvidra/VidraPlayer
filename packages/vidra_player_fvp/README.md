# vidra_player_kit (FVP)

FVP-backed implementation of the internal `Vidra Player` SDK.

This package is not meant to be published independently. In this repository it
acts as one possible target for the `vidra_player_kit` path dependency used by
the example app and host applications.

## Use this adapter

Point your app's `pubspec.yaml` to this directory:

```yaml
dependencies:
  vidra_player:
    path: ../vidra_player
  vidra_player_kit:
    path: ../vidra_player/packages/vidra_player_fvp
```

Then initialize it once at startup:

```dart
import 'package:flutter/widgets.dart';
import 'package:vidra_player_kit/vidra_player_kit.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  VidraPlayerKit.ensureInitialized();
  runApp(const MyApp());
}
```

## Notes

- Backend: `video_player` + `fvp`
- Adapter label logged at startup: `fvp`
- Intended for the repository's internal path-swapping workflow

See the root [README](../../README.md) for the full SDK API and example usage.
