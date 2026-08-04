## 1.4.3

### Fixed

- **macOS native thumbnails: zombie CoreMedia sessions.** Disposing a
  thumbnail generator only dropped the dictionary reference; in-flight
  `AVAssetImageGenerator` requests kept the underlying HLS stream session
  alive — and on an expired stream URL, retrying forever (sampled live:
  two CoreMedia queue threads pegged and the audio queue kept warm hours
  after a pause). Dispose and deinit now cancel all generation, and every
  request carries an 8s timeout that cancels outright — the Dart side
  reads nil as "no preview" and the sprite fallback covers.

## 1.4.2

### Fixed

- **fvp: platform-thread deadlock when a cancelled sweep was disposed during
  playback.** v1.4.1 cancelled the background sweep on resume, but the
  cancel path destroyed the sweep player immediately — and `~TexturePlayer`
  runs on the platform thread and joins any in-flight render callback. That
  callback can stay parked on mdk's shared render lock for as long as the
  foreground decodes (the foreground holds the lock across its frame-pacing
  sleep), so the join never returned and the whole main thread froze
  (sampled live: 1130/1130 in `setRenderCallback`). Cancelling now only
  PAUSES the sweep player; destruction waits on a host-supplied
  `SweepRequest.disposeGate` that opens at the next quiet window (foreground
  paused/stopped or controller disposed). A parked, paused player lingers
  (tens of MB) until then — a leak-shaped cost, deliberately preferred over
  a deadlock-shaped one.

## 1.4.0

### Added

- **Cross-episode intro/outro detection.** The background sweep now also
  perceptual-hashes each frame (dHash, 64-bit), and two episodes of one series
  are compared for a shared run. A match writes `MarkerSource.detected`
  markers for both episodes AND the series-wide `skipIntro`, so episodes that
  were never swept skip too — the manual right-click path has always written
  both layers, and the detector was only writing one.

  Every threshold is a measured value, not a guess. The defaults were set from
  real production footage and then corrected twice by it: the first guesses
  (`maxOffset` 40s, `minRun` 20s, threshold 10, no gap tolerance) each hid a
  genuine 17-second title sequence sitting at a 96-SECOND offset, because one
  episode opened with a recap. `test/shared_run_real_data_test.dart` pins this
  with real hashes and asserts that each first guess would have missed it.

  `minRun` was then lowered again, from 14s to 10s: the SAME shared sequence
  of the SAME two episodes measures 17s on one sweep and 11s on the next,
  purely from where the sampler lands. A floor tuned to one measurement is a
  coin flip. The match COUNT is the discriminator; the duration is a loose
  sanity check. A second real-data fixture pins both samplings.

- **Optional `EpisodeHashStore`.** Hashes (~4KB per episode) persist so a later
  session can detect against an episode it never swept; without it the feature
  only ever fires when a viewer leaves the player open across two episodes.
  Same opt-in shape as `EpisodeMarkerStore` — hosts that skip it are unchanged.
  Preview TILES are deliberately not persisted: ~2MB per episode to avoid a
  sweep that costs nothing and regenerates within minutes of playback.

### Changed

- Sweep hashes are reported as soon as the head window is covered (~15s at 16x)
  rather than at end of sweep (~5min). Measured on device: ordinary episode
  browsing cancelled three sweeps in a row, so nothing was ever persisted and
  no marker ever appeared — despite enough having been gathered within seconds
  each time. `onSweepComplete` is now `onHashesReady` and fires twice.
- A marker that arrives mid-playback is applied immediately when the playhead
  is still inside the intro. The intro skip was decided once at episode start,
  long before detection finishes, so the episode the intro was found on played
  it in full with the marker sitting unused.
- The progress bar draws the series-wide skip setting when an episode has no
  marker of its own, matching how `effectiveSkipSetting` already merges the two
  layers. Previously the player skipped 90 seconds on an unswept episode while
  the bar drew nothing — acting on a boundary it refused to show.

### Fixed

- Tail detection no longer runs on a half-swept episode. `detectOutro` measures
  backwards from the last tile, so mid-sweep it treats wherever the sweep
  stopped as the credits: measured, it produced `outro=23s` on a 44-minute
  episode and persisted it, which auto-skip would have acted on. Completeness
  is tracked per episode and carried in the stored blob, so a restored partial
  set stays partial.
- `SpriteSweepService.clear()` dropped tiles but not hashes, despite both being
  keyed by episode index — a reordered catalog would have marked episode 3 from
  whatever used to be at index 3.
- `cancelSweep` was silent, making "the sweep died" indistinguishable in the
  log from "the sweep is still running".
- A null intro or outro now reports why (closest distance, longest run) instead
  of being reported as a bare `null`.

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
  `VidraPlayer.setFrameSweeperFactory`. **Both adapter packages implement it**,
  so hover thumbnails behave the same whichever engine a host picks; the two
  packages share a name and swapping one for the other needs no host code
  change. `SweptFrame` comes in `.rawRgba()` and `.encoded()` flavours because
  mdk hands back raw pixels and mpv hands back PNG — normalising would cost a
  decode plus an encode per tile for nothing.
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
- The media_kit adapter's read-ahead is now 60s too (`cache-secs` /
  `demuxer-readahead-secs`), so the buffered segment means the same thing on
  both engines.
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
