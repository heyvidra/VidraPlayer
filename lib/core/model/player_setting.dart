import 'package:flutter/material.dart';

@immutable
class PlayerSetting {
  final String videoId;
  final bool autoSkip;
  final int skipIntro;
  final int skipOutro;

  const PlayerSetting({
    required this.videoId,
    this.autoSkip = true,
    this.skipIntro = 0,
    this.skipOutro = 0,
  });

  PlayerSetting copyWith({
    String? videoId,
    bool? autoSkip,
    int? skipIntro,
    int? skipOutro,
  }) {
    return PlayerSetting(
      videoId: videoId ?? this.videoId,
      autoSkip: autoSkip ?? this.autoSkip,
      skipIntro: skipIntro ?? this.skipIntro,
      skipOutro: skipOutro ?? this.skipOutro,
    );
  }

  @override
  String toString() {
    return 'PlayerSetting(videoId: $videoId, autoSkip: $autoSkip, skipIntro: $skipIntro, skipOutro: $skipOutro)';
  }
}
