// Separate file ON PURPOSE: TestWidgetsFlutterBinding mocks HttpClient (every
// request answers 400 without touching the network), so this test must run
// without the widget binding — which is per-file. Keep sprite tests that need
// dart:ui in sprite_sweep_test.dart; keep network-touching ones here.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vidra_player/managers/sprite_sweep_service.dart';

void main() {
  test('resolveVariant chases a master to its lowest-bandwidth variant',
      () async {
    // The production shape that stalled on-device: a quality URL that is
    // itself a (single-variant) master playlist.
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) {
      req.response
        ..headers.contentType = ContentType('application', 'x-mpegURL')
        ..write(
          req.uri.path == '/master.m3u8'
              ? '#EXTM3U\n'
                    '#EXT-X-STREAM-INF:BANDWIDTH=2000000,RESOLUTION=1920x1080\n'
                    'hd/index.m3u8\n'
                    '#EXT-X-STREAM-INF:BANDWIDTH=500000,RESOLUTION=640x360\n'
                    'low/index.m3u8\n'
              : '#EXTM3U\n#EXTINF:6.0,\nseg0.ts\n',
        )
        ..close();
    });
    final base = 'http://127.0.0.1:${server.port}';

    expect(
      await SpriteSweepService.resolveVariantForTest('$base/master.m3u8'),
      '$base/low/index.m3u8',
    );
    // Already a media playlist: unchanged.
    expect(
      await SpriteSweepService.resolveVariantForTest('$base/variant.m3u8'),
      '$base/variant.m3u8',
    );
    // Not HLS at all: unchanged, no fetch.
    expect(
      await SpriteSweepService.resolveVariantForTest('http://x/movie.mp4'),
      'http://x/movie.mp4',
    );
    await server.close(force: true);
  });
}
