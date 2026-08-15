import 'package:flutter/material.dart';
import 'resume.dart';

/// markerHint is the one-off nudge that the progress bar has a right-click
/// menu for setting skip points — it shares this slot because it occupies the
/// same spot above the bar and never coexists with a real skip (it only fires
/// when nothing is configured).
enum SkipNotificationType {
  none,
  intro,
  outro,
  markerHint,

  /// A skip point was just placed by hand. Carries [UIVisibilityState.markerLabel]
  /// and offers an undo — setting one used to produce no visible change at all,
  /// so the only way to tell it had worked was to reopen the settings menu.
  markerSet,
}

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

  /// Human-readable description of the marker just set, e.g. "片头 01:30".
  /// Only meaningful with [SkipNotificationType.markerSet].
  final String? markerLabel;

  const UIVisibilityState({
    this.showControls = false,
    this.showMouseCursor = true,
    this.showEpisodeList = false,
    this.showResumeDialog = false,
    this.showReplayDialog = false,
    this.showErrorDialog = false,
    this.showLoadingIndicator = false,
    this.skipNotification = SkipNotificationType.none,
    this.markerLabel,
    this.resumeState,
    this.replayState,
    this.resumeHint,
    this.seekFeedback,
  });

  final ResumeState? resumeState;
  final ResumeState? replayState;

  /// The non-blocking "picked up where you left off" card.
  ///
  /// Deliberately NOT folded into [showResumeDialog]: that flag is read in a
  /// dozen places as "a modal owns the screen" — it blanks the control bars
  /// behind an IgnorePointer, swallows every keyboard shortcut, and stops
  /// periodic progress saves. A hint must do none of those things.
  final ResumeState? resumeHint;
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
    String? markerLabel,
    ResumeState? resumeState,
    ResumeState? replayState,
    ResumeState? resumeHint,
    Duration? seekFeedback,
    bool forceClearSeekFeedback = false,
    bool forceClearResumeHint = false,
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
      markerLabel: markerLabel ?? this.markerLabel,
      // Nullable fields can't be cleared via `field: null` (copyWith's ??
      // swallows it) — the forceClear flags are the explicit clear channel.
      resumeState: forceClearResumeState
          ? null
          : (resumeState ?? this.resumeState),
      replayState: forceClearReplayState
          ? null
          : (replayState ?? this.replayState),
      resumeHint: forceClearResumeHint ? null : (resumeHint ?? this.resumeHint),
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
            markerLabel == other.markerLabel &&
            resumeState == other.resumeState &&
            replayState == other.replayState &&
            resumeHint == other.resumeHint &&
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
    markerLabel,
    resumeState,
    replayState,
    resumeHint,
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

  const InteractionState({
    this.lastMouseMove,
    this.lastKeyboardInteraction,
    this.lastTouchInteraction,
    this.isMouseActive = false,
    this.isHoveringControls = false,
    this.isHoveringVideo = true,
    this.lastMousePosition,
  });

  InteractionState copyWith({
    DateTime? lastMouseMove,
    DateTime? lastKeyboardInteraction,
    DateTime? lastTouchInteraction,
    bool? isMouseActive,
    bool? isHoveringControls,
    bool? isHoveringVideo,
    Offset? lastMousePosition,
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
    );
  }
}
