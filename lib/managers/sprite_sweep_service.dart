import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../core/interfaces/frame_sweeper.dart';
import '../core/model/model.dart';
import '../utils/log.dart';
import '../utils/perceptual_hash.dart';
import 'shared_run_detector.dart';

/// Session cache of sprite thumbnails, filled by a background [FrameSweeper].
///
/// One sweep per episode, keyed by episode index; tiles are PNG-encoded at
/// storage time because that is the shape the preview UI consumes
/// (`Image.memory`), and raw RGBA at 15MB+ per episode has no second reader.
///
/// TILES are session-scoped and stay that way: an episode the user reaches is
/// swept within minutes anyway, so persisting ~2MB of PNG per episode would buy
/// a quota policy and a stale-art problem for something already free. The
/// HASHES are exportable ([exportHashes]) because they are what cross-episode
/// detection needs a partner for, and at ~4KB per episode they cost nothing —
/// see `EpisodeHashStore`.
///
/// This is an internal implementation class. SDK users should interact with
/// [PlayerController] instead.
class SpriteSweepService {
  SpriteSweepService({
    required FrameSweeper Function() createSweeper,
    this.onHashesReady,
  }) : _createSweeper = createSweeper;

  final FrameSweeper Function() _createSweeper;

  /// Called with the episode index when its hashes are worth acting on: once
  /// as soon as the head window is covered, and again when the sweep finishes.
  ///
  /// NOT just at completion. Detection compares the head, which a 16x sweep
  /// covers in ~15 seconds, while the sweep itself runs ~5 minutes to reach
  /// the end of a 44-minute episode — and any episode switch cancels it.
  /// Measured on device: ordinary episode browsing cancelled three sweeps in a
  /// row, so nothing was ever persisted and no marker ever appeared, despite
  /// enough of every one of them having been gathered within seconds.
  ///
  /// The controller uses this to persist hashes and run cross-episode
  /// detection, which this class deliberately does not do itself — it owns
  /// frames, not markers. Callers must tolerate being called twice per sweep.
  final void Function(int episodeIndex)? onHashesReady;

  /// episodeIndex -> (content-second -> encoded PNG tile)
  final Map<int, SplayTreeMap<int, Uint8List>> _tiles = {};

  /// episodeIndex -> (content-second -> perceptual hash). Kept beside the
  /// tiles rather than derived on demand: hashing needs the decoded pixels,
  /// which exist exactly once, while the frame is being stored.
  final Map<int, SplayTreeMap<int, int>> _hashes = {};

  /// Episodes with a sweep finished or in flight — the "don't start twice"
  /// set. A failed sweep is removed so a later trigger can retry.
  final Set<int> _sweptOrSweeping = {};

  /// Episodes already reported via [onHashesReady] for having their head
  /// window covered, so the interim report fires once per episode rather than
  /// on every frame past the boundary.
  final Set<int> _headReported = {};

  /// Episodes whose sweep actually reached the end of the media.
  ///
  /// Tail-based detection is meaningful ONLY for these. `detectOutro` measures
  /// backwards from the LAST TILE, so on a half-swept episode it silently
  /// treats wherever the sweep happened to stop as the end of the episode and
  /// answers with confidence. Measured on device: a mid-sweep episode was
  /// compared against a fully-swept one and produced `outro=23s`, which was
  /// persisted as a detected marker — auto-skip would have cut 44 minutes of
  /// content 23 seconds in.
  final Set<int> _completed = {};

  /// Whether [episodeIndex]'s hashes run to the end of its media. False for a
  /// sweep still in flight, one that failed part-way, and one restored from
  /// storage that was itself partial.
  bool isComplete(int episodeIndex) => _completed.contains(episodeIndex);

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

  /// The interval tiles were requested at; lookups tolerate one of them.
  static const interval = Duration(seconds: 10);

