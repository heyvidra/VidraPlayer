import '../model/model.dart';

abstract class MediaRepository {
  Future<List<EpisodeHistory>> getEpisodeHistories({required String videoId});

  Future<void> saveEpisodeHistory(String videoId, EpisodeHistory history);

  Future<void> savePlayerSettings(PlayerSetting setting);
  Future<PlayerSetting> getPlayerSettings({required String videoId});
}
