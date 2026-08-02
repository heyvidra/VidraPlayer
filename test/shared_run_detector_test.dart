// The detector decides whether to skip content the user paid attention to,
// so these tests weight one way: a missed intro is a shrug (set it by hand),
// a fabricated one silently eats a scene.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vidra_player/managers/shared_run_detector.dart';
import 'package:vidra_player/utils/perceptual_hash.dart';

/// Tiles 10s apart carrying the given hashes.
List<HashedTile> tiles(List<int> hashes, {int startSec = 0}) => [
  for (var i = 0; i < hashes.length; i++)
    (seconds: startSec + i * 10, hash: hashes[i]),
];

/// Distinct, stable pseudo-hashes. Not random: a failing case must be
/// reproducible.
int h(int seed) {
  var x = seed * 0x9E3779B97F4A7C15;
  x ^= x >>> 31;
  x *= 0xBF58476D1CE4E5B9;
  x ^= x >>> 27;
  return x;
}

/// [original] with [bits] low bits flipped — a frame that survived a second
/// encode, not a different frame.
int noisy(int original, int bits) {
  var v = original;
  for (var i = 0; i < bits; i++) {
    v ^= 1 << (i * 7 % 64);
  }
  return v;
}

void main() {
  group('dHash', () {
    test('a flat frame hashes to zero, a gradient does not', () {
      final flat = Uint8List(16 * 16 * 4)..fillRange(0, 16 * 16 * 4, 128);
      expect(dHash(flat, 16, 16), 0);

      final gradient = Uint8List(16 * 16 * 4);
      for (var y = 0; y < 16; y++) {
        for (var x = 0; x < 16; x++) {
          final i = (y * 16 + x) * 4;
          gradient[i] = gradient[i + 1] = gradient[i + 2] = x * 16;
          gradient[i + 3] = 255;
        }
      }
      expect(dHash(gradient, 16, 16), isNot(0));
    });

    test('frames smaller than the 9x8 grid are refused, not guessed', () {
      expect(dHash(Uint8List(4 * 4 * 4), 4, 4), 0);
    });

    test('hamming distance counts every bit including the sign bit', () {
      expect(hammingDistance(0, 0), 0);
      expect(hammingDistance(0, 1), 1);
      expect(hammingDistance(0, -1), 64); // all ones
      expect(hammingDistance(-1, -1), 0);
    });
  });

  group('intro detection', () {
    test('finds the shared opening and reports where it ends in each', () {
      // Six shared intro tiles (0-50s), then divergent content.
      final intro = [h(1), h(2), h(3), h(4), h(5), h(6)];
      final a = tiles([...intro, h(100), h(101), h(102)]);
      final b = tiles([...intro, h(200), h(201), h(202)]);

      final run = SharedRunDetector.detectIntro(a, b);
      expect(run, isNotNull);
      expect(run!.tiles, 6);
      expect(run.aSeconds, 50); // last intro tile
      expect(run.bSeconds, 50);
    });

    test('absorbs a cold open of differing length via the offset search', () {
      final intro = [h(1), h(2), h(3), h(4), h(5), h(6)];
      // A opens straight on the intro; B has 2 tiles of cold open first.
      final a = tiles([...intro, h(100), h(101)]);
      final b = tiles([h(300), h(301), ...intro, h(200), h(201)]);

      final run = SharedRunDetector.detectIntro(a, b);
      expect(run, isNotNull);
      expect(run!.tiles, 6);
      expect(run.aSeconds, 50); // A's intro ends at 50s
      expect(run.bSeconds, 70); // B's ends two tiles later
    });

    test('tolerates re-encode noise but not a different scene', () {
      final intro = [h(1), h(2), h(3), h(4), h(5), h(6)];
      final a = tiles(intro);
      final b = tiles([for (final x in intro) noisy(x, 4)]);
      expect(SharedRunDetector.detectIntro(a, b), isNotNull);

      final different = tiles([h(9), h(10), h(11), h(12), h(13), h(14)]);
      expect(SharedRunDetector.detectIntro(a, different), isNull);
    });

    test('a long-but-sparse match is rejected; matches must be numerous', () {
      // Two matching tiles 60s apart clear any duration bar while proving
      // nothing — coincidence, not a sequence. The match-count rule is the
      // real discriminator, which is what lets the per-frame threshold sit
      // close to the noise floor.
      final a = tiles([h(1), h(50), h(51), h(52), h(53), h(54), h(7)]);
      final b = tiles([h(1), h(60), h(61), h(62), h(63), h(64), h(7)]);
      expect(SharedRunDetector.detectIntro(a, b), isNull);
    });

    test('a run survives an isolated non-matching frame', () {
      // Measured on real footage: one noisy frame inside a shared title
      // sequence ended an all-or-nothing run, splitting it into useless
      // pieces of 1-2 tiles.
      final shared = [h(1), h(2), h(3), h(4), h(5), h(6), h(7)];
      final a = tiles(shared);
      final b = tiles([...shared]..[3] = h(999)); // one frame differs
      expect(SharedRunDetector.detectIntro(a, b), isNotNull);
      // With no gap tolerance the same data yields nothing usable.
      expect(SharedRunDetector.detectIntro(a, b, maxGap: 0), isNull);
    });

    test('a run shorter than the minimum is rejected as coincidence', () {
      // Two matching tiles spanning 10s: short in both senses — under the
      // 14s duration floor AND under the 5-match count.
      final a = tiles([h(1), h(2), h(100), h(101), h(102)]);
      final b = tiles([h(1), h(2), h(200), h(201), h(202)]);
      expect(SharedRunDetector.detectIntro(a, b), isNull);

      // Same data, both bars lowered: now accepted. Proves the rejection
      // above came from the rules, not from a failure to match at all.
      expect(
        SharedRunDetector.detectIntro(
          a,
          b,
          minRun: const Duration(seconds: 5),
          minMatches: 2,
        ),
        isNotNull,
      );
    });

    test('a match beyond the search window is not an intro', () {
      final shared = [h(1), h(2), h(3), h(4), h(5), h(6)];
      final filler = [for (var i = 0; i < 30; i++) h(500 + i)];
      final a = tiles([...filler, ...shared]);
      final b = tiles([...filler.reversed, ...shared]);
      // The shared run sits ~5 minutes in; the default window is 4.
      expect(SharedRunDetector.detectIntro(a, b), isNull);
    });

    test('thresholds are seconds, not tile counts', () {
      // The head is swept at 2s to give cross-episode matching a chance, so a
      // run of N tiles there is worth a fifth of the same run at 10s. Before
      // this was time-based, 10 dense tiles (18 seconds) passed a "3 tile"
      // bar meant to represent 30 seconds.
      List<HashedTile> dense(List<int> hashes) => [
        for (var i = 0; i < hashes.length; i++)
          (seconds: i * 2, hash: hashes[i]),
      ];
      final shared = [h(1), h(2), h(3), h(4), h(5)]; // 5 tiles = 8 seconds
      final a = dense([...shared, h(100), h(101)]);
      final b = dense([...shared, h(200), h(201)]);

      // 8 seconds is under the 14s floor: rejected despite 5 matching tiles.
      expect(SharedRunDetector.detectIntro(a, b), isNull);

      // The same 5 tiles at 10s spacing span 40 seconds and are accepted —
      // proving the rejection above measured time, not count.
      expect(
        SharedRunDetector.detectIntro(
          tiles([...shared, h(100)]),
          tiles([...shared, h(200)]),
        ),
        isNotNull,
      );
    });

    test('empty input yields nothing rather than throwing', () {
      expect(SharedRunDetector.detectIntro([], tiles([h(1)])), isNull);
      expect(SharedRunDetector.detectIntro(tiles([h(1)]), []), isNull);
    });
  });

  group('outro detection', () {
    test('finds the shared ending and reports where it starts in each', () {
      final credits = [h(70), h(71), h(72), h(73), h(74), h(75)];
      // Episodes of DIFFERENT length: the run must be found from the end.
      final a = tiles([h(1), h(2), h(3), ...credits]);
      final b = tiles([h(9), h(8), h(7), h(6), h(5), ...credits]);

      final run = SharedRunDetector.detectOutro(a, b);
      expect(run, isNotNull);
      expect(run!.tiles, 6);
      expect(run.aSeconds, 30); // A's credits start at 30s
      expect(run.bSeconds, 50); // B is two tiles longer
    });

    test('divergent endings yield nothing', () {
      final a = tiles([h(1), h(2), h(3), h(4), h(5), h(6)]);
      final b = tiles([h(6), h(7), h(8), h(9), h(10), h(11)]);
      expect(SharedRunDetector.detectOutro(a, b), isNull);
    });

    test('the miss diagnostic reports the tail, not the head', () {
      // Measured need: a run that found an intro but no outro logged a bare
      // "outro=null", which reads the same whether the credits are absent or
      // the bar was too tight. The tail diagnostic must look at the tail —
      // delegating to the head version without rebasing would compile and
      // silently report the wrong end.
      // Long enough that the credits fall OUTSIDE the 4-minute head window —
      // on short inputs both windows cover the whole episode and the two
      // diagnostics agree no matter which end they read.
      final credits = [h(70), h(71), h(72), h(73), h(74), h(75)];
      final a = tiles([for (var i = 0; i < 30; i++) h(500 + i), ...credits]);
      final b = tiles([for (var i = 0; i < 35; i++) h(800 + i), ...credits]);

      expect(SharedRunDetector.describeOutroMiss(a, b).bestRunTiles, 6);
      // The same episodes read from the head: nothing but divergent filler.
      expect(SharedRunDetector.describeIntroMiss(a, b).bestRunTiles, 0);
    });
  });
}
