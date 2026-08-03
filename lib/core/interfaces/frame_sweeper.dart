import 'dart:typed_data';

/// One frame delivered by a [FrameSweeper].
///
/// Engines differ in what they hand back — mdk's `snapshot()` gives raw RGBA,
/// mpv's `screenshot()` gives encoded PNG/JPEG — so both shapes are first
/// class here. Re-encoding an already-encoded frame just to normalise would
/// cost a decode plus an encode per tile for no gain.
class SweptFrame {
  /// Content position the frame belongs to.
  final Duration position;

  /// Raw RGBA (`width * height * 4` bytes) when [isEncoded] is false;
  /// PNG/JPEG file bytes when it is true.
  final Uint8List bytes;

  /// Whether [bytes] is already an encoded image.
  final bool isEncoded;

  /// Pixel dimensions. Meaningful only for raw frames — an encoded frame
  /// carries its own, so both are 0.
  final int width;
  final int height;

  /// A frame the SDK must encode before display.
  const SweptFrame.rawRgba({
    required this.position,
    required this.width,
    required this.height,
    required Uint8List pixels,
  }) : bytes = pixels,
       isEncoded = false;

  /// A frame the engine already encoded (PNG or JPEG) — stored as-is.
  const SweptFrame.encoded({required this.position, required this.bytes})
    : isEncoded = true,
      width = 0,
      height = 0;
}

/// Parameters for one sweep run.
class SweepRequest {
  /// Media to sweep. Callers MUST pass a single-variant URL — handing an ABR
  /// master playlist to the engine throttles the whole pipeline to below
  /// realtime (measured: 0.4x on a master vs 14x on its lowest variant).
  final String url;

  /// Content-time spacing between delivered frames.
  ///
  /// Implementations must poll fast enough to honour this: at a boosted
  /// playback rate, wall-clock polling granularity multiplies. Measured on
  /// device before this was stated — a 200ms poll at 16x made a requested
  /// 10s interval land at an irregular 10-14s, and the two episodes being
  /// compared ended up sampled on different grids, which made cross-episode
  /// frame matching impossible in principle.
  final Duration interval;

  /// Tighter spacing to use inside [fineRegion] windows at each end of the
  /// media. Null means [interval] everywhere.
  ///
  /// Detection compares frames ACROSS episodes, so it needs both sides
  /// sampled densely enough that some pair lands on the same moment of a
  /// shared intro. A 10s grid cannot: two episodes whose intros start 3s
  /// apart never sample the same instant.
  final Duration? fineInterval;

  /// How much of the start and the end gets [fineInterval] spacing.
  final Duration fineRegion;

  /// Frame size. Thumbnails, not stills — keep it small.
  final int width;
  final int height;

  /// Open the media at this position instead of 0 (tail sweeps). Fresh-open
  /// at a position is cheap and position-independent (~2-5s measured); a
  /// runtime seek is not.
  final Duration? startAt;

  /// Stop sweeping once this position is reached (defaults to end of media).
  final Duration? endAt;

  /// Awaited by the sweeper immediately before destroying its player.
  /// Pausing/stopping the sweep is always safe; DESTRUCTION is not — on the
  /// fvp engine the texture-player destructor runs on the platform thread
  /// and waits for any in-flight render callback, and a render callback can
  /// stay parked on mdk's shared render lock for as long as the foreground
  /// keeps decoding (sampled live: main thread blocked 1130/1130 in
  /// ~TexturePlayer -> setRenderCallback while the foreground played — a
  /// whole-app deadlock, not a starve). The host completes this future only
  /// when the foreground is not decoding; until then the sweeper must sit
  /// parked. Null means dispose immediately.
  final Future<void> Function()? disposeGate;

  const SweepRequest({
    required this.url,
    this.interval = const Duration(seconds: 10),
    this.fineInterval,
    this.fineRegion = const Duration(minutes: 4),
    this.width = 160,
    this.height = 90,
    this.startAt,
    this.endAt,
    this.disposeGate,
  });

  /// Spacing that applies at content position [positionMs], given the media
  /// length ([durationMs], 0 when not yet known).
  Duration intervalAt(int positionMs, int durationMs) {
    final fine = fineInterval;
    if (fine == null) return interval;
    final region = fineRegion.inMilliseconds;
    if (positionMs <= region) return fine;
    if (durationMs > 0 && positionMs >= durationMs - region) return fine;
    return interval;
  }
}

/// Optional capability: decode a stream in the background and deliver frames
/// at intervals, WITHOUT seeking — sequential decode at boosted rate is two
/// orders of magnitude cheaper than per-position seeks on HLS.
///
/// Separate from [IVideoPlayer] on purpose: `implements` requires every
/// member, so growing that interface breaks every existing adapter. Adapter
/// packages that can sweep register a factory via
/// `VidraPlayer.setFrameSweeperFactory`; hosts without one simply get no
/// sprite thumbnails, exactly as before.
abstract class FrameSweeper {
  /// Sweep [request.url] and emit frames ~[SweepRequest.interval] apart.
  ///
  /// The stream closes when the sweep reaches [SweepRequest.endAt] / end of
  /// media, errors on open failure, and stops promptly when the subscription
  /// is cancelled. Implementations own their player instance's lifecycle.
  Stream<SweptFrame> sweep(SweepRequest request);
}
