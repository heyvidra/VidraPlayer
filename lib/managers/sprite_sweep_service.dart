import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../core/interfaces/frame_sweeper.dart';
import '../core/model/model.dart';
import '../utils/log.dart';

/// Session cache of sprite thumbnails, filled by a background [FrameSweeper].
///
/// One sweep per episode, keyed by episode index; tiles are PNG-encoded at
/// storage time because that is the shape the preview UI consumes
/// (`Image.memory`), and raw RGBA at 15MB+ per episode has no second reader.
/// Session-scoped on purpose: persistence is a later phase, and a cache that
/// dies with the controller can never serve stale art for re-encoded media.
///
/// This is an internal implementation class. SDK users should interact with
/// [PlayerController] instead.
class SpriteSweepService {
  SpriteSweepService({required FrameSweeper Function() createSweeper})
    : _createSweeper = createSweeper;

  final FrameSweeper Function() _createSweeper;

  /// episodeIndex -> (content-second -> encoded PNG tile)
  final Map<int, SplayTreeMap<int, Uint8List>> _tiles = {};

  /// Episodes with a sweep finished or in flight — the "don't start twice"
  /// set. A failed sweep is removed so a later trigger can retry.
  final Set<int> _sweptOrSweeping = {};

  /// Failed attempts per episode. The stable-playback trigger fires on every
  /// position tick, so without a cap an un-sweepable source retries forever —
  /// a stall-watchdog cycle each time — burning bandwidth against the video
  /// the user is watching. Retries RESUME from the last stored tile, so each
  /// attempt extends coverage instead of re-burning it; 3 attempts means up
  /// to three stall recoveries across one episode.
  final Map<int, int> _failures = {};
  static const _maxAttempts = 3;

  StreamSubscription<SweptFrame>? _sub;
  int? _sweepingEpisode;
  bool _isDisposed = false;

  /// Monotonic flight identity. The async URL-resolution gap means a flight
  /// can be cancelled and a NEW flight for the SAME episode started before
  /// the old continuation runs — episode identity cannot tell them apart
  /// (verified interleaving: two concurrent 16x players, the second
  /// overwriting the first's subscription so it could never be cancelled).
  /// Every continuation and stream handler checks its captured id first.
  int _flightId = 0;

  /// The interval tiles were requested at; lookups tolerate half of it.
  static const interval = Duration(seconds: 10);

  /// True from startSweep until done/failed/cancelled — including the
  /// master-resolution step before the sweeper stream exists.
  bool get isSweeping => _sub != null || _sweepingEpisode != null;

  /// Whether [episodeIndex] already has tiles or a sweep in flight.
  bool covers(int episodeIndex) => _sweptOrSweeping.contains(episodeIndex);

  /// Nearest tile to [seconds] for [episodeIndex], or null when the nearest
  /// one is more than one interval away (serving a frame from 30s away reads
  /// as a wrong preview, not a helpful one).
  Uint8List? lookup(int episodeIndex, double seconds) {
    final tiles = _tiles[episodeIndex];
    if (tiles == null || tiles.isEmpty) return null;
    final key = seconds.round();
    final below = tiles.lastKeyBefore(key + 1);
    final above = tiles.firstKeyAfter(key);
    int? best;
    if (below != null) best = below;
    if (above != null &&
        (best == null || (above - key).abs() < (key - best).abs())) {
      best = above;
    }
    if (best == null || (best - key).abs() > interval.inSeconds) return null;
    return tiles[best];
  }

