import '../model/model.dart';

abstract class MediaRepository {
  Future<List<EpisodeHistory>> getEpisodeHistories({required String videoId});

  Future<void> saveEpisodeHistory(String videoId, EpisodeHistory history);

  Future<void> savePlayerSettings(PlayerSetting setting);
  Future<PlayerSetting> getPlayerSettings({required String videoId});
}

/// Optional persistence for per-episode intro/outro markers.
///
/// Deliberately NOT part of [MediaRepository]: `implements` demands every
/// member, so adding methods there would break every existing repository.
/// Implement both interfaces to have markers survive restarts; implement only
/// [MediaRepository] and markers still work for the session, they just aren't
/// stored.
///
/// ```dart
/// class MyRepo implements MediaRepository, EpisodeMarkerStore { ... }
/// ```
abstract class EpisodeMarkerStore {
  Future<List<EpisodeMarkers>> getEpisodeMarkers({required String videoId});

  Future<void> saveEpisodeMarkers(String videoId, EpisodeMarkers markers);
}
