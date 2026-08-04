import 'dart:async';

import 'package:fvp/mdk.dart' as mdk;
import 'package:vidra_player/core/interfaces/frame_sweeper.dart';

/// [FrameSweeper] on a raw mdk [mdk.Player]: sequential decode at boosted
/// rate, NO seeking. Every configuration choice below is a measured result
/// (2026-08-01 gate probes, recorded in vidraDlp's thumbnail task doc):
///
/// - Single-variant URL required: an ABR master paces the pipeline below
///   realtime (0.4x); the same content's lowest variant sweeps at 14x.
/// - Audio track disabled + `setBufferRange(min: 60s)`: 9.2x -> 14.2x.
/// - A parked player renders nothing — playback must be running before any
///   grab. Rendering is driven ENTIRELY by the texture's own render
///   callback (self-sustaining once playing); a second Dart-side
///   renderVideo() pump deadlocks against that callback — see the note in
///   the sweep loop.
/// - `dispose()` straight after a snapshot crashed the probe app; teardown
///   here pauses, settles, then disposes.
class MdkFrameSweeper implements FrameSweeper {
  @override
  Stream<SweptFrame> sweep(SweepRequest request) {
    late StreamController<SweptFrame> ctrl;
    var cancelled = false;
    final cancelSignal = Completer<void>();
    ctrl = StreamController<SweptFrame>(
      onListen: () => _run(ctrl, request, () => cancelled, cancelSignal),
      onCancel: () {
        cancelled = true;
        if (!cancelSignal.isCompleted) cancelSignal.complete();
      },
    );
    return ctrl.stream;
  }