  /// Start sweeping [url] for [episodeIndex]. No-op when already covered,
  /// already sweeping something, out of retry budget, or disposed. One sweep
  /// at a time — this shares bandwidth with the video the user is watching.
  void startSweep({required int episodeIndex, required String url}) {
    // isSweeping, not _sub: the flight exists from here on, but the stream
    // only after async URL resolution — a second start landing in that gap
    // would clobber the first flight's _sweepingEpisode and orphan it.
    if (_isDisposed || isSweeping || covers(episodeIndex)) return;
    if ((_failures[episodeIndex] ?? 0) >= _maxAttempts) return;
    final pausedUntil = _pausedUntil;
    if (pausedUntil != null && DateTime.now().isBefore(pausedUntil)) return;

    _sweptOrSweeping.add(episodeIndex);
    _sweepingEpisode = episodeIndex;
    final flight = ++_flightId;
    final store = _tiles.putIfAbsent(episodeIndex, SplayTreeMap.new);

    // Resolve BEFORE handing anything to the engine: production quality URLs
    // are often still master playlists (olevod's per-quality URL is a
    // single-variant master), and a master wedges the sweep's aggressive
    // prefetch — measured on-device as "stalled at 40ms" — exactly the
    // failure the gate probes showed for masters.
    // Resume, don't restart: after a mid-sweep failure the next attempt
    // opens at the last stored tile (open-at-position is cheap and flat,
    // measured 2-5s) and extends coverage from there.
    final resumeFrom = store.isEmpty
        ? null
        : Duration(seconds: store.lastKey()! + interval.inSeconds);

    _resolveVariant(url).then((resolved) {
      // Flight identity, NOT episode identity: cancel + restart for the SAME
      // episode inside this async gap is indistinguishable by episode alone,
      // and the stale continuation would spawn a second concurrent player.
      if (_isDisposed || flight != _flightId) return;

      final FrameSweeper sweeper;
      try {
        // The factory can be cleared between trigger and continuation; that
        // must fail the flight, not escape as an unhandled async error with
        // the bookkeeping stuck mid-flight.
        sweeper = _createSweeper();
      } catch (e) {
        logger.w('[SpriteSweep] sweeper creation failed: $e');
        _failures[episodeIndex] = (_failures[episodeIndex] ?? 0) + 1;
        _sweptOrSweeping.remove(episodeIndex);
        _clearFlight();
        return;
      }
      logger.i(
        '[SpriteSweep] start ep=$episodeIndex from=${resumeFrom?.inSeconds ?? 0}s url=$resolved',
      );
      _sub = sweeper
          .sweep(
            SweepRequest(
              url: resolved,
              interval: interval,
              startAt: resumeFrom,
            ),
          )
          .listen(
            (frame) {
              // Engines that already encode (mpv) store straight through;
              // raw-pixel engines (mdk) encode immediately, because the
              // sweeper may reuse its buffer between emissions.
              if (frame.isEncoded) {
                store[frame.position.inSeconds] = frame.bytes;
                return;
              }
              _encodePng(frame).then((png) {
                if (_isDisposed || png == null) return;
                store[frame.position.inSeconds] = png;
              });
            },
            onError: (Object e) {
              if (flight != _flightId) return; // stale flight, not ours
              logger.w('[SpriteSweep] ep=$episodeIndex failed: $e');
              _failures[episodeIndex] = (_failures[episodeIndex] ?? 0) + 1;
              // Tiles keep; the episode becomes retriable while budget lasts,
              // and the next attempt resumes past the last stored tile.
              _sweptOrSweeping.remove(episodeIndex);
              _clearFlight();
            },
            onDone: () {
              if (flight != _flightId) return; // stale flight, not ours
              logger.i(
                '[SpriteSweep] ep=$episodeIndex done, ${store.length} tiles',
              );
              _clearFlight();
            },
            cancelOnError: true,
          );
    });
  }

  /// Chase an HLS master playlist down to its lowest-bandwidth variant URI.
  /// Non-masters (media playlists, mp4, anything unfetchable) come back
  /// unchanged — the sweep then runs on the original URL and the stall
  /// watchdog is the backstop. Visible for tests only.
  static Future<String> resolveVariantForTest(String url) =>
      _resolveVariant(url);

