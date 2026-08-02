import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vidra_player/core/interfaces/frame_sweeper.dart';
import 'package:vidra_player/core/model/model.dart';
import 'package:vidra_player/managers/sprite_sweep_service.dart';
import 'package:vidra_player/managers/thumbnail_manager.dart';

/// Hand-controlled sweeper: the test decides what frames arrive and when.
class FakeSweeper implements FrameSweeper {
  final requests = <SweepRequest>[];
  final _ctrl = StreamController<SweptFrame>();
  var cancelled = false;

  @override
  Stream<SweptFrame> sweep(SweepRequest request) {
    requests.add(request);
    _ctrl.onCancel = () => cancelled = true;
    return _ctrl.stream;
  }

  /// Raw-RGBA frame, the mdk/fvp shape: the service must encode it.
  void emitFrame(int second) {
    // 2x2 opaque red RGBA — tiny but real pixels for the PNG encoder.
    final px = Uint8List.fromList(
      List.filled(4 * 4, 0)
        ..setAll(0, [
          255, 0, 0, 255, //
          255, 0, 0, 255,
          255, 0, 0, 255,
          255, 0, 0, 255,
        ]),
    );
    _ctrl.add(
      SweptFrame.rawRgba(
        position: Duration(seconds: second),
        width: 2,
        height: 2,
        pixels: px,
      ),
    );
  }

  /// Pre-encoded frame, the mpv/media_kit shape: the service must store it
  /// as-is rather than running it back through the encoder.
  void emitEncodedFrame(int second, Uint8List bytes) {
    _ctrl.add(
      SweptFrame.encoded(position: Duration(seconds: second), bytes: bytes),
    );
  }

  Future<void> done() => _ctrl.close();
  void fail(Object error) => _ctrl.addError(error);
}

