import 'dart:typed_data';

/// Difference hash (dHash) of an RGBA frame: 64 bits describing where the
/// image gets brighter left-to-right.
///
/// Chosen over a DCT-based pHash because the job is "is this the same shot",
/// not "is this the same picture after re-encoding". dHash is a few dozen
/// comparisons per frame, survives the scaling and codec noise between two
/// encodes of one intro, and needs no float math.
///
/// [rgba] must be `width * height * 4` bytes.
int dHash(Uint8List rgba, int width, int height) {
  if (width < 9 || height < 8) return 0;

  // Point-sample a 9x8 grey grid. Box-averaging would be more faithful, but
  // an intro's frames differ from each other far more than sampling noise
  // differs, so the extra work buys nothing here.
  final grey = Uint8List(9 * 8);
  for (var y = 0; y < 8; y++) {
    final sy = (y * height) ~/ 8;
    for (var x = 0; x < 9; x++) {
      final sx = (x * width) ~/ 9;
      final i = (sy * width + sx) * 4;
      grey[y * 9 + x] =
          (rgba[i] * 299 + rgba[i + 1] * 587 + rgba[i + 2] * 114) ~/ 1000;
    }
  }

  var hash = 0;
  var bit = 0;
  for (var y = 0; y < 8; y++) {
    for (var x = 0; x < 8; x++) {
      if (grey[y * 9 + x] < grey[y * 9 + x + 1]) {
        hash |= 1 << bit;
      }
      bit++;
    }
  }
  return hash;
}

/// Number of differing bits between two [dHash] values, 0..64.
int hammingDistance(int a, int b) {
  var v = a ^ b;
  var count = 0;
  // Dart ints are 64-bit two's complement on native; `v != 0` terminates
  // correctly for the sign bit because the shift below is logical.
  while (v != 0) {
    count += v & 1;
    v = v >>> 1;
  }
  return count;
}

/// Whether two frames are the same shot. 10/64 bits is the usual dHash
/// "same image" line; frames from one intro re-encoded twice sit well under
/// it, while different scenes sit well above.
bool framesMatch(int a, int b, {int threshold = 10}) =>
    hammingDistance(a, b) <= threshold;
