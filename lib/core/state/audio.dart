import 'package:flutter/material.dart';

@immutable
class AudioState {
  final double volume;
  final bool isMuted;
  final double playbackSpeed;

  const AudioState({
    this.volume = 1.0,
    this.isMuted = false,
    this.playbackSpeed = 1.0,
  });

  AudioState copyWith({double? volume, bool? isMuted, double? playbackSpeed}) {
    return AudioState(
      volume: volume ?? this.volume,
      isMuted: isMuted ?? this.isMuted,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
    );
  }
}
