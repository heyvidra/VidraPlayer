// controller/delegates/skip_delegate.dart

import 'dart:async';
import '../../managers/ui_manager.dart';
import '../../core/state/states.dart';
import '../../core/model/player_setting.dart';
import '../../utils/log.dart';

/// Internal delegate for handling auto-skip intro/outro logic.
///
/// This class extracts the auto-skip decision making from PlayerController
/// to improve maintainability.
class SkipDelegate {
  final UIStateManager _uiManager;

  SkipDelegate({required UIStateManager uiManager}) : _uiManager = uiManager;

  /// Check and handle auto-skip outro logic.
  ///
  /// Called on every position update to check if we should skip to next episode.
  /// Shows notification 5 seconds before skip, then auto-skips if enabled.
  Future<bool> checkAndSkipOutro({
    required PlaybackPositionState position,
    required PlayerSetting setting,
    required bool isSwitchingEpisode,
    required bool pendingResumeCheck,
    required bool hasNextEpisode,
    required Future<void> Function() playNextEpisode,
    required Future<void> Function() pause,
  }) async {
    final duration = position.duration.inSeconds;
    final currentPosition = position.position.inSeconds;
    final autoSkip = setting.autoSkip;
    final skipOutro = setting.skipOutro;

    if (duration <= 0 ||
        !autoSkip ||
        skipOutro <= 0 ||
        isSwitchingEpisode ||
        pendingResumeCheck) {
      return false;
    }

    final remaining = duration - currentPosition;

    if (remaining <= skipOutro) {
      // Time to skip
      _uiManager.hideSkipNotification();

      if (hasNextEpisode) {
        await playNextEpisode();
        return true; // Skipped
      } else {
        // Show replay dialog if no next episode
        _uiManager.showReplayDialog(
          ResumeState(
            positionMillis: position.position.inMilliseconds,
            durationMillis: position.duration.inMilliseconds,
          ),
        );
        await pause();
        return true; // Triggered end behavior
      }
    } else if (remaining <= skipOutro + 5 && hasNextEpisode) {
      // Show notification 5 seconds before skip
      _uiManager.showSkipOutroNotification();
      return false;
    } else {
      // Clear notification if we're outside the skip window
      if (_uiManager.currentVisibility.skipNotification ==
          SkipNotificationType.outro) {
        _uiManager.hideSkipNotification();
      }
      return false;
    }
  }

  /// Apply intro skip if enabled.
  ///
  /// Called when starting a new episode to optionally skip the intro.
  void applyIntroSkip({
    required PlayerSetting setting,
    required Future<void> Function(Duration, SeekSource) seek,
  }) {
    if (setting.autoSkip && setting.skipIntro > 0) {
      logger.d("[SkipDelegate] Applying intro skip: ${setting.skipIntro}s");
      seek(Duration(seconds: setting.skipIntro), SeekSource.external);
      _uiManager.showSkipIntroNotification();
    }
  }
}
