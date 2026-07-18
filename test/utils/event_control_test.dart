import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vidra_player/utils/event_control.dart';

void main() {
  group('Latest (single-flight, keep latest)', () {
    test('runs the in-flight task, then only the latest queued one', () async {
      final log = <String>[];
      final latest = Latest();
      final gateA = Completer<void>();

      // A starts immediately (leading) and blocks until released.
      latest.run(() async {
        log.add('A-start');
        await gateA.future;
        log.add('A-end');
      });
      // Queued while A is in flight; C supersedes B, so B must be dropped.
      latest.run(() async => log.add('B'));
      latest.run(() async => log.add('C'));

      gateA.complete();
      await Future.delayed(const Duration(milliseconds: 10));

      // The old broken version let a stale write land after a newer one; the
      // fixed version drops the superseded B and only runs the latest (C).
      expect(log, ['A-start', 'A-end', 'C']);
    });

    test('a task queued after dispose never runs', () async {
      final log = <String>[];
      final latest = Latest();
      final gateA = Completer<void>();

      latest.run(() async {
        log.add('A-start');
        await gateA.future;
        log.add('A-end');
      });
      latest.dispose(); // drops the pending queue and stops draining
      latest.run(() async => log.add('after-dispose'));

      gateA.complete();
      await Future.delayed(const Duration(milliseconds: 10));

      expect(log, isNot(contains('after-dispose')));
    });
  });
}
