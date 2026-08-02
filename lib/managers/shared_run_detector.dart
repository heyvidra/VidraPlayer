import '../utils/perceptual_hash.dart';

/// One swept tile reduced to what detection needs.
typedef HashedTile = ({int seconds, int hash});

/// Where a shared run ends (intro) or starts (outro), per episode.
typedef SharedRun = ({int aSeconds, int bSeconds, int tiles});

/// Why a comparison produced nothing — the difference between "these two
/// episodes share no opening" and "they nearly matched but the bar was set
/// too high". Without it a null result is unactionable.
typedef DetectionMiss = ({int bestDistance, int bestRunTiles});

/// Finds the stretch two episodes of one series have in common at their start
/// (the intro) or at their end (the credits).
///
/// Pure: hashes in, seconds out. Every judgement call is a named parameter
/// with a defended default, because the failure mode that matters is not
/// "missed an intro" — the user can still set one by hand — but "declared an
/// intro that isn't one and skipped real content".
abstract final class SharedRunDetector {
  /// Thresholds are expressed in TIME, not tile counts, because the sweeper
  /// samples the head and tail more densely than the middle — a tile count
  /// means a different number of seconds depending on where you are.
  ///
  /// How far one episode's intro may sit from the other's. Measured on real
  /// episodes of one series: the shared title sequence sat at 2s in one and
  /// 98s in the other, because that one opened with a recap. 40s — the first
  /// guess — put the real answer outside the search entirely.
  static const defaultMaxOffset = Duration(minutes: 3);

  /// How far into an episode an intro may begin. Past this it is content.
  /// Must not exceed the sweeper's fine-sampling window, or a run would try
  /// to extend across a change of spacing.
  static const defaultSearchWindow = Duration(minutes: 4);

  /// A run shorter than this is not worth a skip control even if real.
  ///
  /// A loose sanity floor, NOT the discriminator — [defaultMinMatches] is.
  /// The measured span systematically understates the true sequence, because
  /// matched tiles are interior samples and the run extends up to one sampling
  /// interval past each end. Worse, it JITTERS: the same shared intro of the
  /// same two episodes measured 17s on one sweep (2s..19s) and 11s on the next
  /// (6s..17s), purely from where the sampler happened to land. 20s — the first
  /// guess — rejected it outright, and 14s sat inside the jitter band, so a
  /// genuine intro was found or missed depending on the run.
  static const defaultMinRun = Duration(seconds: 10);

  /// And it must be built from at least this many matching samples. Duration
  /// alone is a weak signal: two coincidental matches 20s apart clear a time
  /// bar, while five consecutive matches at a consistent offset cannot happen
  /// by chance. THIS is the discriminator, which is why the per-frame
  /// threshold below is allowed to sit near the noise floor.
  static const defaultMinMatches = 5;

  /// Per-frame bit distance counted as "same shot".
  ///
  /// Measured on one series: frames of the shared sequence scored 1-11, while
  /// unrelated frames from the same two episodes never went below 13. 12 sits
  /// between them — deliberately close to the noise, because the run
  /// structure, not this number, is what rejects coincidence.
  static const defaultThreshold = 12;

  /// Consecutive non-matching samples tolerated inside a run.
  ///
  /// Without this the measured sequence 11,9,11,4,4,11,9,1 broke into pieces
  /// of length 1-2 at any threshold below 11, because a single noisy frame
  /// ends an all-or-nothing run. Two is enough to bridge a compression
  /// artefact without bridging a scene change.
  static const defaultMaxGap = 2;

  /// The shared opening run, or null when the two episodes have none.
  ///
  /// [aSeconds] / [bSeconds] in the result are where the run ENDS in each
  /// episode — i.e. the intro-end marker for each.
  /// Closest the two openings came, for diagnosis when [detectIntro] returns
  /// null. `bestDistance` near 64 means genuinely unrelated footage; near the
  /// threshold means the bar, not the content, decided.
  static DetectionMiss describeIntroMiss(
    List<HashedTile> a,
    List<HashedTile> b, {
    Duration maxOffset = defaultMaxOffset,
    Duration searchWindow = defaultSearchWindow,
    int threshold = defaultThreshold,
  }) {
    var bestDistance = 64;
    var bestRun = 0;
    final aLimit = _windowLimit(a, searchWindow);
    final bLimit = _windowLimit(b, searchWindow);
    final maxOffsetTiles = _offsetTiles(a, maxOffset);
    for (var offset = -maxOffsetTiles; offset <= maxOffsetTiles; offset++) {
      var run = 0;
      for (var i = 0; i < aLimit; i++) {
        final j = i + offset;
        if (j < 0 || j >= bLimit) continue;
        final d = hammingDistance(a[i].hash, b[j].hash);
        if (d < bestDistance) bestDistance = d;
        if (d <= threshold) {
          run++;
          if (run > bestRun) bestRun = run;
        } else {
          run = 0;
        }
      }
    }
    return (bestDistance: bestDistance, bestRunTiles: bestRun);
  }

