import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vidra_player/core/interfaces/video_player.dart';
import 'package:vidra_player/core/model/model.dart';
import 'package:vidra_player/core/state/states.dart';
import 'package:vidra_player/managers/playback_manager.dart';

/// Minimal controllable fake for PlaybackManager-focused tests.
class _FakePlayer implements IVideoPlayer {
  final _positionCtrl = StreamController<Duration>.broadcast();
  final _bufferingCtrl = StreamController<BufferingState>.broadcast();
  final _playingCtrl = StreamController<bool>.broadcast();
  final _liveCtrl = StreamController<bool>.broadcast();
  final _errorCtrl = StreamController<PlayerError?>.broadcast();
  final _bufferedCtrl = StreamController<List<BufferRange>>.broadcast();
  final _videoSizeCtrl = StreamController<VideoSize?>.broadcast();
  final _completedCtrl = StreamController<bool>.broadcast();

  Duration _position = Duration.zero;
  bool playShouldThrow = false;
  bool pauseShouldThrow = false;
  int playCalls = 0;
  int pauseCalls = 0;
  Duration? lastSeekTarget;

  @override
  Duration get duration => const Duration(minutes: 2);

  @override
  Duration get position => _position;

  @override
  bool get isPlaying => false;

  @override
  bool get isLive => false;

  @override
  VideoSize? get videoSize => null;

  @override
  Stream<Duration> get positionStream => _positionCtrl.stream;

  @override
  Stream<BufferingState> get bufferingStream => _bufferingCtrl.stream;

  @override
  Stream<bool> get isPlayingStream => _playingCtrl.stream;

  @override
  Stream<bool> get isLiveStream => _liveCtrl.stream;

  @override
  Stream<PlayerError?> get errorStream => _errorCtrl.stream;

  @override
  Stream<List<BufferRange>> get bufferedStream => _bufferedCtrl.stream;

  @override
  Stream<VideoSize?> get videoSizeStream => _videoSizeCtrl.stream;

  @override
  Stream<bool> get completedStream => _completedCtrl.stream;

  void emitPlaying(bool playing) => _playingCtrl.add(playing);
  void emitCompleted(bool completed) => _completedCtrl.add(completed);
  void emitPosition(Duration pos) {
    _position = pos;
    _positionCtrl.add(pos);
  }

  @override
  Future<void> initialize(VideoSource source) async {}

  @override
  Future<void> play() async {
    playCalls++;
    if (playShouldThrow) throw StateError('play blocked');
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    if (pauseShouldThrow) throw StateError('pause blocked');
  }

  @override
  Future<void> seek(Duration position) async {
    lastSeekTarget = position;
  }

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> setPlaybackSpeed(double speed) async {}

  @override
  Future<void> reset() async {}

  @override
  Widget render({
    Key? key,
    BoxFit fit = BoxFit.contain,
    Alignment alignment = Alignment.center,
  }) => const SizedBox.shrink();

  @override
  Future<void> dispose() async {
    await _positionCtrl.close();
    await _bufferingCtrl.close();
    await _playingCtrl.close();
    await _liveCtrl.close();
    await _errorCtrl.close();
    await _bufferedCtrl.close();
    await _videoSizeCtrl.close();
    await _completedCtrl.close();
  }
}

PlaybackManager _buildManager(_FakePlayer player, {bool loop = false}) {
  return PlaybackManager(
    config: PlayerConfig(behavior: PlayerBehavior(loop: loop)),
    player: player,
  );
}

Future<void> _pump() => Future<void>.delayed(Duration.zero);