  /// Spacing inside the head and tail windows. Cross-episode detection
  /// compares FRAMES, so both episodes must be sampled densely enough that
  /// some pair lands on the same instant of a shared intro — a 10s grid
  /// cannot do that for intros starting a few seconds apart. Two seconds
  /// costs ~120 extra hashes per window (8 bytes each) and the tiles are
  /// stored anyway.
  static const fineInterval = Duration(seconds: 2);
  static const fineRegion = Duration(minutes: 4);

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
              fineInterval: fineInterval,
              fineRegion: fineRegion,
              startAt: resumeFrom,
            ),
          )
          .listen(
            (frame) {
              // Both shapes go through _store: the display bytes and the
              // perceptual hash come from the same decode, and a raw frame's
              // buffer may be reused by the sweeper the moment we return.
              _store(episodeIndex, frame);
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
              // Only here — the stream running to completion is the ONLY
              // evidence the tiles reach the end of the media. See [_completed].
              _completed.add(episodeIndex);
              _clearFlight();
              onHashesReady?.call(episodeIndex);
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
    if (ep != null) {
      _sweptOrSweeping.remove(ep);
      // Say so. A silent cancel reads exactly like a sweep still running, and
      // it cost a 13-minute misdiagnosis: three sweeps had been killed by
      // ordinary episode switching and the log looked identical to one long
      // stall.
      logger.i(
        '[SpriteSweep] ep=$ep cancelled at ${_hashes[ep]?.length ?? 0} hashes'
        '${cooldown == null ? '' : ' (cooldown ${cooldown.inSeconds}s)'}',
      );
    }
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
    // Hashes too, and for the same reason the tiles go: they are keyed by
    // episode index, so surviving a catalog change means comparing episode 3's
    // frames against whatever is at index 3 now — and detection WRITES skip
    // markers from that comparison.
    _hashes.clear();
    _sweptOrSweeping.clear();
    _headReported.clear();
    _completed.clear();
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

  /// Hashed tiles for [episodeIndex], oldest first — the detector's input.
  List<HashedTile> hashedTiles(int episodeIndex) {
    final h = _hashes[episodeIndex];
    if (h == null) return const [];
    return [for (final e in h.entries) (seconds: e.key, hash: e.value)];
  }

  /// Episodes with enough hashed tiles to be worth comparing.
  List<int> episodesWithHashes({int minTiles = 4}) => [
    for (final e in _hashes.entries)
      if (e.value.length >= minTiles) e.key,
  ];

  /// Wire format for [exportHashes]: a version byte, a flags byte, then 12
  /// bytes per tile — uint32 content-second, int64 hash, little-endian.
  ///
  /// Versioned because the blob outlives the code that wrote it, and a
  /// silently misread hash set would place skip markers on footage it never
  /// saw. Bit 0 of the flags byte is [_completedFlag]: whether these tiles run
  /// to the end of the media. Without it a partial set restored from storage
  /// is indistinguishable from a full one, and tail detection would measure
  /// "the end" from wherever a cancelled sweep stopped — see [_completed].
  static const _hashFormatVersion = 2;
  static const _hashHeaderBytes = 2;
  static const _hashRecordBytes = 12;
  static const _completedFlag = 1;

  /// [episodeIndex]'s hashes as a storable blob, or null when it has none.
  Uint8List? exportHashes(int episodeIndex) {
    final hashes = _hashes[episodeIndex];
    if (hashes == null || hashes.isEmpty) return null;
    final out = ByteData(_hashHeaderBytes + hashes.length * _hashRecordBytes);
    out.setUint8(0, _hashFormatVersion);
    out.setUint8(1, _completed.contains(episodeIndex) ? _completedFlag : 0);
    var offset = _hashHeaderBytes;
    for (final e in hashes.entries) {
      out.setUint32(offset, e.key, Endian.little);
      out.setInt64(offset + 4, e.value, Endian.little);
      offset += _hashRecordBytes;
    }
    return out.buffer.asUint8List();
  }

  /// Restore hashes previously produced by [exportHashes].
  ///
  /// Hashes ONLY: [covers] stays false, so the episode is still swept normally
  /// when the user reaches it and still gets its preview tiles. This exists to
  /// give detection a partner to compare against, not to skip work.
  ///
  /// An unrecognised or truncated blob is dropped, not guessed at.
  void importHashes(int episodeIndex, List<int> bytes) {
    if (_isDisposed || bytes.length < _hashHeaderBytes) return;
    if (bytes[0] != _hashFormatVersion) return;
    if ((bytes.length - _hashHeaderBytes) % _hashRecordBytes != 0) return;
    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    // Absent flag => treated as partial, which is the safe reading: tail
    // detection stays off rather than measuring from a false end.
    if (bytes[1] & _completedFlag != 0) _completed.add(episodeIndex);
    final into = _hashes.putIfAbsent(episodeIndex, SplayTreeMap.new);
    for (
      var o = _hashHeaderBytes;
      o + _hashRecordBytes <= bytes.length;
      o += _hashRecordBytes
    ) {
      into[data.getUint32(o, Endian.little)] = data.getInt64(
        o + 4,
        Endian.little,
      );
    }
  }

  /// Decode once, keep both products: the bytes the preview displays and the
  /// hash detection compares.
  Future<void> _store(int episodeIndex, SweptFrame frame) async {
    try {
      final ui.Image image;
      if (frame.isEncoded) {
        final codec = await ui.instantiateImageCodec(frame.bytes);
        image = (await codec.getNextFrame()).image;
      } else {
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
        image = await completer.future;
      }

      final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final displayBytes = frame.isEncoded
          ? frame.bytes
          : (await image.toByteData(
              format: ui.ImageByteFormat.png,
            ))?.buffer.asUint8List();
      final hash = rgba == null
          ? 0
          : dHash(rgba.buffer.asUint8List(), image.width, image.height);
      image.dispose();

      if (_isDisposed || displayBytes == null) return;
      final second = frame.position.inSeconds;
      _tiles.putIfAbsent(episodeIndex, SplayTreeMap.new)[second] = displayBytes;
      if (hash != 0) {
        _hashes.putIfAbsent(episodeIndex, SplayTreeMap.new)[second] = hash;
      }

      // Past the densely-sampled head means detection has everything it can
      // use from this end. Report now rather than at end of sweep — see
      // [onHashesReady] for why waiting loses the work entirely.
      if (hash != 0 &&
          second > fineRegion.inSeconds &&
          _headReported.add(episodeIndex)) {
        onHashesReady?.call(episodeIndex);
      }
    } catch (e) {
      logger.w('[SpriteSweep] frame store failed: $e');
    }
  }

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _flightId++;
    _sub?.cancel();
    _clearFlight();
    _tiles.clear();
    _hashes.clear();
    _sweptOrSweeping.clear();
    _headReported.clear();
    _completed.clear();
    _failures.clear();
  }
}
