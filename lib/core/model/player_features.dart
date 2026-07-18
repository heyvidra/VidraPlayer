import 'package:flutter/material.dart';

/// Feature Configuration
@immutable
class PlayerFeatures {
  final bool enableHistory;
  final bool enablePictureInPicture;
  final bool enableKeyboardShortcuts;
  final bool enableAutoPlayNext;
  final bool enableQualitySelection;
  final bool enablePlaybackSpeed;

  const PlayerFeatures({
    this.enableHistory = true,
    this.enablePictureInPicture = true,
    this.enableKeyboardShortcuts = true,
    this.enableAutoPlayNext = true,
    this.enableQualitySelection = true,
    this.enablePlaybackSpeed = true,
  });

  const PlayerFeatures.all()
    : enableHistory = true,
      enablePictureInPicture = true,
      enableKeyboardShortcuts = true,
      enableAutoPlayNext = true,
      enableQualitySelection = true,
      enablePlaybackSpeed = true;

  const PlayerFeatures.minimal()
    : enableHistory = false,
      enablePictureInPicture = false,
      enableKeyboardShortcuts = false,
      enableAutoPlayNext = false,
      enableQualitySelection = false,
      enablePlaybackSpeed = false;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is PlayerFeatures &&
            runtimeType == other.runtimeType &&
            enableHistory == other.enableHistory &&
            enablePictureInPicture == other.enablePictureInPicture &&
            enableKeyboardShortcuts == other.enableKeyboardShortcuts &&
            enableAutoPlayNext == other.enableAutoPlayNext &&
            enableQualitySelection == other.enableQualitySelection &&
            enablePlaybackSpeed == other.enablePlaybackSpeed;
  }

  @override
  int get hashCode => Object.hashAll([
        enableHistory,
        enablePictureInPicture,
        enableKeyboardShortcuts,
        enableAutoPlayNext,
        enableQualitySelection,
        enablePlaybackSpeed,
      ]);
}
