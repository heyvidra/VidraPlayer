import 'package:flutter_test/flutter_test.dart';
import 'package:vidra_player/core/lifecycle/lifecycle_token.dart';
import 'package:vidra_player/core/lifecycle/safe_stream.dart';
import 'dart:async';

class _TestClass with LifecycleTokenProvider {
  void dispose() {
    invalidateLifecycle();
  }
}

void main() {
  group('LifecycleToken', () {
    test('token is alive before invalidation', () {
      final obj = _TestClass();
      final token = obj.lifecycleToken;

      expect(token.isAlive, true);
    });

    test('token is dead after invalidation', () {
      final obj = _TestClass();
      final token = obj.lifecycleToken;

      obj.dispose();

      expect(token.isAlive, false);
    });

    test('new token after invalidation is alive', () {
      final obj = _TestClass();
      final token1 = obj.lifecycleToken;

      obj.invalidateLifecycle();

      final token2 = obj.lifecycleToken;

      expect(token1.isAlive, false);
      expect(token2.isAlive, true);
    });

    test('token survives async gap when not invalidated', () async {
      final obj = _TestClass();
      final token = obj.lifecycleToken;

      expect(token.isAlive, true);

      await Future.delayed(const Duration(milliseconds: 10));

      expect(token.isAlive, true);
    });

    test('token dies during async gap if invalidated', () async {
      final obj = _TestClass();
      final token = obj.lifecycleToken;

      expect(token.isAlive, true);

      // Simulate async work with disposal in the middle
      final future = Future.delayed(const Duration(milliseconds: 10));
      obj.dispose();

      await future;

      expect(token.isAlive, false);
    });

    test('multiple tokens from same object share state', () {
      final obj = _TestClass();
      final token1 = obj.lifecycleToken;
      final token2 = obj.lifecycleToken;

      expect(token1.isAlive, true);
      expect(token2.isAlive, true);

      obj.dispose();

      expect(token1.isAlive, false);
      expect(token2.isAlive, false);
    });

    test('ensureAlive throws when token is dead', () {
      final obj = _TestClass();
      final token = obj.lifecycleToken;

      obj.dispose();

      expect(() => token.ensureAlive(), throwsA(isA<StateError>()));
    });

    test('ensureAlive does not throw when token is alive', () {
      final obj = _TestClass();
      final token = obj.lifecycleToken;

      expect(() => token.ensureAlive(), returnsNormally);
    });
  });

  group('safeEmit', () {
    test('emits when token is alive and controller is open', () async {
      final obj = _TestClass();
      final token = obj.lifecycleToken;
      final controller = StreamController<int>.broadcast();
      final events = <int>[];

      controller.stream.listen(events.add);
      await Future.delayed(Duration.zero); // Pump for listener

      safeEmit(controller, 42, token);
      await Future.delayed(Duration.zero); // Pump for emission

      expect(events, [42]);

      unawaited(controller.close());
    });

    test('does not emit when token is dead', () {
      final obj = _TestClass();
      final token = obj.lifecycleToken;
      final controller = StreamController<int>.broadcast();
      final events = <int>[];

      controller.stream.listen(events.add);

      obj.dispose();

      safeEmit(controller, 42, token);

      expect(events, isEmpty);

      unawaited(controller.close());
    });

    test('does not emit when controller is closed', () {
      final obj = _TestClass();
      final token = obj.lifecycleToken;
      final controller = StreamController<int>.broadcast();
      final events = <int>[];

      controller.stream.listen(events.add);
      unawaited(controller.close());

      // Should not throw
      expect(() => safeEmit(controller, 42, token), returnsNormally);

      expect(events, isEmpty);
    });

    test('does not emit when both token is dead and controller is closed', () {
      final obj = _TestClass();
      final token = obj.lifecycleToken;
      final controller = StreamController<int>.broadcast();
      final events = <int>[];

      controller.stream.listen(events.add);

      obj.dispose();
      unawaited(controller.close());

      // Should not throw
      expect(() => safeEmit(controller, 42, token), returnsNormally);

      expect(events, isEmpty);
    });

    test('async scenario: emit after await with alive token', () async {
      final obj = _TestClass();
      final token = obj.lifecycleToken;
      final controller = StreamController<int>.broadcast();
      final events = <int>[];

      controller.stream.listen(events.add);
      await Future.delayed(Duration.zero); // Pump for listener

      await Future.delayed(const Duration(milliseconds: 10));

      safeEmit(controller, 42, token);
      await Future.delayed(Duration.zero); // Pump for emission

      expect(events, [42]);

      unawaited(controller.close());
    });

    test('async scenario: no emit after await with dead token', () async {
      final obj = _TestClass();
      final token = obj.lifecycleToken;
      final controller = StreamController<int>.broadcast();
      final events = <int>[];

      controller.stream.listen(events.add);

      final future = Future.delayed(const Duration(milliseconds: 10));
      obj.dispose();
      await future;

      safeEmit(controller, 42, token);

      expect(events, isEmpty);

      unawaited(controller.close());
    });
  });

  group('safeEmitWithBreadcrumb', () {
    test('emits when token is alive and controller is open', () async {
      final obj = _TestClass();
      final token = obj.lifecycleToken;
      final controller = StreamController<int>.broadcast();
      final events = <int>[];

      controller.stream.listen(events.add);
      await Future.delayed(Duration.zero); // Pump for listener

      safeEmitWithBreadcrumb(controller, 42, token, component: 'test');
      await Future.delayed(Duration.zero); // Pump for emission

      expect(events, [42]);

      unawaited(controller.close());
    });

    test('does not emit when token is dead', () {
      final obj = _TestClass();
      final token = obj.lifecycleToken;
      final controller = StreamController<int>.broadcast();
      final events = <int>[];

      controller.stream.listen(events.add);

      obj.dispose();

      safeEmitWithBreadcrumb(controller, 42, token, component: 'test');

      expect(events, isEmpty);

      unawaited(controller.close());
    });
  });
}