void main() {
  group('isPlayingStream reconciliation', () {
    test('external pause from the player flips lifecycle to paused', () async {
      final player = _FakePlayer();
      final manager = _buildManager(player);

      await manager.play();
      expect(manager.lifecycleState.isPlaying, isTrue);

      // Player pauses on its own (OS audio-focus loss, natural end...).
      player.emitPlaying(false);
      await _pump();

      expect(manager.lifecycleState.isPlaying, isFalse);
      expect(manager.lifecycleState.status, PlaybackStatus.paused);

      manager.dispose();
      await player.dispose();
    });

    test('external play from the player flips lifecycle to playing', () async {
      final player = _FakePlayer();
      final manager = _buildManager(player);

      player.emitPlaying(true);
      await _pump();

      expect(manager.lifecycleState.isPlaying, isTrue);
      expect(manager.lifecycleState.status, PlaybackStatus.playing);

      manager.dispose();
      await player.dispose();
    });
  });

  group('optimistic state rollback', () {
    test('play() failure reverts the optimistic playing state', () async {
      final player = _FakePlayer()..playShouldThrow = true;
      final manager = _buildManager(player);

      await manager.play();

      expect(player.playCalls, 1);
      expect(manager.lifecycleState.isPlaying, isFalse,
          reason: 'blocked play() must not leave a phantom playing state');

      manager.dispose();
      await player.dispose();
    });

    test('pause() failure reverts the optimistic paused state', () async {
      final player = _FakePlayer();
      final manager = _buildManager(player);

      await manager.play();
      player.pauseShouldThrow = true;
      await manager.pause();

      expect(player.pauseCalls, 1);
      expect(manager.lifecycleState.isPlaying, isTrue,
          reason: 'failed pause() must roll back to the previous state');

      manager.dispose();
      await player.dispose();
    });
  });

  group('seek', () {
    test('completes and clears seekTarget when a tick lands near the target',
        () async {
      final player = _FakePlayer();
      final manager = _buildManager(player);

      unawaited(manager.seek(const Duration(seconds: 30), SeekSource.external));
      expect(manager.positionState.isSeeking, isTrue);
      expect(manager.positionState.seekTarget, const Duration(seconds: 30));

      player.emitPosition(const Duration(seconds: 30, milliseconds: 100));
      await _pump();

      expect(manager.positionState.isSeeking, isFalse);
      expect(manager.positionState.seekTarget, isNull,
          reason: 'clearSeek must actually null the stale target');
      expect(manager.positionState.seekSource, isNull);

      manager.dispose();
      await player.dispose();
    });

    test('watchdog force-clears a stuck isSeeking after the timeout',
        () async {
      final player = _FakePlayer();
      final manager = _buildManager(player);

      unawaited(manager.seek(const Duration(seconds: 30), SeekSource.userDrag));
      expect(manager.positionState.isSeeking, isTrue);

      // No position tick ever lands near the target (keyframe-sparse seek).
      await Future<void>.delayed(const Duration(milliseconds: 2200));

      expect(manager.positionState.isSeeking, isFalse,
          reason: 'watchdog must clear stuck seeking state');
      expect(manager.positionState.seekTarget, isNull);

      manager.dispose();
      await player.dispose();
    });
  });

  group('completedStream', () {
    test('completion marks lifecycle as ended and not playing', () async {
      final player = _FakePlayer();
      final manager = _buildManager(player);

      await manager.play();
      player.emitCompleted(true);
      await _pump();

      expect(manager.lifecycleState.status, PlaybackStatus.ended);
      expect(manager.lifecycleState.isPlaying, isFalse);

      manager.dispose();
      await player.dispose();
    });

    test('completion with loop enabled restarts instead of ending', () async {
      final player = _FakePlayer();
      final manager = _buildManager(player, loop: true);

      await manager.play();
      player.emitCompleted(true);
      await _pump();

      expect(player.lastSeekTarget, Duration.zero,
          reason: 'loop must seek back to the start');
      expect(manager.lifecycleState.status, isNot(PlaybackStatus.ended));

      manager.dispose();
      await player.dispose();
    });
  });

  group('seek emission', () {
    // Regression: seek() used to assign _positionState and then emit the SAME
    // object — the no-op equality guard in _emitPositionState saw
    // next == _positionState and swallowed every seek event. While paused the
    // player emits no ticks to self-heal, so the progress bar / seek events
    // froze on the pre-seek position (user-visible as "pause acts weird").
    test('seek() notifies position consumers even while paused', () async {
      final player = _FakePlayer();
      final manager = _buildManager(player);

      final emitted = <PlaybackPositionState>[];
      final sub = manager.positionStream.listen(emitted.add);

      await manager.pause();
      await manager.seek(const Duration(seconds: 30), SeekSource.userDrag);
      await _pump();

      expect(player.lastSeekTarget, const Duration(seconds: 30));
      expect(
        manager.positionNotifier.value.seekTarget,
        const Duration(seconds: 30),
        reason: 'notifier must reflect the in-flight seek',
      );
      expect(
        emitted.any(
          (s) => s.isSeeking && s.seekTarget == const Duration(seconds: 30),
        ),
        isTrue,
        reason: 'seek must be emitted on the position stream',
      );

      await sub.cancel();
      manager.dispose();
      await player.dispose();
    });

    test('no-op position re-reports are swallowed, real changes pass', () async {
      final player = _FakePlayer();
      final manager = _buildManager(player);

      var notifications = 0;
      manager.positionNotifier.addListener(() => notifications++);

      player.emitPosition(const Duration(seconds: 5));
      await _pump();
      final afterFirst = notifications;
      expect(afterFirst, greaterThan(0));

      // Same position again (paused tick) — must not notify.
      player.emitPosition(const Duration(seconds: 5));
      await _pump();
      expect(notifications, afterFirst);

      player.emitPosition(const Duration(seconds: 6));
      await _pump();
      expect(notifications, greaterThan(afterFirst));

      manager.dispose();
      await player.dispose();
    });
  });

  test('dispose is idempotent', () async {
    final player = _FakePlayer();
    final manager = _buildManager(player);

    manager.dispose();
    expect(manager.dispose, returnsNormally);

    await player.dispose();
  });
}
