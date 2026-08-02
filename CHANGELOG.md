## 1.3.0

### Added

- **Progress-bar hover previews on every platform**, not just macOS. With a
  `FrameSweeper` registered (the fvp adapter package registers one in
  `ensureInitialized`), the controller sweeps the episode being watched in
  the background — lowest quality variant, no seeking, sequential decode at
  boosted rate — and hover serves the pre-generated sprite tiles. macOS keeps
  its native seek-accurate previews and uses sprites as the fallback. Sweeps
  start only after 10s of stable playback, resume from where they left off
  after a network stall, stop retrying after three failures, and are cancelled
  the moment the user switches episodes.
- `FrameSweeper` / `SweepRequest` / `SweptFrame` — optional adapter capability
  (same non-breaking pattern as `EpisodeMarkerStore`), registered via
  `VidraPlayer.setFrameSweeperFactory`.
- Hovering the progress bar now fills the track from the start to the cursor,
  so the stretch a click would seek to is visible before clicking.

### Changed

- **The buffered segment is finally visible.** It was always painted, but the
  fvp adapter left mdk's packet buffer at its ~4s default — under 2px on a
  44-minute episode, and hidden under the playhead. The adapter now raises
  the ceiling to 60s (floor untouched at 4s, so start-up latency is
  unchanged: measured 878ms vs 2242ms against a colder CDN). The bar reads
  as runway ahead of the playhead, which is what mdk reports — it resets on
  seek because the engine keeps no download history, and painting an
  accumulated range would claim data that HLS would still re-fetch.
- Buffered colour raised to ~40% opacity across every theme preset; several
  sat within a few percent of the track colour and were invisible regardless.
- The hover preview collapses when it has no frame yet instead of showing a
  broken-image placeholder, and the time bubble is positioned independently
  of it — a shared frame sized for the 160px preview froze the bubble 80px
  short of either edge, and left it off-centre whenever the preview was
  absent.

- **A stuck episode/quality switch can now be cancelled.** The blocking
  switching overlay grows a cancel button once a switch outlives 3 seconds
  (fast switches never flash it). Cancelling drops the overlay immediately,
  silently abandons the in-flight load — no error, nothing failed, the user
  changed their mind — and leaves every episode/quality action available,
  including re-opening the very episode that was cancelled. Also available
  programmatically as `PlayerController.cancelSwitching`.
- `BaseVideoPlayerAdapter.cancelLoad` / `PlaybackManager.cancelLoad`, the
  underlying abandon-the-open primitives.
- `SwitchingState.attempt`, a monotonic id of the current switch. UI keyed on
  `isSwitching` edges alone cannot see "cancel, then immediately switch
  again" — the two updates coalesce into one where the flag never flips.

### Changed

- The transition→event derivation rules (seek edges, the once-per-episode
  end-event latch, lifecycle status events) moved out of `PlayerController`
  into `PlaybackEventEmitter`, where they are unit-tested in isolation. No
  behavioral change; `lifecycleEvents` and every event payload are unchanged.

## 1.2.0

### Breaking

- **Resuming no longer opens a dialog by default.** A video with watch history
  now picks up where it left off and reports that in a dismissible corner card
  carrying "start over". Restore the old behaviour with
  `PlayerBehavior(resumeMode: ResumeMode.prompt)` — or `promptWithCountdown`
  for the auto-resume countdown, which used to be wired to `resumeOnFocus`
  where nobody could find it.
- `SkipNotificationType` gained `markerSet`. Exhaustive switches over it need a
  new case.

### Added

- Hand-placed skip points now confirm on screen, can be undone from that
  confirmation, are drawn as bands on the progress bar, and can be cleared from
  the right-click menu — previously setting one produced no visible change at
  all and could never be removed.
- `PlayerController.clearSkipPoints` / `undoSkipPoint` / `hasSkipPoints`,
  `EpisodeMarkers.clear`.
- `dismissResumeDialog`, so the resume prompt has an exit that doesn't play.

### Fixed

- A modal resume/replay dialog no longer lets keystrokes through to the player.
  Space used to start playback from 0:00 behind a dialog that never closed,
  over control bars that are IgnorePointer-blocked while it is up. Enter takes
  the dialog's primary action, Escape backs out, everything else is swallowed —
  and Enter is handed back to the host app when no dialog is showing.
- Dismissing the resume prompt parks on the remembered position instead of
  stranding the viewer at 0:00, where the next position tick would overwrite
  the stored history.
- Periodic progress saves now guard `position > 0`, matching the three
  immediate-save paths.
- "Cancel" on the finished-episode dialog no longer replays the episode.
- Setting an outro marker at or behind the playhead no longer cuts to the next
  episode a tick later.
- Progress-bar tooltip and the right-click menu's two rows now read against one
  baseline; `auto_skip_opening` says the same thing in all three locales.

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
