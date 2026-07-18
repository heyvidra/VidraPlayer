import 'package:flutter/material.dart';
import 'resume.dart';

enum SkipNotificationType { none, intro, outro }

@immutable
class UIVisibilityState {
  final bool showControls;
  final bool showMouseCursor;
  final bool showEpisodeList;
  final bool showResumeDialog;
  final bool showReplayDialog;
  final bool showErrorDialog;
  final bool showLoadingIndicator;
  final SkipNotificationType skipNotification;

  const UIVisibilityState({
    this.showControls = false,
    this.showMouseCursor = true,
    this.showEpisodeList = false,
    this.showResumeDialog = false,
    this.showReplayDialog = false,
    this.showErrorDialog = false,
    this.showLoadingIndicator = false,
    this.skipNotification = SkipNotificationType.none,
    this.resumeState,
    this.replayState,
    this.seekFeedback,
  });

  final ResumeState? resumeState;
  final ResumeState? replayState;
  final Duration? seekFeedback;

  UIVisibilityState copyWith({
    bool? showControls,
    bool? showMouseCursor,
    bool? showEpisodeList,
    bool? showResumeDialog,
    bool? showReplayDialog,
    bool? showErrorDialog,
    bool? showLoadingIndicator,
    SkipNotificationType? skipNotification,
    ResumeState? resumeState,
    ResumeState? replayState,
    Duration? seekFeedback,
    bool forceClearSeekFeedback = false,
    bool forceClearResumeState = false,
    bool forceClearReplayState = false,
  }) {
    return UIVisibilityState(
      showControls: showControls ?? this.showControls,
      showMouseCursor: showMouseCursor ?? this.showMouseCursor,
      showEpisodeList: showEpisodeList ?? this.showEpisodeList,
      showResumeDialog: showResumeDialog ?? this.showResumeDialog,
      showReplayDialog: showReplayDialog ?? this.showReplayDialog,
      showErrorDialog: showErrorDialog ?? this.showErrorDialog,
      showLoadingIndicator: showLoadingIndicator ?? this.showLoadingIndicator,
      skipNotification: skipNotification ?? this.skipNotification,
      // Nullable fields can't be cleared via `field: null` (copyWith's ??
      // swallows it) — the forceClear flags are the explicit clear channel.
      resumeState: forceClearResumeState
          ? null
          : (resumeState ?? this.resumeState),
      replayState: forceClearReplayState
          ? null
          : (replayState ?? this.replayState),
      seekFeedback: forceClearSeekFeedback
          ? null
          : (seekFeedback ?? this.seekFeedback),
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is UIVisibilityState &&
            runtimeType == other.runtimeType &&
            showControls == other.showControls &&
            showMouseCursor == other.showMouseCursor &&
            showEpisodeList == other.showEpisodeList &&
            showResumeDialog == other.showResumeDialog &&
            showReplayDialog == other.showReplayDialog &&
            showErrorDialog == other.showErrorDialog &&
            showLoadingIndicator == other.showLoadingIndicator &&
            skipNotification == other.skipNotification &&
            resumeState == other.resumeState &&
            replayState == other.replayState &&
            seekFeedback == other.seekFeedback;
  }

  @override
  int get hashCode => Object.hash(
        showControls,
        showMouseCursor,
        showEpisodeList,
        showResumeDialog,
        showReplayDialog,
        showErrorDialog,
        showLoadingIndicator,
        skipNotification,
        resumeState,
        replayState,
        seekFeedback,
      );

  @override
  String toString() {
    return 'UIVisibilityState(showControls: $showControls, seekFeedback: $seekFeedback, skipNotification: $skipNotification)';
  }
}

/// Interaction state
@immutable
class InteractionState {
  final DateTime? lastMouseMove;
  final DateTime? lastKeyboardInteraction;
  final DateTime? lastTouchInteraction;
  final bool isMouseActive;
  final bool isHoveringControls;
  final bool isHoveringVideo;
  final Offset? lastMousePosition;
  final Duration hoverDuration;
  final Set<int> activePointers;

  const InteractionState({
    this.lastMouseMove,
    this.lastKeyboardInteraction,
    this.lastTouchInteraction,
    this.isMouseActive = false,
    this.isHoveringControls = false,
    this.isHoveringVideo = true,
    this.lastMousePosition,
    this.hoverDuration = Duration.zero,
    this.activePointers = const {},
  });

  InteractionState copyWith({
    DateTime? lastMouseMove,
    DateTime? lastKeyboardInteraction,
    DateTime? lastTouchInteraction,
    bool? isMouseActive,
    bool? isHoveringControls,
    bool? isHoveringVideo,
    Offset? lastMousePosition,
    Duration? hoverDuration,
    Set<int>? activePointers,
  }) {
    return InteractionState(
      lastMouseMove: lastMouseMove ?? this.lastMouseMove,
      lastKeyboardInteraction:
          lastKeyboardInteraction ?? this.lastKeyboardInteraction,
      lastTouchInteraction: lastTouchInteraction ?? this.lastTouchInteraction,
      isMouseActive: isMouseActive ?? this.isMouseActive,
      isHoveringControls: isHoveringControls ?? this.isHoveringControls,
      isHoveringVideo: isHoveringVideo ?? this.isHoveringVideo,
      lastMousePosition: lastMousePosition ?? this.lastMousePosition,
      hoverDuration: hoverDuration ?? this.hoverDuration,
      activePointers: activePointers ?? this.activePointers,
    );
  }
}
