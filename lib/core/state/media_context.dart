import 'package:flutter/material.dart';

import '../model/model.dart';

@immutable
class MediaContextState {
  final VideoMetadata? video;
  final List<VideoEpisode> episodes;
  final int currentEpisodeIndex;
  final int currentQualityIndex;
  final List<EpisodeHistory> episodeHistory;
  final PlayerSetting? playerSetting;

  const MediaContextState({
    this.video,
    this.episodes = const [],
    this.currentEpisodeIndex = 0,
    this.currentQualityIndex = 0,
    this.episodeHistory = const [],
    this.playerSetting,
  });

  MediaContextState copyWith({
    VideoMetadata? video,
    List<VideoEpisode>? episodes,
    int? currentEpisodeIndex,
    int? currentQualityIndex,
    List<EpisodeHistory>? episodeHistory,
    PlayerSetting? playerSetting,
  }) {
    return MediaContextState(
      video: video ?? this.video,
      episodes: episodes ?? this.episodes,
      currentEpisodeIndex: currentEpisodeIndex ?? this.currentEpisodeIndex,
      currentQualityIndex: currentQualityIndex ?? this.currentQualityIndex,
      episodeHistory: episodeHistory ?? this.episodeHistory,
      playerSetting: playerSetting ?? this.playerSetting,
    );
  }

  bool get hasNextEpisode => currentEpisodeIndex < episodes.length - 1;

  bool get hasPreviousEpisode => currentEpisodeIndex > 0;

  List<VideoQuality> get availableQualities {
    if (episodes.isEmpty ||
        currentEpisodeIndex < 0 ||
        currentEpisodeIndex >= episodes.length) {
      return const [];
    }
    return episodes[currentEpisodeIndex].qualities;
  }

  VideoQuality? get currentQuality {
    final qualities = availableQualities;
    if (qualities.isEmpty) return null;
    // Clamp: a stale quality index carried across an episode with fewer
    // qualities must never RangeError (this getter is read from UI builders).
    return qualities[currentQualityIndex.clamp(0, qualities.length - 1)];
  }

  /// The playable source for the current episode + quality selection.
  /// Single source-resolution authority: playback opens exactly this.
  VideoSource? get currentSource => currentQuality?.source;

  VideoEpisode? get currentEpisode {
    if (episodes.isEmpty ||
        currentEpisodeIndex < 0 ||
        currentEpisodeIndex >= episodes.length) {
      return null;
    }
    return episodes[currentEpisodeIndex];
  }

  String get title {
    if (video == null) return '';
    if (episodes.isEmpty) return video!.title;
    return "${video!.title} - ${episodes[currentEpisodeIndex].title}";
  }

  @override
  String toString() {
    return 'MediaContextState(video: ${video?.toString()}, episodes: $episodes, currentEpisodeIndex: $currentEpisodeIndex, currentQualityIndex: $currentQualityIndex, playerSetting: $playerSetting)';
  }
}
