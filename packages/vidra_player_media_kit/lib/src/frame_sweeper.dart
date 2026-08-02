import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:vidra_player/core/interfaces/frame_sweeper.dart';

/// [FrameSweeper] on a background media_kit [Player]: sequential decode at a
/// boosted rate, NO seeking.
///
/// Mirrors the fvp/mdk sweeper, and every setting traces to the same measured
/// constraints (2026-08-01 gate probes, recorded in vidraDlp's thumbnail task
/// doc) translated to mpv:
///
/// - Single-variant URL required. `SpriteSweepService` resolves masters before
///   calling, so nothing extra is needed here — but `hls-bitrate=min` is set
///   anyway so a master that slips through still picks the cheapest variant
///   (the main adapter deliberately uses `max`; sweeping wants the opposite).
/// - Audio disabled and a wide read-ahead: mdk needed both to get from 0.6x to
///   14x, and mpv's knobs are `AudioTrack.no()` + `cache-secs` /
///   `demuxer-readahead-secs`.
/// - Playback must actually run. mpv decodes nothing while paused, so no
///   frame would ever appear.
///
/// One thing is genuinely simpler than mdk: `screenshot()` returns encoded
/// PNG bytes, so there is no raw-pixel channel order to get wrong and no
/// re-encode — the frames go straight into the tile cache.
class MediaKitFrameSweeper implements FrameSweeper {
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
    final player = Player(
      configuration: const PlayerConfiguration(
        title: 'VidraPlayer sweep',
        // No on-screen text to burn into thumbnails, and no libass cost.
        libass: false,
      ),
    );
    try {
      // mpv does not decode video without a video output, and in media_kit
      // the video output IS VideoController. Measured: without one, playback
      // reports playing=true while position stays at 0ms and screenshot()
      // returns nothing (0/10 frames); with one, 9/10 distinct frames and the
      // clock runs. It does NOT need to be mounted in the widget tree —
      // constructing it is enough. Same class of constraint as mdk needing
      // `state = playing` plus a renderVideo() pump.
      //
      // VideoController has no dispose(); it is torn down with its Player.
      VideoController(player);

      await _applySweepProperties(player);
      if (isCancelled()) return;

      // Open AT the resume position — measured on mdk as cheap and
      // position-independent (~2-5s), unlike a runtime seek which walks HLS
      // segments. Raced against cancellation: an open on a strained CDN can
      // pend for many seconds, and a doomed sweep must not keep prefetching
      // against the episode the user is actually watching.
      final media = Media(req.url, start: req.startAt);
      final opened = await Future.any([
        player.open(media, play: false).then((_) => true),
        cancelSignal.future.then((_) => false),
      ]).timeout(const Duration(seconds: 30), onTimeout: () => false);
      if (!opened || isCancelled()) return;

      // Audio off after open: the track list does not exist before it.
      await player.setAudioTrack(AudioTrack.no());
      const rate = 16.0;
      await player.setRate(rate);
      await player.play();

      // Poll granularity is multiplied by the playback rate: at 16x a 200ms
      // sleep advances 3.2s of content, so a requested 10s interval landed at
      // an irregular 10-14s and two episodes ended up sampled on different
      // grids — measured, and fatal to cross-episode frame matching.
      final finestMs = (req.fineInterval ?? req.interval).inMilliseconds;
      final pollMs = ((finestMs / rate) / 4).clamp(30, 200).toInt();

      final startMs = req.startAt?.inMilliseconds ?? 0;
      // Duration is resolved INSIDE the loop, not here: for HLS mpv does not
      // know it yet at this point (the main adapter has a whole two-phase
      // stability dance for the same reason). Reading it early yielded 0,
      // which made the end bound infinite — measured: the sweep covered the
      // full 44-minute episode, then sat at EOF until the 90s stall watchdog
      // failed it, discarding a completed sweep as an error.
      int endMs = req.endAt?.inMilliseconds ?? 0;

      // Far enough back that the first poll emits immediately.
      var lastEmitMs = startMs - (1 << 20);
      var lastPos = -1;
      var stalledSince = Stopwatch()..start();

      while (!isCancelled()) {
        await Future<void>.delayed(Duration(milliseconds: pollMs));
        if (isCancelled()) return;

        final pos = player.state.position.inMilliseconds;

        // mpv's own end-of-media signal, checked before the watchdog: at EOF
        // the clock stops, which is indistinguishable from a stall.
        if (player.state.completed) break;

        if (endMs == 0) {
          final d = player.state.duration.inMilliseconds;
          if (d > 0) endMs = d - 2000;
        }

        // Stall watchdog, 90s to match the mdk sweeper: a production CDN dip
        // can outlive 30s and then recover, and this is background work.
        if (pos != lastPos) {
          lastPos = pos;
          stalledSince = Stopwatch()..start();
        } else if (stalledSince.elapsed > const Duration(seconds: 90)) {
          throw TimeoutException('sweep stalled at ${pos}ms');
        }

        if (pos - lastEmitMs >=
            req.intervalAt(pos, endMs > 0 ? endMs : 0).inMilliseconds) {
          final png = await player
              .screenshot(format: 'image/png')
              .timeout(const Duration(seconds: 5), onTimeout: () => null);
          if (isCancelled()) return;
          if (png != null && png.isNotEmpty) {
            lastEmitMs = pos;
            ctrl.add(
              SweptFrame.encoded(
                position: Duration(milliseconds: pos),
                bytes: png,
              ),
            );
          }
        }

        if (endMs > 0 && pos >= endMs) break;
      }
    } catch (e, st) {
      if (!ctrl.isClosed) ctrl.addError(e, st);
    } finally {
      try {
        await player.dispose();
      } catch (_) {
        // A leaked mpv instance beats taking the app down on teardown.
      }
      if (!ctrl.isClosed) await ctrl.close();
    }
  }

  /// mpv properties for a background sweep. Best-effort: a property the build
  /// does not know must not fail the whole sweep.
  Future<void> _applySweepProperties(Player player) async {
    final dynamic np = player.platform;
    Future<void> set(String k, String v) async {
      try {
        await np.setProperty(k, v);
      } catch (e) {
        debugPrint('[MediaKitFrameSweeper] setProperty($k=$v) failed: $e');
      }
    }

    // Wide read-ahead, same intent as mdk's setBufferRange(max: 60s) — that
    // single change took the mdk sweep from 9.2x to 14.2x.
    await set('cache', 'yes');
    await set('cache-secs', '60');
    await set('demuxer-readahead-secs', '60');
    // Cheapest variant if a master URL ever reaches here (see class doc).
    await set('hls-bitrate', 'min');
    // Thumbnails are 160x90; decoding above that is wasted work.
    await set('scale', 'bilinear');
    await set('vd-lavc-fast', 'yes');
    await set('vd-lavc-skiploopfilter', 'all');
  }
}
