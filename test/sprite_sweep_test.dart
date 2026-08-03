import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

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
      List.filled(4 * 4, 0)..setAll(0, [
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

  /// A frame big enough to actually HASH. dHash needs a 9x8 grid, so the 2x2
  /// frames above hash to 0 and are stored without one — fine for tile tests,
  /// useless for anything touching hashes. The content varies with [second]
  /// so two tiles never collide.
  void emitHashableFrame(int second) {
    const w = 16, h = 16;
    final px = Uint8List(w * h * 4);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = (y * w + x) * 4;
        px[i] = px[i + 1] = px[i + 2] = (x * 16 + second * 7) % 256;
        px[i + 3] = 255;
      }
    }
    _ctrl.add(
      SweptFrame.rawRgba(
        position: Duration(seconds: second),
        width: w,
        height: h,
        pixels: px,
      ),
    );
  }

  /// Pre-encoded frame, the mpv/media_kit shape: the service must store it
  /// as-is rather than running it back through the encoder.
  void emitEncodedFrame(int second, Uint8List bytes) {
    _ctrl.add(
      SweptFrame.encoded(
        position: Duration(seconds: second),
        bytes: bytes,
      ),
    );
  }

  Future<void> done() => _ctrl.close();
  void fail(Object error) => _ctrl.addError(error);
}

