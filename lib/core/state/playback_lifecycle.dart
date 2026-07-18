import 'package:flutter/material.dart';

import '../model/model.dart';

@immutable
class PlaybackLifecycleState {
  final PlaybackStatus status; // playing / paused / stopped
  final bool isInitialized;
  final bool isPlaying;
  final bool wasPlayingBeforeSeek;
  final int? videoWidth;
  final int? videoHeight;

  const PlaybackLifecycleState({
    this.status = PlaybackStatus.idle,
    this.isInitialized = false,
    this.isPlaying = false,
    this.wasPlayingBeforeSeek = false,
    this.videoWidth,
    this.videoHeight,
  });

  PlaybackLifecycleState copyWith({
    PlaybackStatus? status,
    bool? isInitialized,
    bool? isPlaying,
    bool? wasPlayingBeforeSeek,
    int? videoWidth,
    int? videoHeight,
  }) {
    return PlaybackLifecycleState(
      status: status ?? this.status,
      isInitialized: isInitialized ?? this.isInitialized,
      isPlaying: isPlaying ?? this.isPlaying,
      wasPlayingBeforeSeek: wasPlayingBeforeSeek ?? this.wasPlayingBeforeSeek,
      videoWidth: videoWidth ?? this.videoWidth,
      videoHeight: videoHeight ?? this.videoHeight,
    );
  }

  double get aspectRatio {
    if (!isInitialized ||
        videoHeight == null ||
        videoWidth == null ||
        videoHeight == 0) {
      return 16 / 9;
    }
    return videoWidth!.toDouble() / videoHeight!.toDouble();
  }

  @override
  String toString() {
    return 'PlaybackLifecycleState{status: $status, isInitialized: $isInitialized, isPlaying: $isPlaying, wasPlayingBeforeSeek: $wasPlayingBeforeSeek}';
  }
}
