// Chapter parsing is pure text -> markers, so it's tested without any network.
// The load-bearing bits: START-DATE is wall-clock and only means anything
// relative to PROGRAM-DATE-TIME, and an unlabelled chapter list must yield
// nothing rather than a guess.

import 'package:flutter_test/flutter_test.dart';
import 'package:vidra_player/core/model/episode_markers.dart';
import 'package:vidra_player/utils/chapter_probe.dart';

const _playlist = '''
#EXTM3U
#EXT-X-VERSION:6
#EXT-X-TARGETDURATION:6
#EXT-X-PROGRAM-DATE-TIME:2026-01-01T00:00:00.000Z
#EXT-X-DATERANGE:ID="ch0",CLASS="com.apple.hls.chapter",START-DATE="2026-01-01T00:00:00.000Z",X-TITLE="Recap"
#EXT-X-DATERANGE:ID="ch1",CLASS="com.apple.hls.chapter",START-DATE="2026-01-01T00:00:30.000Z",X-TITLE="Opening"
#EXT-X-DATERANGE:ID="ch2",CLASS="com.apple.hls.chapter",START-DATE="2026-01-01T00:02:00.000Z",X-TITLE="Episode"
#EXT-X-DATERANGE:ID="ch3",CLASS="com.apple.hls.chapter",START-DATE="2026-01-01T00:22:00.000Z",X-TITLE="Ending"
#EXTINF:6.0,
seg0.ts
''';

void main() {
  test('resolves START-DATE against PROGRAM-DATE-TIME', () {
    final chapters = parseHlsChapters(_playlist);
    expect(chapters.map((c) => c.title), [
      'Recap',
      'Opening',
      'Episode',
      'Ending',
    ]);
    expect(chapters[1].start, const Duration(seconds: 30));
    expect(chapters[3].start, const Duration(minutes: 22));
  });

  test('intro runs to the NEXT chapter, outro is where credits start', () {
    final markers = markersFromChapters(parseHlsChapters(_playlist), 3);
    expect(markers, isNotNull);
    expect(markers!.episodeIndex, 3);
    expect(markers.introStart, const Duration(seconds: 30));
    expect(markers.introEnd, const Duration(minutes: 2));
    expect(markers.outroStart, const Duration(minutes: 22));
    expect(markers.source, MarkerSource.chapter);
  });

  test('outro tail is measured from the end of the media', () {
    final markers = markersFromChapters(parseHlsChapters(_playlist), 0)!;
    // 24 min media, credits at 22:00 -> 120s of tail.
    expect(markers.outroTailSeconds(const Duration(minutes: 24)), 120);
    // Unknown/zero duration must not produce a bogus tail.
    expect(markers.outroTailSeconds(Duration.zero), 0);
  });

  test('matches Chinese chapter titles', () {
    final markers = markersFromChapters(
      parseHlsChapters(
        _playlist
            .replaceAll('X-TITLE="Opening"', 'X-TITLE="片头"')
            .replaceAll('X-TITLE="Ending"', 'X-TITLE="片尾"'),
      ),
      0,
    );
    expect(markers!.introEnd, const Duration(minutes: 2));
    expect(markers.outroStart, const Duration(minutes: 22));
  });

  test('unlabelled chapters yield no markers, not a guess', () {
    final markers = markersFromChapters(
      parseHlsChapters(
        _playlist
            .replaceAll('X-TITLE="Opening"', 'X-TITLE="Chapter 1"')
            .replaceAll('X-TITLE="Ending"', 'X-TITLE="Chapter 3"'),
      ),
      0,
    );
    expect(markers, isNull);
  });

  test('dateranges without a PROGRAM-DATE-TIME anchor are unusable', () {
    final noAnchor = _playlist
        .split('\n')
        .where((l) => !l.startsWith('#EXT-X-PROGRAM-DATE-TIME'))
        .join('\n');
    expect(parseHlsChapters(noAnchor), isEmpty);
  });

  test('a plain playlist parses to nothing', () {
    expect(parseHlsChapters('#EXTM3U\n#EXTINF:6.0,\nseg0.ts\n'), isEmpty);
  });

  test('non-HLS urls are never fetched', () async {
    // No network: an mp4 would mean downloading the whole file, so the probe
    // must bail on the extension before opening a socket.
    expect(
      await probeChapters('https://example.com/movie.mp4', 0),
      isNull,
    );
  });
}
