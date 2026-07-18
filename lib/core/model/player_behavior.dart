import 'package:flutter/material.dart';

/// Behavior Configuration
@immutable
class PlayerBehavior {
  final Duration autoHideDelay;
  final Duration mouseHideDelay;
  final Duration hoverShowDelay;
  final Duration progressSaveInterval;
  final Duration bufferSize;
  final bool pauseOnWindowLoseFocus;
  final bool pauseOnMinimize;
  final bool resumeOnFocus;
  final bool showControlsOnHover;
  final bool hideMouseWhenIdle;
  final bool autoPlay;
  final bool loop;
  final bool muteOnStart;
  final double initialVolume;
  final double minBufferDuration;
  final double maxBufferDuration;
  final bool enableThumbnail;

  const PlayerBehavior({
    this.autoHideDelay = const Duration(seconds: 3),
    this.mouseHideDelay = const Duration(seconds: 2),
    this.hoverShowDelay = const Duration(milliseconds: 300),
    this.progressSaveInterval = const Duration(seconds: 5),
    this.bufferSize = const Duration(seconds: 10),
    this.pauseOnWindowLoseFocus = false,
    this.pauseOnMinimize = false,
    this.resumeOnFocus = true,
    this.showControlsOnHover = true,
    this.hideMouseWhenIdle = true,
    this.autoPlay = true,
    this.loop = false,
    this.muteOnStart = false,
    this.initialVolume = 1.0,
    this.minBufferDuration = 2.0,
    this.maxBufferDuration = 10.0,
    this.enableThumbnail = true,
  });

  PlayerBehavior copyWith({
    Duration? autoHideDelay,
    Duration? mouseHideDelay,
    Duration? hoverShowDelay,
    Duration? progressSaveInterval,
    Duration? bufferSize,
    bool? pauseOnWindowLoseFocus,
    bool? pauseOnMinimize,
    bool? resumeOnFocus,
    bool? showControlsOnHover,
    bool? hideMouseWhenIdle,
    bool? autoPlay,
    bool? loop,
    bool? muteOnStart,
    double? initialVolume,
    double? minBufferDuration,
    double? maxBufferDuration,
    bool? enableThumbnail,
  }) {
    return PlayerBehavior(
      autoHideDelay: autoHideDelay ?? this.autoHideDelay,
      mouseHideDelay: mouseHideDelay ?? this.mouseHideDelay,
      hoverShowDelay: hoverShowDelay ?? this.hoverShowDelay,
      progressSaveInterval: progressSaveInterval ?? this.progressSaveInterval,
      bufferSize: bufferSize ?? this.bufferSize,
      pauseOnWindowLoseFocus:
          pauseOnWindowLoseFocus ?? this.pauseOnWindowLoseFocus,
      pauseOnMinimize: pauseOnMinimize ?? this.pauseOnMinimize,
      resumeOnFocus: resumeOnFocus ?? this.resumeOnFocus,
      showControlsOnHover: showControlsOnHover ?? this.showControlsOnHover,
      hideMouseWhenIdle: hideMouseWhenIdle ?? this.hideMouseWhenIdle,
      autoPlay: autoPlay ?? this.autoPlay,
      loop: loop ?? this.loop,
      muteOnStart: muteOnStart ?? this.muteOnStart,
      initialVolume: initialVolume ?? this.initialVolume,
      minBufferDuration: minBufferDuration ?? this.minBufferDuration,
      maxBufferDuration: maxBufferDuration ?? this.maxBufferDuration,
      enableThumbnail: enableThumbnail ?? this.enableThumbnail,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is PlayerBehavior &&
            runtimeType == other.runtimeType &&
            autoHideDelay == other.autoHideDelay &&
            mouseHideDelay == other.mouseHideDelay &&
            hoverShowDelay == other.hoverShowDelay &&
            progressSaveInterval == other.progressSaveInterval &&
            bufferSize == other.bufferSize &&
            pauseOnWindowLoseFocus == other.pauseOnWindowLoseFocus &&
            pauseOnMinimize == other.pauseOnMinimize &&
            resumeOnFocus == other.resumeOnFocus &&
            showControlsOnHover == other.showControlsOnHover &&
            hideMouseWhenIdle == other.hideMouseWhenIdle &&
            autoPlay == other.autoPlay &&
            loop == other.loop &&
            muteOnStart == other.muteOnStart &&
            initialVolume == other.initialVolume &&
            minBufferDuration == other.minBufferDuration &&
            maxBufferDuration == other.maxBufferDuration &&
            enableThumbnail == other.enableThumbnail;
  }

  @override
  int get hashCode => Object.hashAll([
        autoHideDelay,
        mouseHideDelay,
        hoverShowDelay,
        progressSaveInterval,
        bufferSize,
        pauseOnWindowLoseFocus,
        pauseOnMinimize,
        resumeOnFocus,
        showControlsOnHover,
        hideMouseWhenIdle,
        autoPlay,
        loop,
        muteOnStart,
        initialVolume,
        minBufferDuration,
        maxBufferDuration,
        enableThumbnail,
      ]);
}
