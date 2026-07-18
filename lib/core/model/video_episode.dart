import 'package:flutter/material.dart';
import 'video_quality.dart';

@immutable
class VideoEpisode {
  final int index;
  final String title;
  final List<VideoQuality> qualities;
  final Widget? badge;

  const VideoEpisode({
    required this.index,
    required this.title,
    this.qualities = const [],
    this.badge,
  });
}

@immutable
class EpisodeHistory {
  final int index;
  final int positionMillis;
  final int durationMillis;

  const EpisodeHistory({
    required this.index,
    required this.positionMillis,
    required this.durationMillis,
  });

  double get watchedProgress => (positionMillis > 0)
      ? (positionMillis / durationMillis).clamp(0.0, 1.0)
      : 0.0;

  @override
  String toString() {
    return 'EpisodeHistory(index: $index, positionMillis: $positionMillis, durationMillis: $durationMillis)';
  }
}
