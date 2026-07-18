import 'dart:async';

import '../core/interfaces/media_repository.dart';
import '../core/state/media_context.dart';
import '../core/model/model.dart';
import '../core/lifecycle/lifecycle_token.dart';
import '../core/lifecycle/safe_stream.dart';
import '../utils/event_control.dart';
import '../utils/log.dart';

/// Manages media context including video, episodes, quality selections,
/// history tracking, and player settings.
class MediaManager with LifecycleTokenProvider {
  // ===============================================================
  // Dependencies & State
  // ===============================================================

  final MediaRepository _repository;

  final _mediaCtrl = StreamController<MediaContextState>.broadcast();
  MediaContextState _state = const MediaContextState();

  // Lifecycle flag
  bool _isDisposed = false;

  // Utils
  final Latest _saveSettingLatest = Latest();
  final Throttle _saveProgressThrottle = Throttle(const Duration(seconds: 10));

  // ===============================================================
  // Construction
  // ===============================================================

  MediaManager({required MediaRepository repository})
    : _repository = repository;

  // ===============================================================
  // Stream & State Accessors
  // ===============================================================

  Stream<MediaContextState> get mediaStream => _mediaCtrl.stream;
  MediaContextState get state => _state;

  // ===============================================================
  // Initialization & Basic Updates
  // ===============================================================

  void initialize({
    VideoMetadata? video,
    required List<VideoEpisode> episodes,
    int? episodeIndex,
    int? qualityIndex,
  }) {
    if (_isDisposed) return;

    _state = _state.copyWith(
      video: video,
      episodes: episodes,
      currentEpisodeIndex: episodeIndex ?? 0,
      currentQualityIndex: qualityIndex ?? 0,
    );

    if (!_mediaCtrl.isClosed) {
      _mediaCtrl.add(_state);
    }

    if (episodes.isNotEmpty) {
      getAllHistories();
      getPlayerSettings();
    }
  }

  void updateEpisodes(List<VideoEpisode> episodes) {
    if (_isDisposed) return;
    _state = _state.copyWith(episodes: episodes);
    if (!_mediaCtrl.isClosed) {
      _mediaCtrl.add(_state);
    }
  }

  void updateHistory(List<EpisodeHistory> histories) {
    if (_isDisposed) return;
    _state = _state.copyWith(episodeHistory: histories);
    if (!_mediaCtrl.isClosed) {
      _mediaCtrl.add(_state);
    }
  }

  void switchEpisode(int index) {
    if (_isDisposed) return;
    if (index < 0 || index >= _state.episodes.length) return;

    // Carry the current quality across episodes by LABEL when the target offers
    // it; otherwise fall back to the first quality. This keeps
    // currentQualityIndex valid for the new episode so media state and the
    // source that playback actually opens can never diverge (and
    // currentQuality/currentSource can't land on a stale out-of-range index).
    final currentLabel = _state.currentQuality?.label;
    final targetQualities = _state.episodes[index].qualities;
    var nextQualityIndex = 0;
    if (currentLabel != null) {
      final match = targetQualities.indexWhere((q) => q.label == currentLabel);
      if (match >= 0) nextQualityIndex = match;
    }

    _state = _state.copyWith(
      currentEpisodeIndex: index,
      currentQualityIndex: nextQualityIndex,
    );
    if (!_mediaCtrl.isClosed) {
      _mediaCtrl.add(_state);
    }
  }

  void switchQuality(int qualityIndex) {
    if (_isDisposed) return;
    if (_state.currentQualityIndex != qualityIndex) {
      _state = _state.copyWith(currentQualityIndex: qualityIndex);
      if (!_mediaCtrl.isClosed) {
        _mediaCtrl.add(_state);
      }
    }
  }

  void updatePlayerSetting(PlayerSetting setting) {
    if (_isDisposed) return;
    _state = _state.copyWith(playerSetting: setting);
    if (!_mediaCtrl.isClosed) {
      _mediaCtrl.add(_state);
    }
  }

  // ===============================================================
  // History Management
  // ===============================================================

  Future<void> saveProgress({
    required int episodeIndex,
    required int positionMillis,
    required int durationMillis,
  }) async {
    final token = lifecycleToken;
    if (!token.isAlive || durationMillis <= 0) return;

    _saveProgressThrottle.call(() async {
      if (!token.isAlive) return;

      final history = EpisodeHistory(
        index: episodeIndex,
        positionMillis: positionMillis,
        durationMillis: durationMillis,
      );

      await _repository.saveEpisodeHistory(_state.video!.id, history);

      if (!token.isAlive) return;

      final histories = List<EpisodeHistory>.from(_state.episodeHistory);
      final historyIndex = histories.indexWhere((h) => h.index == episodeIndex);
      if (historyIndex >= 0) {
        histories[historyIndex] = history;
      } else {
        histories.add(history);
      }

      _state = _state.copyWith(episodeHistory: histories);
      safeEmit(_mediaCtrl, _state, token);
    });
  }

