import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vidra_player/core/adapters/base_video_player_adapter.dart';
import 'package:vidra_player/core/model/model.dart';
import 'package:vidra_player/core/lifecycle/lifecycle_token.dart';

/// Regression for the HLS Phase-2 fast path: a duration already past 5 min
/// that holds for 2 consecutive 500ms readings must exit immediately instead
/// of paying the full 6-reading (3 s) stability window; short VODs must still
/// pay it (a growing index can plausibly pause on a small value).
class _ProbeAdapter extends BaseVideoPlayerAdapter {
  Duration current = Duration.zero;

  Future<void> waitStable() => waitForFormatStable(
        source: const VideoSource.network('https://cdn.example.com/index.m3u8'),
        token: lifecycleToken,
        cancelToken: Completer<OpenResult>(),
        getCurrentDuration: () => current,
      );

  @override
  Future<void> onInitialize(VideoSource source, LifecycleToken token) async {}

  @override
  Future<void> onReset() async {}

  @override
  Widget buildRenderWidget(Key? key, BoxFit fit, Alignment alignment) =>
      const SizedBox.shrink();

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> setPlaybackSpeed(double speed) async {}

  @override
  Duration get duration => current;

  @override
  Duration get position => Duration.zero;

  @override
  bool get isPlaying => false;

  @override
  bool get isLive => false;

  @override
  VideoSize? get videoSize => null;
}

void main() {
  test('large stable duration exits via fast path after 2 polls (~1s)', () {
    fakeAsync((async) {
      final adapter = _ProbeAdapter()..current = const Duration(minutes: 10);
      var done = false;
      adapter.waitStable().then((_) => done = true);

      async.elapse(const Duration(milliseconds: 1100));
      expect(done, isTrue, reason: '2 stable readings past 5min should exit');
    });
  });

  test('short VOD still pays the full 6-reading (3s) stability window', () {
    fakeAsync((async) {
      final adapter = _ProbeAdapter()..current = const Duration(minutes: 2);
      var done = false;
      adapter.waitStable().then((_) => done = true);

      async.elapse(const Duration(milliseconds: 1100));
      expect(done, isFalse, reason: 'fast path must not apply under 5min');

      async.elapse(const Duration(milliseconds: 2500));
      expect(done, isTrue, reason: 'full window should complete by ~3s');
    });
  });
}
