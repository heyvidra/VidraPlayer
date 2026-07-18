import 'dart:async';

import '../core/interfaces/video_player.dart';
import '../core/lifecycle/lifecycle_token.dart';
import '../core/state/audio.dart';

class AudioManager with LifecycleTokenProvider {
  // ===============================================================
  // Dependencies & State
  // ===============================================================

  final IVideoPlayer _player;

  final _audioCtrl = StreamController<AudioState>.broadcast();
  AudioState _state = const AudioState();

  // Lifecycle flag
  bool _isDisposed = false;

  // ===============================================================
  // Construction
  // ===============================================================

  AudioManager({required IVideoPlayer player}) : _player = player;

  // ===============================================================
  // Stream & State Accessors
  // ===============================================================

  Stream<AudioState> get audioStream => _audioCtrl.stream;
  AudioState get state => _state;

  // ===============================================================
  // Actions
  // ===============================================================

  Future<void> setVolume(double volume) async {
    if (_isDisposed) return;

    _state = _state.copyWith(volume: volume, isMuted: volume == 0);
    if (!_audioCtrl.isClosed) {
      _audioCtrl.add(_state);
    }
    await _player.setVolume(volume);
  }

  Future<void> setMute() async {
    if (_isDisposed) return;

    _state = _state.copyWith(isMuted: true);
    if (!_audioCtrl.isClosed) {
      _audioCtrl.add(_state);
    }
    await _player.setVolume(0);
  }

  Future<void> setPlaybackSpeed(double speed) async {
    if (_isDisposed) return;

    _state = _state.copyWith(playbackSpeed: speed);
    if (!_audioCtrl.isClosed) {
      _audioCtrl.add(_state);
    }
    await _player.setPlaybackSpeed(speed);
  }

  Future<void> restoreState() async {
    final token = lifecycleToken;
    if (!token.isAlive) return;

    if (_state.isMuted) {
      await _player.setVolume(0);
    } else {
      await _player.setVolume(_state.volume);
    }

    if (!token.isAlive) return;
    await _player.setPlaybackSpeed(_state.playbackSpeed);
  }

  Future<void> toggleMute() async {
    if (_isDisposed) return;

    double newVolume = _state.isMuted
        ? (_state.volume == 0 ? 1.0 : _state.volume)
        : 0.0;
    if (newVolume == 0) {
      await setMute();
    } else {
      await setVolume(newVolume);
    }
  }

  // ===============================================================
  // Disposal
  // ===============================================================

  void dispose() {
    if (_isDisposed) return;
    invalidateLifecycle();
    _isDisposed = true;
    _audioCtrl.close();
  }
}