  // Force save immediately (e.g. on pause or dispose)
  Future<void> saveProgressImmediate({
    required int episodeIndex,
    required int positionMillis,
    required int durationMillis,
  }) async {
    final token = lifecycleToken;
    if (!token.isAlive || durationMillis <= 0) return;

    final history = EpisodeHistory(
      index: episodeIndex,
      positionMillis: positionMillis,
      durationMillis: durationMillis,
    );

    await _repository.saveEpisodeHistory(_state.video!.id, history);
  }

  Future<List<EpisodeHistory>> getAllHistories() async {
    final token = lifecycleToken;
    if (!token.isAlive || _state.video == null) return [];

    final histories = await _repository.getEpisodeHistories(
      videoId: _state.video!.id,
    );

    if (!token.isAlive) return histories;
    updateHistory(histories);
    return histories;
  }

  Future<EpisodeHistory?> getEpisodeHistory(int episodeIndex) async {
    if (_state.episodeHistory.isNotEmpty) {
      try {
        return _state.episodeHistory.firstWhere((h) => h.index == episodeIndex);
      } catch (e) {
        return null;
      }
    }
    return null;
  }

  /// @deprecated Use getEpisodeHistory and handle logic in delegate
  Future<EpisodeHistory?> shouldRestore(int episodeIndex) async {
    logger.d(
      "[HistoryManager] Checking restore for: ${_state.episodes[episodeIndex].title}",
    );
    final history = await getEpisodeHistory(episodeIndex);

    if (history == null) return null;

    final canRestore =
        history.positionMillis > 30000 &&
        history.positionMillis < (history.durationMillis * 0.95);

    logger.d(
      "[HistoryManager] History found: ${history.positionMillis}ms. Can restore: $canRestore",
    );

    if (canRestore) {
      return history;
    }

    return null;
  }

  // ===============================================================
  // Player Configuration/Settings (Auto-Skip, etc.)
  // ===============================================================

  PlayerSetting _currentOrDefaultSetting() {
    return _state.playerSetting ??
        PlayerSetting(videoId: _state.video?.id ?? 'unknown');
  }

  void updateSetting(PlayerSetting setting) {
    final token = lifecycleToken;
    if (!token.isAlive) return;

    _saveSettingLatest.run(() async {
      if (!token.isAlive) return;
      await _repository.savePlayerSettings(setting);
      if (!token.isAlive) return;

      _state = _state.copyWith(playerSetting: setting);
      safeEmit(_mediaCtrl, _state, token);
    });
  }

  Future<void> updateAutoSkip(bool autoSkip) async {
    if (_isDisposed) return;
    final playerSetting = _currentOrDefaultSetting().copyWith(
      autoSkip: autoSkip,
    );
    _state = _state.copyWith(playerSetting: playerSetting);
    updateSetting(playerSetting);
  }

  Future<void> updateSkipIntro(int skipIntro) async {
    if (_isDisposed) return;
    final playerSetting = _currentOrDefaultSetting().copyWith(
      skipIntro: skipIntro,
    );
    _state = _state.copyWith(playerSetting: playerSetting);
    updateSetting(playerSetting);
  }

  Future<void> updateSkipOutro(int skipOutro) async {
    if (_isDisposed) return;
    final playerSetting = _currentOrDefaultSetting().copyWith(
      skipOutro: skipOutro,
    );
    _state = _state.copyWith(playerSetting: playerSetting);
    updateSetting(playerSetting);
  }

  Future<PlayerSetting> getPlayerSettings() async {
    final token = lifecycleToken;
    if (!token.isAlive || _state.video == null) {
      return PlayerSetting(videoId: 'unknown');
    }

    final setting = await _repository.getPlayerSettings(
      videoId: _state.video!.id,
    );

    if (!token.isAlive) return setting;

    _state = _state.copyWith(playerSetting: setting);
    safeEmit(_mediaCtrl, _state, token);
    return setting;
  }

  // ===============================================================
  // Disposal
  // ===============================================================

  void dispose() {
    if (_isDisposed) return;
    invalidateLifecycle(); // Invalidate all tokens first
    _isDisposed = true;
    _mediaCtrl.close();
    _saveSettingLatest.dispose();
    _saveProgressThrottle.dispose();
  }
}
