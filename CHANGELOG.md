## 1.1.0

- Per-episode intro/outro markers (`EpisodeMarkers`) with a source ranking —
  manual edits outrank detected ones, which outrank chapters. They override the
  series-wide `PlayerSetting.skipIntro`/`skipOutro`, which stays the fallback.
- Read intro/outro markers from HLS `EXT-X-DATERANGE` chapters when the source
  has them. Probed in parallel with opening the player, so it costs no latency.
- Optional `EpisodeMarkerStore` for persisting markers. Separate from
  `MediaRepository` so existing repositories are unaffected; without it markers
  live for the session only.
- Right-clicking the progress bar sets a skip point: a manual marker on this
  episode plus the series-wide `PlayerSetting`, so it persists through the
  `MediaRepository` every host already implements and covers every episode.
- A one-off hint, shown in the opening minute of a video with no skip points
  configured, pointing at that right-click menu. Desktop only.
- Progress-bar hover tooltip sits clear of the playhead instead of over it.

## 1.0.0

- Initial release: Flutter video player SDK with multi-episode playlists, quality switching, resume/replay from watch history, auto-skip intro/outro, auto-play-next, keyboard shortcuts, fullscreen and picture-in-picture, desktop and mobile control layouts, theming/localization, and pluggable player adapters (fvp / media_kit).
