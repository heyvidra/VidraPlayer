// controller/delegates/resume_delegate.dart

import 'dart:async';
import '../../managers/media_manager.dart';
import '../../managers/ui_manager.dart';
import '../../core/state/states.dart';
import '../../core/model/player_setting.dart';
import '../../utils/log.dart';

/// Internal delegate for handling playback resume logic from history.
///
/// This class extracts the complex resume-from-history decision making
/// from PlayerController to improve maintainability.
class ResumeDelegate {
  final MediaManager _mediaManager;
  final UIStateManager _uiManager;

  ResumeDelegate({
    required MediaManager mediaManager,
    required UIStateManager uiManager,
  }) : _mediaManager = mediaManager,
       _uiManager = uiManager;

  /// Check if playback should resume from history and handle appropriately.
  ///
  /// This method implements the smart resume logic:
  /// - If progress > 95%: Show replay dialog
  /// - If progress > 30s and < 95%: Show resume dialog
  /// - If progress < 30s: Auto-skip intro if enabled, or start from beginning
  Future<void> checkAndPromptResume({
    required int episodeIndex,
    required bool isInitialized,
    // A LIVE predicate, not a snapshot: this runs across async gaps and the
    // controller can be disposed during any of them. A captured bool could
    // never reflect that, making the "re-check after async" guards dead.
    required bool Function() isDisposed,
    required Future<void> Function(Duration, SeekSource) seek,
    required Future<void> Function() pause,
    required Future<void> Function() play,
    required PlayerSetting Function() getPlayerSetting,
    required bool autoPlay,
  }) async {
    if (isDisposed() || !isInitialized) {
      return;
    }

    // Wait for player to stabilize (reduced from 500ms for better UX)
    await Future.delayed(const Duration(milliseconds: 100));

    // Re-check state after async
    if (isDisposed() ||
        _mediaManager.state.currentEpisodeIndex != episodeIndex) {
      return;
    }

    try {
      final currentEpisode = _mediaManager.state.currentEpisode;
      if (currentEpisode == null || _mediaManager.state.video == null) {
        // if (autoPlay) play();
        return;
      }

      final history = await _mediaManager.getEpisodeHistory(episodeIndex);

      // Re-check after async
      if (isDisposed() ||
          _mediaManager.state.currentEpisodeIndex != episodeIndex) {
        return;
      }

      if (history != null) {
        final resumeState = ResumeState(
          positionMillis: history.positionMillis,
          durationMillis: history.durationMillis,
        );

        final progress = resumeState.progress;
        const int minRestoreMillis = 30000; // 30 seconds

        if (progress > 0.95) {
          // Progress > 95%: Show replay dialog
          _uiManager.hideControlsImmediately();
          _uiManager.showReplayDialog(resumeState);
          // Stay paused (fire-and-forget: dialog is already showing)
          unawaited(pause());
        } else if (history.positionMillis > minRestoreMillis) {
          // Valid mid-progress: Show resume dialog
          _uiManager.hideControlsImmediately();
          _uiManager.showResumeDialog(resumeState);
          // Stay paused (fire-and-forget: dialog is already showing)
          unawaited(pause());
        } else {
          // Progress too short: Auto-skip intro or start from beginning
          await _handleIntroSkip(
            seek: seek,
            play: play,
            getPlayerSetting: getPlayerSetting,
            autoPlay: autoPlay,
          );
        }
      } else {
        // No history: Check for intro skip
        await _handleIntroSkip(
          seek: seek,
          play: play,
          getPlayerSetting: getPlayerSetting,
          autoPlay: autoPlay,
        );
      }
    } catch (e) {
      logger.e('[ResumeDelegate] Failed to check resume playback: $e');
      // If error occurs, fallback to autoPlay
      if (autoPlay) unawaited(play());
    }
  }

  Future<void> _handleIntroSkip({
    required Future<void> Function(Duration, SeekSource) seek,
    required Future<void> Function() play,
    required PlayerSetting Function() getPlayerSetting,
    required bool autoPlay,
  }) async {
    final setting = getPlayerSetting();
    if (setting.autoSkip && setting.skipIntro > 0) {
      await seek(Duration(seconds: setting.skipIntro), SeekSource.external);
      _uiManager.showSkipIntroNotification();
    }
    if (autoPlay) await play();

    // Re-show controls AFTER playback is (re)established so the auto-hide timer
    // is armed against the now-playing state. Ordering matters: _loadEpisode
    // calls showControls() before play(), where _isPlaying is still false and
    // the hide timer no-ops — leaving the toolbar stuck visible on auto-advance
    // + intro-skip. Doing it here guarantees a fresh temporary show + timer.
    _uiManager.showControlsTemporarily();
  }
}
