// Right-click intro/outro markers: x on the bar -> the two skip values.
// skipIntro counts from the start, skipOutro from the END, so they must always
// sum to the media length — get that backwards and the outro skip fires at the
// wrong time (or immediately).

import 'package:flutter_test/flutter_test.dart';
import 'package:vidra_player/ui/controls/progress_bar.dart';

void main() {
  // 200px wide bar, 12px padding either side -> 176px of track, 10 min media.
  ({int intro, int outro})? at(double dx) => markerSecondsAt(
    localDx: dx,
    width: 200,
    padding: 12,
    maxDurationMs: 600000,
  );

  test('maps x to intro seconds, outro is the remainder', () {
    expect(at(12), (intro: 0, outro: 600));
    expect(at(100), (intro: 300, outro: 300));
    expect(at(188), (intro: 600, outro: 0));
  });

  test('clamps clicks in the padding to the track ends', () {
    expect(at(0), (intro: 0, outro: 600));
    expect(at(200), (intro: 600, outro: 0));
  });

  test('returns null when the bar has no usable width or duration', () {
    expect(
      markerSecondsAt(
        localDx: 10,
        width: 20,
        padding: 12,
        maxDurationMs: 600000,
      ),
      isNull,
    );
    expect(
      markerSecondsAt(localDx: 10, width: 200, padding: 12, maxDurationMs: 0),
      isNull,
    );
  });
}
