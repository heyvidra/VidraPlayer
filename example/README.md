# vidra_player_example

Example application for the internal `vidra_player` SDK.

## What it shows

- Registering the `vidra_player_kit` adapter alias
- Creating a `PlayerController` with episodes and multiple player features
- Switching themes, locale, fullscreen, and PiP behavior inside a host app

## Run the example

The example currently points `vidra_player_kit` to the FVP adapter:

```yaml
vidra_player_kit:
  path: ../packages/vidra_player_fvp
```

To try the other backend, change that path to:

```yaml
vidra_player_kit:
  path: ../packages/vidra_player_media_kit
```

Then run:

```bash
flutter pub get
flutter run
```