Future<void> _settle() async {
  // Real (timer) delays, not bare microtask turns: URL resolution and PNG
  // encoding both hop through timer-backed async under the test binding.
  await Future<void>.delayed(const Duration(milliseconds: 20));
  await Future<void>.delayed(const Duration(milliseconds: 20));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SpriteSweepService', () {
    test('stores tiles and lookup serves the nearest within tolerance',
        () async {
      final sweeper = FakeSweeper();
      final service = SpriteSweepService(createSweeper: () => sweeper);
      service.startSweep(episodeIndex: 0, url: 'http://x/low.m3u8');
      await _settle(); // URL resolution is async; the sweeper appears after it

      sweeper.emitFrame(10);
      sweeper.emitFrame(20);
      await _settle();

      expect(service.lookup(0, 11.4), isNotNull); // 1.4s off -> tile@10
      expect(service.lookup(0, 15.0), isNotNull); // equidistant -> a tile
      expect(service.lookup(0, 45.0), isNull); // >interval from anything
      expect(service.lookup(1, 10.0), isNull); // other episode
      service.dispose();
    });

    test('one sweep at a time, and covered episodes never re-sweep', () async {
      final sweepers = <FakeSweeper>[];
      final service = SpriteSweepService(
        createSweeper: () {
          final s = FakeSweeper();
          sweepers.add(s);
          return s;
        },
      );

      service.startSweep(episodeIndex: 0, url: 'u0');
      service.startSweep(episodeIndex: 1, url: 'u1'); // in-flight guard
      await _settle();
      expect(sweepers, hasLength(1));

      sweepers.single.emitFrame(10);
      await _settle();
      await sweepers.single.done();
      await _settle();

      service.startSweep(episodeIndex: 0, url: 'u0'); // covered guard
      expect(sweepers, hasLength(1));

      service.startSweep(episodeIndex: 1, url: 'u1'); // now allowed
      await _settle();
      expect(sweepers, hasLength(2));
      service.dispose();
    });

    test('a failed sweep retries and RESUMES past the last stored tile',
        () async {
      final sweepers = <FakeSweeper>[];
      final service = SpriteSweepService(
        createSweeper: () {
          final s = FakeSweeper();
          sweepers.add(s);
          return s;
        },
      );

      service.startSweep(episodeIndex: 0, url: 'u');
      await _settle();
      expect(sweepers.last.requests.single.startAt, isNull);
      sweepers.last.fail(StateError('open failed'));
      await _settle();

      service.startSweep(episodeIndex: 0, url: 'u');
      await _settle();
      expect(sweepers, hasLength(2), reason: 'empty failure must retry');
      expect(sweepers.last.requests.single.startAt, isNull);

      // 20 minutes of coverage land, then the sweep dies mid-flight —
      // the on-device failure shape (CDN stall past the watchdog).
      sweepers.last.emitFrame(1200);
      await _settle();
      sweepers.last.fail(StateError('mid-sweep stall'));
      await _settle();

      service.startSweep(episodeIndex: 0, url: 'u');
      await _settle();
      expect(sweepers, hasLength(3));
      expect(
        sweepers.last.requests.single.startAt,
        Duration(seconds: 1200 + SpriteSweepService.interval.inSeconds),
        reason: 'the retry opens past the covered range, not from zero',
      );
      // Both halves of the coverage answer lookups.
      expect(service.lookup(0, 1200), isNotNull);
      service.dispose();
    });

    test('cancelSweep stops the stream, keeps tiles, and the episode can '
        'RESUME later', () async {
      final sweepers = <FakeSweeper>[];
      final service = SpriteSweepService(
        createSweeper: () {
          final s = FakeSweeper();
          sweepers.add(s);
          return s;
        },
      );
      service.startSweep(episodeIndex: 0, url: 'u');
      await _settle();
      sweepers.last.emitFrame(10);
      await _settle();

      service.cancelSweep();
      await _settle();
      expect(sweepers.last.cancelled, isTrue);
      expect(service.lookup(0, 10), isNotNull);
      expect(service.isSweeping, isFalse);

      // A cancelled half-covered episode must not be stranded: the next
      // trigger resumes past the last tile instead of being swallowed by
      // the covered-guard.
      service.startSweep(episodeIndex: 0, url: 'u');
      await _settle();
      expect(sweepers, hasLength(2));
      expect(
        sweepers.last.requests.single.startAt,
        Duration(seconds: 10 + SpriteSweepService.interval.inSeconds),
      );
      service.dispose();
    });

    test('cancel + restart across the async resolve gap yields ONE sweeper',
        () async {
      // The verified high-severity race: episode identity cannot tell a
      // cancelled flight's stale continuation from the new flight for the
      // SAME episode — without the flight id, both continuations create
      // sweepers and the first player can never be cancelled again.
      final sweepers = <FakeSweeper>[];
      final service = SpriteSweepService(
        createSweeper: () {
          final s = FakeSweeper();
          sweepers.add(s);
          return s;
        },
      );

      service.startSweep(episodeIndex: 0, url: 'u');
      // Cancel INSIDE the resolve gap — before any sweeper exists.
      service.cancelSweep();
      service.startSweep(episodeIndex: 0, url: 'u');
      await _settle();

      expect(
        sweepers,
        hasLength(1),
        reason: 'the stale continuation must abort; two sweepers means two '
            'concurrent 16x players, the first uncancellable',
      );
      expect(service.isSweeping, isTrue);
      service.cancelSweep();
      expect(sweepers.single.cancelled, isTrue);
      service.dispose();
    });

    test('a source exhausting the retry budget stops being retried', () async {
      final sweepers = <FakeSweeper>[];
      final service = SpriteSweepService(
        createSweeper: () {
          final s = FakeSweeper();
          sweepers.add(s);
          return s;
        },
      );
      for (var attempt = 0; attempt < 5; attempt++) {
        service.startSweep(episodeIndex: 0, url: 'u');
        await _settle();
        if (sweepers.length > attempt) sweepers.last.fail(StateError('x'));
        await _settle();
      }
      expect(
        sweepers,
        hasLength(3),
        reason: 'retry budget is 3 — an un-sweepable source must not burn '
            'bandwidth forever against the video being watched',
      );
      service.dispose();
    });

    test('an engine that pre-encodes stores its bytes verbatim', () async {
      // media_kit's screenshot() already returns PNG; re-encoding it would
      // cost a decode + encode per tile and change the bytes.
      final sweeper = FakeSweeper();
      final service = SpriteSweepService(createSweeper: () => sweeper);
      service.startSweep(episodeIndex: 0, url: 'u');
      await _settle();

      final png = Uint8List.fromList([137, 80, 78, 71, 1, 2, 3]);
      sweeper.emitEncodedFrame(10, png);
      await _settle();

      expect(service.lookup(0, 10), same(png));
      service.dispose();
    });

    test('pickSweepQuality takes the smallest numeric label', () {
      const qs = [
        VideoQuality(label: '1080P', source: VideoSource.network('http://a')),
        VideoQuality(label: '480p', source: VideoSource.network('http://b')),
        VideoQuality(label: '720p', source: VideoSource.network('http://c')),
      ];
      expect(SpriteSweepService.pickSweepQuality(qs)!.label, '480p');
      // "4K" means 4000 columns, not 4: it must never beat 480p.
      const withK = [
        VideoQuality(label: '4K', source: VideoSource.network('http://a')),
        VideoQuality(label: '2K', source: VideoSource.network('http://b')),
        VideoQuality(label: '480p', source: VideoSource.network('http://c')),
      ];
      expect(SpriteSweepService.pickSweepQuality(withK)!.label, '480p');
      // Unparseable labels: fall back to the LAST entry (lists are
      // conventionally best-first).
      const named = [
        VideoQuality(label: '高清', source: VideoSource.network('http://a')),
        VideoQuality(label: '流畅', source: VideoSource.network('http://b')),
      ];
      expect(SpriteSweepService.pickSweepQuality(named)!.label, '流畅');
      expect(SpriteSweepService.pickSweepQuality(const []), isNull);
    });
  });

  group('ThumbnailManager sprite fallback', () {
    test('serves the sprite tile when the native path has nothing', () async {
      // Test host is macOS: the native channel throws (no plugin) -> null ->
      // sprite fallback. Off macOS the sprite is consulted directly.
      final tile = Uint8List.fromList([1, 2, 3]);
      final manager = ThumbnailManager(
        url: 'http://x',
        spriteLookup: (s) => s == 30.0 ? tile : null,
      );
      expect(await manager.getThumbnail(30.0), same(tile));
      expect(await manager.getThumbnail(99.0), isNull);
      manager.dispose();
    });
  });
}
