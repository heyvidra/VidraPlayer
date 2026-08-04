import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:fvp/mdk.dart' as mdk;
// ignore: implementation_imports
import 'package:fvp/src/generated_bindings.dart' as mdkc;
import 'package:vidra_player/core/interfaces/frame_sweeper.dart';

/// [FrameSweeper] on a raw mdk [mdk.Player]: sequential decode at boosted
/// rate, NO seeking. Every configuration choice below is a measured result
/// (2026-08-01 gate probes, recorded in vidraDlp's thumbnail task doc):
///
/// - Single-variant URL required: an ABR master paces the pipeline below
///   realtime (0.4x); the same content's lowest variant sweeps at 14x.
/// - Audio track disabled + `setBufferRange(min: 60s)`: 9.2x -> 14.2x.
/// - A parked player renders nothing — playback must be running before any
///   grab, and `renderVideo()` must be pumped because nothing composites
///   this player's frames. The pump is SAFE here and only here: the sweep
///   detaches the texture's render callback first, so it is the only thing
///   touching the renderer — see [_detachRenderCallback] for the two field
///   deadlocks that a second driver caused.
/// - `dispose()` straight after a snapshot crashed the probe app; teardown
///   here pauses, settles, then disposes.
/// Clears the render callback fvp's `TexturePlayer` registers inside
/// `updateTexture()` (`{ lock(tex.mtx); renderVideo(); frameAvailable(); }`).
///
/// fvp exposes no way to build the render target without that callback, and
/// no way to unregister it — but it does expose the raw mdk handle, and mdk's
/// C API takes a zeroed `mdkRenderCallback` as "none" (the C++ wrapper builds
/// exactly this struct for `setRenderCallback(nullptr)`).
void _detachRenderCallback(mdk.Player p) {
  final api = Pointer<mdkc.mdkPlayerAPI>.fromAddress(p.nativeHandle);
  final none = calloc<mdkc.mdkRenderCallback>();
  try {
    api.ref.setRenderCallback.asFunction<
        void Function(Pointer<mdkc.mdkPlayer>, mdkc.mdkRenderCallback)>()(
      api.ref.object,
      none.ref,
    );
  } finally {
    calloc.free(none);
  }
}

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
    Timer? pump;
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
      // The texture is the render TARGET and is not optional: mdk needs the
      // Metal surface fvp builds here or renderVideo() draws nowhere and
      // every snapshot fails (measured — and a failed snapshot hands fvp a
      // null SnapshotRequest, which it dereferences: SIGSEGV, whole app).
      final tex = await p.updateTexture(width: req.width, height: req.height);
      if (tex < 0) throw StateError('sweep texture failed for ${req.url}');
      // Keep the target, drop its render callback. That callback is what
      // deadlocked twice in the field: v1.4.3, ABBA against this loop's pump
      // across two threads; v1.4.4, with the pump gone, snapshot() drove the
      // render inline on the UI isolate and the callback re-entered the
      // renderer that same stack already held (sampled 2226/2226). Nobody
      // composites the sweep's frames, so the callback only ever existed to
      // feed a compositor that isn't there — detaching it leaves the pump
      // below as the one and only driver, with nothing left to race.
      _detachRenderCallback(p);

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

      // The pump lives OUTSIDE the sweep loop, and it has to: mdk completes a
      // snapshot on the next redraw, so a pump inside the loop is parked by
      // the very `await snapshot()` it has to service. Measured with the pump
      // inline: 13 tiles where ~450 were due, every miss a 5s timeout that a
      // late redraw then mis-delivered into the NEXT request. A timer keeps
      // rendering while the loop is parked.
      pump = Timer.periodic(
        Duration(milliseconds: pollMs),
        (_) => p.renderVideo(),
      );
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
        // Before anything else: a tick landing on a paused-and-torn-down
        // player renders into freed state.
        pump?.cancel();
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
