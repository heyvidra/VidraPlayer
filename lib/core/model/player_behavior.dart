import 'package:material_ui/material_ui.dart';

/// How a video with watch history reopens.
enum ResumeMode {
  /// Pick up where they left off and say so in a corner, without taking the
  /// screen. The default: a viewer opening episode 12 for the second night
  /// running has already answered "continue?" by opening it.
  auto,

  /// Ask first, modally. What the player did before [auto] existed.
  prompt,

  /// [prompt], but the dialog resumes on its own after a few seconds.
  promptWithCountdown,
}

/// Behavior Configuration
@immutable
class PlayerBehavior {
  final Duration autoHideDelay;
  final Duration mouseHideDelay;
  final Duration hoverShowDelay;
  final bool pauseOnWindowLoseFocus;
  final bool pauseOnMinimize;
  final bool showControlsOnHover;
  final bool hideMouseWhenIdle;
  final bool autoPlay;
  final bool loop;
  final bool muteOnStart;
  final double initialVolume;
  final bool enableThumbnail;
  final ResumeMode resumeMode;

  /// Open the next episode a few seconds before this one ends, so the switch
  /// lands on a stream that is already playing-ready instead of a spinner.
  /// Two decoders exist for that stretch; a host that cannot afford it turns
  /// this off.
  final bool preloadNextEpisode;

  const PlayerBehavior({
    this.autoHideDelay = const Duration(seconds: 3),
    this.mouseHideDelay = const Duration(seconds: 2),
    this.hoverShowDelay = const Duration(milliseconds: 300),
    this.pauseOnWindowLoseFocus = false,
    this.pauseOnMinimize = false,
    this.showControlsOnHover = true,
    this.hideMouseWhenIdle = true,
    this.autoPlay = true,
    this.loop = false,
    this.muteOnStart = false,
    this.initialVolume = 1.0,
    this.enableThumbnail = true,
    this.resumeMode = ResumeMode.auto,
    this.preloadNextEpisode = true,
  });

  PlayerBehavior copyWith({
    Duration? autoHideDelay,
    Duration? mouseHideDelay,
    Duration? hoverShowDelay,
    bool? pauseOnWindowLoseFocus,
    bool? pauseOnMinimize,
    bool? showControlsOnHover,
    bool? hideMouseWhenIdle,
    bool? autoPlay,
    bool? loop,
    bool? muteOnStart,
    double? initialVolume,
    bool? enableThumbnail,
    ResumeMode? resumeMode,
    bool? preloadNextEpisode,
  }) {
    return PlayerBehavior(
      autoHideDelay: autoHideDelay ?? this.autoHideDelay,
      mouseHideDelay: mouseHideDelay ?? this.mouseHideDelay,
      hoverShowDelay: hoverShowDelay ?? this.hoverShowDelay,
      pauseOnWindowLoseFocus:
          pauseOnWindowLoseFocus ?? this.pauseOnWindowLoseFocus,
      pauseOnMinimize: pauseOnMinimize ?? this.pauseOnMinimize,
      showControlsOnHover: showControlsOnHover ?? this.showControlsOnHover,
      hideMouseWhenIdle: hideMouseWhenIdle ?? this.hideMouseWhenIdle,
      autoPlay: autoPlay ?? this.autoPlay,
      loop: loop ?? this.loop,
      muteOnStart: muteOnStart ?? this.muteOnStart,
      initialVolume: initialVolume ?? this.initialVolume,
      enableThumbnail: enableThumbnail ?? this.enableThumbnail,
      resumeMode: resumeMode ?? this.resumeMode,
      preloadNextEpisode: preloadNextEpisode ?? this.preloadNextEpisode,
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
            pauseOnWindowLoseFocus == other.pauseOnWindowLoseFocus &&
            pauseOnMinimize == other.pauseOnMinimize &&
            showControlsOnHover == other.showControlsOnHover &&
            hideMouseWhenIdle == other.hideMouseWhenIdle &&
            autoPlay == other.autoPlay &&
            loop == other.loop &&
            muteOnStart == other.muteOnStart &&
            initialVolume == other.initialVolume &&
            enableThumbnail == other.enableThumbnail &&
            resumeMode == other.resumeMode;
  }

  @override
  int get hashCode => Object.hashAll([
    autoHideDelay,
    mouseHideDelay,
    hoverShowDelay,
    pauseOnWindowLoseFocus,
    pauseOnMinimize,
    showControlsOnHover,
    hideMouseWhenIdle,
    autoPlay,
    loop,
    muteOnStart,
    initialVolume,
    enableThumbnail,
    resumeMode,
  ]);
}