  /// The same diagnosis for the tail. Measured need: a run where the intro was
  /// found and the outro was not logged `outro=null`, which reads identically
  /// whether the episodes share no credits or the bar was one bit too tight —
  /// resolving it took an offline probe over dumped hashes.
  static DetectionMiss describeOutroMiss(
    List<HashedTile> a,
    List<HashedTile> b, {
    Duration maxOffset = defaultMaxOffset,
    Duration searchWindow = defaultSearchWindow,
    int threshold = defaultThreshold,
  }) => describeIntroMiss(
    _rebaseFromEnd(a),
    _rebaseFromEnd(b),
    maxOffset: maxOffset,
    searchWindow: searchWindow,
    threshold: threshold,
  );

  static SharedRun? detectIntro(
    List<HashedTile> a,
    List<HashedTile> b, {
    Duration maxOffset = defaultMaxOffset,
    Duration searchWindow = defaultSearchWindow,
    Duration minRun = defaultMinRun,
    int minMatches = defaultMinMatches,
    int threshold = defaultThreshold,
    int maxGap = defaultMaxGap,
  }) {
    final run = _longestRun(
      a,
      b,
      maxOffset: maxOffset,
      searchWindow: searchWindow,
      minRun: minRun,
      minMatches: minMatches,
      threshold: threshold,
      maxGap: maxGap,
    );
    if (run == null) return null;
    // End of the run = end of the intro. The run's last tile still belongs to
    // the intro, so the marker goes at that tile's position.
    return (
      aSeconds: a[run.aStart + run.length - 1].seconds,
      bSeconds: b[run.bStart + run.length - 1].seconds,
      tiles: run.length,
    );
  }

  /// The shared closing run, or null when there is none.
  ///
  /// [aSeconds] / [bSeconds] are where the run STARTS in each episode — the
  /// outro-start marker. Episodes differ in length, so this searches from the
  /// end of each list rather than from a shared origin.
  static SharedRun? detectOutro(
    List<HashedTile> a,
    List<HashedTile> b, {
    Duration maxOffset = defaultMaxOffset,
    Duration searchWindow = defaultSearchWindow,
    Duration minRun = defaultMinRun,
    int minMatches = defaultMinMatches,
    int threshold = defaultThreshold,
    int maxGap = defaultMaxGap,
  }) {
    // Reversed AND re-based: the shared parameters are all in seconds from
    // the searched edge, and for the tail that edge is the end of the media.
    final ra = _rebaseFromEnd(a);
    final rb = _rebaseFromEnd(b);
    final run = _longestRun(
      ra,
      rb,
      maxOffset: maxOffset,
      searchWindow: searchWindow,
      minRun: minRun,
      minMatches: minMatches,
      threshold: threshold,
      maxGap: maxGap,
    );
    if (run == null) return null;
    // Reversed, so the run's LAST tile is the earliest one — where the
    // credits begin. Rebased seconds count BACK from the end, so convert to
    // absolute positions before handing them out as markers.
    return (
      aSeconds: a.last.seconds - ra[run.aStart + run.length - 1].seconds,
      bSeconds: b.last.seconds - rb[run.bStart + run.length - 1].seconds,
      tiles: run.length,
    );
  }

