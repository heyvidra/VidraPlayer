import '../../core/interfaces/media_repository.dart';
import '../../core/model/model.dart';
class MemoryMediaRepository implements MediaRepository {
  final Map<String, Map<int, EpisodeHistory>> _history = {};
  final Map<String, PlayerSetting> _settings = {};

  @override
  Future<List<EpisodeHistory>> getEpisodeHistories({
    required String videoId,
  }) async {
    final key = videoId;
    if (!_history.containsKey(key)) {
      return [];
    }
    return _history[key]!.values.toList();
  }

  @override
  Future<void> saveEpisodeHistory(
    String videoId,
    EpisodeHistory history,
  ) async {
    final key = videoId;
    if (!_history.containsKey(key)) {
      _history[key] = {};
    }
    _history[key]![history.index] = history;
  }

  @override
  Future<void> savePlayerSettings(PlayerSetting setting) async {
    final key = setting.videoId;
    _settings[key] = setting;
  }

  @override
  Future<PlayerSetting> getPlayerSettings({required String videoId}) async {
    final key = videoId;
    if (!_settings.containsKey(key)) {
      return PlayerSetting(videoId: videoId);
    }
    return _settings[key]!;
  }
}