  Future<void> _run(
    StreamController<SweptFrame> ctrl,
    SweepRequest req,
    bool Function() isCancelled,
    Completer<void> cancelSignal,
  ) async {
    final p = mdk.Player();
    try {
      p.media = req.url;
      p.mute = true;
      p.activeAudioTracks = [];
      p.setBufferRange(min: 60000, max: 120000);

      final startMs = req.startAt?.inMilliseconds ?? 0;
      // Raced against cancellation: prepare can pend up to 30s on a strained
      // CDN — exactly when users switch away — and a cancel that merely
      // flips a bool would leave this player prefetching hard against the
      // NEW episode's startup for the whole wait. The abandoned prepare
      // still resolves against the disposed player later; teardown's
      // pause-and-settle runs first either way.
      final prep = await Future.any([
        p
            .prepare(position: startMs)
            .timeout(const Duration(seconds: 30), onTimeout: () => -99),
        cancelSignal.future.then((_) => -100),
      ]);
      if (prep == -100 || isCancelled()) return;
      if (prep < 0) {
        throw StateError('sweep open failed ($prep) for ${req.url}');
      }

      // Both dimensions, or updateTexture returns -1 and nothing renders.
      final tex = await p.updateTexture(width: req.width, height: req.height);
      if (tex < 0) throw StateError('sweep texture failed for ${req.url}');

      const rate = 16.0;
      p.playbackRate = rate;
      p.state = mdk.PlaybackState.playing;

      // Poll granularity is multiplied by the playback rate: at 16x a 200ms
      // sleep advances 3.2s of content, which turned a requested 10s interval
      // into an irregular 10-14s and — measured — left two episodes sampled
      // on different grids, killing cross-episode frame matching. Poll at a
      // fraction of the FINEST interval expressed in wall time.
      final finestMs = (req.fineInterval ?? req.interval).inMilliseconds;
      final pollMs = ((finestMs / rate) / 4).clamp(30, 200).toInt();
      // Resolved lazily below when the engine does not know it yet. mdk
      // reports duration right after prepare for the sources measured here,
      // but the media_kit sweeper hit exactly this with HLS: an early read
      // returned 0, the end bound went infinite, and a sweep that had
      // covered the whole episode was then failed by the stall watchdog at
      // EOF. Same shape, same guard.
      int endMs = req.endAt?.inMilliseconds ?? p.mediaInfo.duration;
      if (endMs > 0) endMs -= 2000;

      // Far enough back that the first poll emits immediately.
      var lastEmitMs = startMs - (1 << 20);
      var lastPos = -1;
      var stalledSince = Stopwatch()..start();

      while (!isCancelled()) {
        await Future<void>.delayed(Duration(milliseconds: pollMs));
        if (isCancelled()) return;

        // Deliberately NO Dart-side renderVideo() pump here. With
        // updateTexture() in place the TexturePlayer's render callback is a
        // self-sustaining driver: each delivered frame renders and thereby
        // consumes the queue, which admits the next frame — no compositor
        // required (this is exactly how foreground playback renders). A
        // second driver from this isolate deadlocked in the field, sampled
        // live on 1.6.8: the Dart pump held mdk's renderer mutex and waited
        // on the player's recursive API mutex, while the render callback
        // held the API mutex and waited on the renderer — ABBA, 2187/2187
        // samples on both sides, whole UI isolate frozen. The 90s stall
        // watchdog below covers the case where callback-driven rendering
        // ever fails to sustain itself.
        final pos = p.position;

        if (endMs <= 0) {
          final d = p.mediaInfo.duration;
          if (d > 0) endMs = d - 2000;
        }

        // Stall watchdog: a sweep that stops advancing (dead CDN, wedged
        // demuxer) must end as an error, not run silently forever. 90s, not
        // 30s — measured on a production CDN, a mid-sweep network dip can
        // pause the pipeline well past 30s and then recover; this is
        // background work, patience costs nothing, and the resume-from-last-
        // tile retry upstream covers the genuinely dead case.
        if (pos != lastPos) {
          lastPos = pos;
          stalledSince = Stopwatch()..start();
        } else if (stalledSince.elapsed > const Duration(seconds: 90)) {
          throw TimeoutException('sweep stalled at ${pos}ms');
        }

        if (pos - lastEmitMs >= req.intervalAt(pos, endMs > 0 ? endMs : 0)
                .inMilliseconds) {
          final pixels = await p
              .snapshot(width: req.width, height: req.height)
              .timeout(const Duration(seconds: 5), onTimeout: () => null);
          if (isCancelled()) return;
          if (pixels != null && pixels.isNotEmpty) {
            lastEmitMs = pos;
            ctrl.add(
              SweptFrame.rawRgba(
                position: Duration(milliseconds: pos),
                width: req.width,
                height: req.height,
                pixels: pixels,
              ),
            );
          }
        }

        if (endMs > 0 && pos >= endMs) break;
      }
    } catch (e, st) {
      if (!ctrl.isClosed) ctrl.addError(e, st);
    } finally {
      // Measured crash: dispose() immediately after a snapshot cycle takes
      // the native side down. Park it, let the vo settle, then dispose.
      try {
        p.state = mdk.PlaybackState.paused;
        await Future<void>.delayed(const Duration(milliseconds: 300));
        // Destruction — and ONLY destruction — must wait for the host's gate.
        // dispose() reaches ~TexturePlayer on the platform thread, which
        // joins any in-flight render callback; that callback can be parked
        // on mdk's shared render lock for as long as the foreground decodes
        // (the foreground holds it across its frame-pacing sleep, so a
        // parked waiter starves indefinitely under first-fit mutexes).
        // Disposing in that state deadlocks the MAIN thread — sampled live
        // on a resume-from-pause: 1130/1130 in setRenderCallback. Pausing
        // above is safe and stops the lock traffic; the player then lingers
        // parked (tens of MB) until the foreground yields a quiet window.
        await req.disposeGate?.call();
        p.dispose();
      } catch (_) {
        // A leaked player beats a crashed process.
      }
      if (!ctrl.isClosed) await ctrl.close();
    }
  }
}