  static Future<String> _resolveVariant(String url) async {
    if (!url.toLowerCase().contains('.m3u8')) return url;
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
      final uri = Uri.parse(url);
      final req = await client.getUrl(uri);
      final res = await req.close().timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return url;
      final text = await res
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 5));
      if (!text.contains('#EXT-X-STREAM-INF')) return url; // already a variant

      String? best;
      int? bestBw;
      final lines = const LineSplitter().convert(text);
      for (var i = 0; i < lines.length - 1; i++) {
        if (!lines[i].startsWith('#EXT-X-STREAM-INF')) continue;
        final bw = int.tryParse(
          RegExp(r'BANDWIDTH=(\d+)').firstMatch(lines[i])?.group(1) ?? '',
        );
        // The URI is the next non-comment line.
        var j = i + 1;
        while (j < lines.length && lines[j].startsWith('#')) {
          j++;
        }
        if (j >= lines.length || lines[j].trim().isEmpty) continue;
        if (bestBw == null || (bw ?? 1 << 40) < bestBw) {
          bestBw = bw ?? 1 << 40;
          best = lines[j].trim();
        }
      }
      if (best == null) return url;
      return uri.resolve(best).toString();
    } catch (e) {
      logger.w('[SpriteSweep] master resolve failed, sweeping as-is: $e');
      return url;
    } finally {
      client?.close(force: true);
    }
  }

  /// Not before this instant may a new sweep start. Set by cooldown cancels.
  DateTime? _pausedUntil;

  /// Stop the in-flight sweep (if any). Tiles already stored stay, and the
  /// episode becomes eligible again — a later trigger RESUMES past the last
  /// tile, so cancelling never permanently strands a half-covered episode.
  ///
  /// [cooldown] delays the next start. Pass it for network-pressure cancels
  /// (foreground rebuffering): without it a flapping connection produces a
  /// restart storm — measured on a production CDN: four resolve+prepare
  /// cycles in six minutes, one of which burned a retry on a 30s open
  /// timeout. Leave it null for switch/dispose cancels, where the next
  /// trigger is naturally far away.
  void cancelSweep({Duration? cooldown}) {
    // Any continuation or handler of the current flight is stale from here.
    _flightId++;
    final ep = _sweepingEpisode;
    if (ep != null) _sweptOrSweeping.remove(ep);
    if (cooldown != null) {
      _pausedUntil = DateTime.now().add(cooldown);
    }
    _sub?.cancel();
    _clearFlight();
  }

  /// Drop everything. For catalog changes (updateEpisodes): tiles are keyed
  /// by episode INDEX, so a reordered/replaced episode list silently serves
  /// the wrong episode's frames unless the cache dies with the old indices.
  void clear() {
    cancelSweep();
    _tiles.clear();
    _sweptOrSweeping.clear();
    _failures.clear();
  }

  void _clearFlight() {
    _sub = null;
    _sweepingEpisode = null;
  }

  /// Pick the sweep source for an episode: the lowest-looking quality by the
  /// digits in its label ("480p" < "720p" < "1080p"), falling back to the
  /// LAST quality when labels don't parse (source lists are conventionally
  /// best-first). Sweeping the lowest variant is a hard requirement, not an
  /// optimization — see [SweepRequest.url].
  static VideoQuality? pickSweepQuality(List<VideoQuality> qualities) {
    if (qualities.isEmpty) return null;
    VideoQuality? best;
    int? bestNum;
    for (final q in qualities) {
      // "2K"/"4K" mean thousands of columns — read them as 2000/4000, or the
      // naive digit parse ranks 4K (4) below 480p (480) and sweeps the
      // HIGHEST bitrate variant.
      final k = RegExp(r'(\d+)\s*[kK]\b').firstMatch(q.label);
      final d = RegExp(r'\d+').firstMatch(q.label);
      final int? n = k != null
          ? int.parse(k.group(1)!) * 1000
          : (d != null ? int.parse(d.group(0)!) : null);
      if (n == null) continue;
      if (bestNum == null || n < bestNum) {
        bestNum = n;
        best = q;
      }
    }
    return best ?? qualities.last;
  }

  Future<Uint8List?> _encodePng(SweptFrame frame) async {
    try {
      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        frame.bytes,
        frame.width,
        frame.height,
        // mdk's Dart wrapper documents rgba and its native header says bgra;
        // measured with a solid-red stream: first pixel [255,24,0,255] — the
        // wrapper is right, snapshot() hands back RGBA.
        ui.PixelFormat.rgba8888,
        completer.complete,
      );
      final image = await completer.future;
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return data?.buffer.asUint8List();
    } catch (e) {
      logger.w('[SpriteSweep] encode failed: $e');
      return null;
    }
  }

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _flightId++;
    _sub?.cancel();
    _clearFlight();
    _tiles.clear();
    _sweptOrSweeping.clear();
    _failures.clear();
  }
}