/// A genuinely decodable PNG, built through dart:ui so the bytes are whatever
/// this platform's encoder produces rather than a hand-rolled constant.
Future<Uint8List> _realPng() async {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    Uint8List.fromList(
      List.generate(16 * 16 * 4, (i) => i % 4 == 3 ? 255 : (i * 7) % 256),
    ),
    16,
    16,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  final image = await completer.future;
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
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
    test(
      'stores tiles and lookup serves the nearest within tolerance',
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
      },
    );

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

    test(
      'a failed sweep retries and RESUMES past the last stored tile',
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
      },
    );

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

    test('disposeGate is forwarded into every sweep request', () async {
      // The gate is the ONLY thing standing between a cancelled sweep and a
      // platform-thread deadlock on fvp (dispose during foreground playback,
      // sampled live on 1.6.5) — a service that silently drops it recreates
      // that deadlock with no compile-time signal.
      final sweeper = FakeSweeper();
      Future<void> gate() async {}
      final service = SpriteSweepService(
        createSweeper: () => sweeper,
        disposeGate: gate,
      );
      service.startSweep(episodeIndex: 0, url: 'http://x/low.m3u8');
      await _settle();
      expect(sweeper.requests.single.disposeGate, same(gate));
      service.dispose();
    });

    test(
      'cancel + restart across the async resolve gap yields ONE sweeper',
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
          reason:
              'the stale continuation must abort; two sweepers means two '
              'concurrent 16x players, the first uncancellable',
        );
        expect(service.isSweeping, isTrue);
        service.cancelSweep();
        expect(sweepers.single.cancelled, isTrue);
        service.dispose();
      },
    );

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
        reason:
            'retry budget is 3 — an un-sweepable source must not burn '
            'bandwidth forever against the video being watched',
      );
      service.dispose();
    });

    test('an engine that pre-encodes stores its bytes verbatim', () async {
      // media_kit's screenshot() already returns PNG. The frame is still
      // decoded once (the perceptual hash needs pixels), but the bytes handed
      // to the preview must be the engine's originals, not a re-encode.
      final sweeper = FakeSweeper();
      final service = SpriteSweepService(createSweeper: () => sweeper);
      service.startSweep(episodeIndex: 0, url: 'u');
      await _settle();

      final png = await _realPng();
      sweeper.emitEncodedFrame(10, png);
      await _settle();

      expect(service.lookup(0, 10), same(png));
      service.dispose();
    });

    test('a frame the platform cannot decode is dropped, not stored', () async {
      // Undecodable bytes would fail in Image.memory too, so a preview built
      // from them shows nothing — and they cannot be hashed, so they carry no
      // detection value either.
      final sweeper = FakeSweeper();
      final service = SpriteSweepService(createSweeper: () => sweeper);
      service.startSweep(episodeIndex: 0, url: 'u');
      await _settle();

      sweeper.emitEncodedFrame(10, Uint8List.fromList([137, 80, 78, 71, 9]));
      await _settle();

      expect(service.lookup(0, 10), isNull);
      service.dispose();
    });

    test('hashes are reported once the head is covered, not at the end of '
        'the sweep', () async {
      // Measured on device: the user browsed episodes normally, every switch
      // cancelled the in-flight sweep, and because hashes were only reported
      // at completion NOTHING was ever persisted and no marker ever appeared —
      // even though the head window, which is all detection compares, had been
      // covered within seconds each time.
      final reported = <int>[];
      final sweeper = FakeSweeper();
      final service = SpriteSweepService(
        createSweeper: () => sweeper,
        onHashesReady: reported.add,
      );
      service.startSweep(episodeIndex: 2, url: 'u');
      await _settle();

      // Inside the head window: nothing to act on yet.
      sweeper.emitHashableFrame(10);
      sweeper.emitHashableFrame(120);
      await _settle();
      expect(reported, isEmpty);

      // First frame past it — detection has everything the head can give.
      sweeper.emitHashableFrame(SpriteSweepService.fineRegion.inSeconds + 2);
      await _settle();
      expect(reported, [2]);

      // Once per episode, not per frame.
      sweeper.emitHashableFrame(600);
      await _settle();
      expect(reported, [2]);

      // And again at completion, which is when the tail exists and an outro
      // becomes findable.
      await sweeper.done();
      await _settle();
      expect(reported, [2, 2]);
      service.dispose();
    });

    test('a sweep is only "complete" once the stream ends, and that '
        'survives storage', () async {
      // This gates tail detection. detectOutro measures backwards from the
      // LAST TILE, so on a half-swept episode it treats wherever the sweep
      // stopped as the credits and answers confidently. Measured on device: a
      // mid-sweep episode compared against a complete one yielded outro=23s,
      // persisted as a detected marker — auto-skip would have cut a 44-minute
      // episode 23 seconds in.
      final sweeper = FakeSweeper();
      final service = SpriteSweepService(createSweeper: () => sweeper);
      service.startSweep(episodeIndex: 0, url: 'u');
      await _settle();
      sweeper.emitHashableFrame(10);
      sweeper.emitHashableFrame(500);
      await _settle();

      expect(
        service.isComplete(0),
        isFalse,
        reason: 'tiles exist, but nothing says they reach the end',
      );
      // A partial set must READ as partial after a restart too, or the guard
      // silently stops working across sessions.
      final partial = service.exportHashes(0)!;
      final restoredPartial = SpriteSweepService(
        createSweeper: () => FakeSweeper(),
      );
      restoredPartial.importHashes(0, partial);
      expect(restoredPartial.hashedTiles(0), hasLength(2));
      expect(restoredPartial.isComplete(0), isFalse);

      await sweeper.done();
      await _settle();
      expect(service.isComplete(0), isTrue);

      final full = service.exportHashes(0)!;
      final restoredFull = SpriteSweepService(
        createSweeper: () => FakeSweeper(),
      );
      restoredFull.importHashes(7, full);
      expect(restoredFull.isComplete(7), isTrue);

      service.dispose();
      restoredPartial.dispose();
      restoredFull.dispose();
    });

    test('hashes survive an export/import round trip', () async {
      final sweeper = FakeSweeper();
      final service = SpriteSweepService(createSweeper: () => sweeper);
      service.startSweep(episodeIndex: 0, url: 'u0');
      await _settle();
      sweeper.emitHashableFrame(2);
      sweeper.emitHashableFrame(
        2960,
      ); // past uint16, and a real episode is longer
      await _settle();

      final blob = service.exportHashes(0)!;
      final original = service.hashedTiles(0);
      expect(original, hasLength(2));

      // A fresh service, as a later session would be.
      final restored = SpriteSweepService(createSweeper: () => FakeSweeper());
      restored.importHashes(3, blob);
      expect(restored.hashedTiles(3), original);
      // Hashes only: the episode must still be swept for its preview tiles.
      expect(restored.covers(3), isFalse);
      expect(restored.lookup(3, 2), isNull);
      expect(restored.episodesWithHashes(minTiles: 2), [3]);

      service.dispose();
      restored.dispose();
    });

    test('a blob from an unknown format is discarded, not misread', () async {
      final sweeper = FakeSweeper();
      final service = SpriteSweepService(createSweeper: () => sweeper);
      service.startSweep(episodeIndex: 0, url: 'u0');
      await _settle();
      sweeper.emitHashableFrame(10);
      await _settle();
      final blob = service.exportHashes(0)!;
      service.dispose();

      // Stored bytes outlive the code that wrote them, and a misread hash set
      // does not fail loudly — it places skip markers from footage it never
      // saw. Both corruptions must yield nothing at all.
      final s = SpriteSweepService(createSweeper: () => FakeSweeper());
      s.importHashes(0, [...blob]..[0] = 99); // future version
      expect(s.hashedTiles(0), isEmpty);
      s.importHashes(1, blob.sublist(0, blob.length - 3)); // truncated
      expect(s.hashedTiles(1), isEmpty);
      s.importHashes(2, const []);
      expect(s.hashedTiles(2), isEmpty);
      s.dispose();
    });

    test('clear() drops hashes as well as tiles', () async {
      // Both are keyed by episode INDEX, and detection WRITES skip markers
      // from the hashes — surviving a catalog change means marking episode 3
      // from whatever used to be at index 3.
      final sweeper = FakeSweeper();
      final service = SpriteSweepService(createSweeper: () => sweeper);
      service.startSweep(episodeIndex: 0, url: 'u0');
      await _settle();
      sweeper.emitHashableFrame(10);
      await _settle();
      expect(service.hashedTiles(0), isNotEmpty);

      service.clear();
      expect(service.hashedTiles(0), isEmpty);
      expect(service.lookup(0, 10), isNull);
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
