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
      loadEpisodeMarkers();
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
    // video is what the write is KEYED by. Every caller happens to check it
    // today, which is exactly why the `!` below survived — one refactor away
    // from a null-bang crash on the position tick, ten times a second.
    final video = _state.video;
    if (!token.isAlive || video == null || durationMillis <= 0) return;

    _saveProgressThrottle.call(() async {
      if (!token.isAlive) return;

      final history = EpisodeHistory(
        index: episodeIndex,
        positionMillis: positionMillis,
        durationMillis: durationMillis,
      );

      await _repository.saveEpisodeHistory(video.id, history);

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
    final video = _state.video;
    if (!token.isAlive || video == null || durationMillis <= 0) return;

    final history = EpisodeHistory(
      index: episodeIndex,
      positionMillis: positionMillis,
      durationMillis: durationMillis,
    );

    await _repository.saveEpisodeHistory(video.id, history);
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

  // ===============================================================
  // Player Configuration/Settings (Auto-Skip, etc.)
  // ===============================================================

  PlayerSetting _currentOrDefaultSetting() {
    return _state.playerSetting ??
        PlayerSetting(videoId: _state.video?.id ?? 'unknown');
  }

  /// Apply [setting] now, persist it after.
  ///
  /// The emission used to wait for the repository write to come back, while
  /// the three callers below mutated `_state` synchronously and emitted
  /// nothing — so `media.playerSetting` was already the new value but no
  /// listener had been told. A skip toggle therefore moved only once storage
  /// answered, which on a slow host repository reads as a switch that ignores
  /// the first tap. Optimistic, like play()/pause() in PlaybackManager.
  ///
  /// No rollback on a failed write: [Latest] swallows the error and the UI
  /// keeps the value the user chose. That is what the old code did too (it
  /// left `_state` mutated and simply never emitted), minus the silence.
  /// Bumped by every local settings write. [getPlayerSettings] compares it
  /// across its await to tell "nothing happened" from "the user changed this
  /// while I was reading" — see there.
  int _settingWrites = 0;

  void updateSetting(PlayerSetting setting) {
    final token = lifecycleToken;
    if (!token.isAlive) return;

    _settingWrites++;
    _state = _state.copyWith(playerSetting: setting);
    safeEmit(_mediaCtrl, _state, token);

    _saveSettingLatest.run(() async {
      if (!token.isAlive) return;
      await _repository.savePlayerSettings(setting);
    });
  }

  Future<void> updateAutoSkip(bool autoSkip) async {
    if (_isDisposed) return;
    updateSetting(_currentOrDefaultSetting().copyWith(autoSkip: autoSkip));
  }

  Future<void> updateSkipIntro(int skipIntro) async {
    if (_isDisposed) return;
    updateSetting(_currentOrDefaultSetting().copyWith(skipIntro: skipIntro));
  }

  Future<void> updateSkipOutro(int skipOutro) async {
    if (_isDisposed) return;
    updateSetting(_currentOrDefaultSetting().copyWith(skipOutro: skipOutro));
  }

  Future<PlayerSetting> getPlayerSettings() async {
    final token = lifecycleToken;
    final video = _state.video;
    if (!token.isAlive || video == null) {
      return PlayerSetting(videoId: 'unknown');
    }

    // A load started at initialize() and a user toggling auto-skip a moment
    // later are concurrent writers of the same field, and this one is reading
    // what was on disk BEFORE the toggle. Whichever finishes last used to win:
    // the old code happened to apply its write after the repository round
    // trip, so it usually landed second and the bug stayed invisible. Making
    // the write optimistic put it first and the stale load overwrote the
    // user's choice every time — same race, now deterministic.
    final writesBefore = _settingWrites;
    final setting = await _repository.getPlayerSettings(videoId: video.id);

    if (!token.isAlive) return setting;
    // Someone chose something while this read was in flight. It wins; this
    // value is by definition older. Still returned to the caller, which only
    // ever uses it as a starting point.
    if (_settingWrites != writesBefore) return setting;

    _state = _state.copyWith(playerSetting: setting);
    safeEmit(_mediaCtrl, _state, token);
    return setting;
  }

  // ===============================================================
  // Per-episode intro/outro markers
  // ===============================================================

  /// The repository's marker store, when it opted into one. An explicit cast
  /// because [EpisodeMarkerStore] is not a subtype of [MediaRepository] — Dart
  /// only promotes downward, so an `is` check alone wouldn't give access.
  EpisodeMarkerStore? get _markerStore {
    final repository = _repository;
    return repository is EpisodeMarkerStore
        ? repository as EpisodeMarkerStore
        : null;
  }

  Future<void> loadEpisodeMarkers() async {
    final token = lifecycleToken;
    final store = _markerStore;
    if (!token.isAlive || _state.video == null || store == null) return;

    final markers = await store.getEpisodeMarkers(videoId: _state.video!.id);
    if (!token.isAlive || markers.isEmpty) return;

    _state = _state.copyWith(
      episodeMarkers: {for (final m in markers) m.episodeIndex: m},
    );
    safeEmit(_mediaCtrl, _state, token);
  }

  /// The repository's hash store, when it opted into one. Same optional-cast
  /// shape as [_markerStore].
  EpisodeHashStore? get _hashStore {
    final repository = _repository;
    return repository is EpisodeHashStore
        ? repository as EpisodeHashStore
        : null;
  }

  /// Stored sweep hashes for the current video, keyed by episode index.
  /// Empty when no store is configured or nothing was stored yet.
  Future<Map<int, List<int>>> loadEpisodeHashes() async {
    final token = lifecycleToken;
    final store = _hashStore;
    if (!token.isAlive || _state.video == null || store == null) {
      return const {};
    }
    try {
      final hashes = await store.getEpisodeHashes(videoId: _state.video!.id);
      return token.isAlive ? hashes : const {};
    } catch (e) {
      logger.w('[MediaManager] Failed to load episode hashes: $e');
      return const {};
    }
  }

  /// Persist one episode's sweep hashes. Silently does nothing without a store
  /// — detection then works within the session only, as it did before.
  Future<void> saveEpisodeHashes(int episodeIndex, List<int> hashes) async {
    final store = _hashStore;
    if (!lifecycleToken.isAlive || _state.video == null || store == null) {
      return;
    }
    try {
      await store.saveEpisodeHashes(_state.video!.id, episodeIndex, hashes);
    } catch (e) {
      logger.w('[MediaManager] Failed to persist episode hashes: $e');
    }
  }

  /// Store markers for one episode. A lower-ranked source (a chapter probe, a
  /// detector) never clobbers what the user placed by hand — see
  /// [EpisodeMarkers.outranks].
  Future<void> updateEpisodeMarkers(EpisodeMarkers markers) async {
    final token = lifecycleToken;
    if (!token.isAlive || _state.video == null) return;

    final existing = _state.episodeMarkers[markers.episodeIndex];
    if (existing != null && !markers.outranks(existing)) return;

    _state = _state.copyWith(
      episodeMarkers: {..._state.episodeMarkers, markers.episodeIndex: markers},
    );
    safeEmit(_mediaCtrl, _state, token);

    // No store configured: markers still drive this session's skip logic, they
    // just don't outlive it.
    final store = _markerStore;
    if (store == null) return;
    try {
      await store.saveEpisodeMarkers(_state.video!.id, markers);
    } catch (e) {
      logger.w('[MediaManager] Failed to persist episode markers: $e');
    }
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