  /// Longest run of matching tiles within [searchWindow] of the start of
  /// both lists, allowing one list to be shifted by up to [maxOffset].
  ///
  /// Pairs by INDEX, which is only meaningful because the sweeper emits on a
  /// regular content-time grid. It did not always: measured on device, a 200ms
  /// poll at 16x playback turned a requested 10s interval into an irregular
  /// 10-14s, and two episodes came out sampled at 0,12,25,38... versus
  /// 0,10,23,36... — index i meant a different instant in each, so no real
  /// intro could ever line up. The sweeper's poll rate is now derived from the
  /// interval; this comment is here so a future change there cannot silently
  /// break detection again.
  ///
  /// Brute force over offsets and start positions: a few hundred 64-bit XORs,
  /// once per episode pair on a background sweep completion.
  static _Run? _longestRun(
    List<HashedTile> a,
    List<HashedTile> b, {
    required Duration maxOffset,
    required Duration searchWindow,
    required Duration minRun,
    required int minMatches,
    required int threshold,
    required int maxGap,
  }) {
    if (a.isEmpty || b.isEmpty) return null;
    final aLimit = _windowLimit(a, searchWindow);
    final bLimit = _windowLimit(b, searchWindow);
    final maxOffsetTiles = _offsetTiles(a, maxOffset);
    final minRunSeconds = minRun.inSeconds;

    _Run? best;
    for (var offset = -maxOffsetTiles; offset <= maxOffsetTiles; offset++) {
      var i = 0;
      while (i < aLimit) {
        final j = i + offset;
        if (j < 0 || j >= bLimit) {
          i++;
          continue;
        }
        if (!framesMatch(a[i].hash, b[j].hash, threshold: threshold)) {
          i++;
          continue;
        }
        // Extend, tolerating up to [maxGap] consecutive misses: a single
        // noisy frame must not end a real sequence (measured — it did).
        var length = 0;
        var matches = 0;
        var gap = 0;
        var lastMatch = 0;
        while (i + length < aLimit && j + length < bLimit) {
          if (framesMatch(
            a[i + length].hash,
            b[j + length].hash,
            threshold: threshold,
          )) {
            matches++;
            gap = 0;
            lastMatch = length;
          } else if (++gap > maxGap) {
            break;
          }
          length++;
        }
        // Trim the trailing gap so the reported end is a real match.
        length = lastMatch + 1;

        // Span in SECONDS (a tile count means different durations in the
        // densely sampled head than in the middle) AND a minimum number of
        // actual matches — the run structure is what rules out coincidence.
        final spanSeconds = a[i + length - 1].seconds - a[i].seconds;
        if (spanSeconds >= minRunSeconds &&
            matches >= minMatches &&
            (best == null || matches > best.matches)) {
          best = _Run(aStart: i, bStart: j, length: length, matches: matches);
        }
        i += length;
      }
    }
    return best;
  }
}

/// Index one past the last tile within [window] of the list's first tile.
int _windowLimit(List<HashedTile> tiles, Duration window) {
  final cutoff = tiles.first.seconds + window.inSeconds;
  var i = 0;
  while (i < tiles.length && tiles[i].seconds <= cutoff) {
    i++;
  }
  return i;
}

/// [offset] converted to a tile count using the list's actual head spacing,
/// so the search covers the same amount of TIME whatever the sample density.
int _offsetTiles(List<HashedTile> tiles, Duration offset) {
  if (tiles.length < 2) return 0;
  final step = tiles[1].seconds - tiles[0].seconds;
  if (step <= 0) return 0;
  final n = offset.inSeconds ~/ step;
  // The ceiling exists only to bound work, so it must not be tighter than
  // the offsets that actually occur: at 2s head sampling a 96s offset — one
  // measured on real episodes — is 48 tiles, and a 40-tile cap hid it. The
  // search is a few tens of thousands of 64-bit XORs at this size.
  return n < 1 ? 1 : (n > 200 ? 200 : n);
}

/// Tiles reversed, with `seconds` re-expressed as distance from the END, so
/// the tail can be searched with the same from-the-edge logic as the head.
List<HashedTile> _rebaseFromEnd(List<HashedTile> tiles) {
  if (tiles.isEmpty) return const [];
  final last = tiles.last.seconds;
  return [
    for (final t in tiles.reversed) (seconds: last - t.seconds, hash: t.hash),
  ];
}

class _Run {
  const _Run({
    required this.aStart,
    required this.bStart,
    required this.length,
    required this.matches,
  });
  final int aStart;
  final int bStart;

  /// Tiles spanned, gaps included.
  final int length;

  /// Tiles that actually matched — the confidence signal.
  final int matches;
}
