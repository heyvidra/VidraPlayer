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
  final Duration interval;

  /// Frame size. Thumbnails, not stills — keep it small.
  final int width;
  final int height;

  /// Open the media at this position instead of 0 (tail sweeps). Fresh-open
  /// at a position is cheap and position-independent (~2-5s measured); a
  /// runtime seek is not.
  final Duration? startAt;

  /// Stop sweeping once this position is reached (defaults to end of media).
  final Duration? endAt;

  const SweepRequest({
    required this.url,
    this.interval = const Duration(seconds: 10),
    this.width = 160,
    this.height = 90,
    this.startAt,
    this.endAt,
  });
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
