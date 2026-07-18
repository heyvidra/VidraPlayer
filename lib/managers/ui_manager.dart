import 'dart:async';
import 'package:flutter/material.dart';

import '../core/interfaces/window_delegate.dart';
import '../core/model/player_behavior.dart';
import '../core/state/states.dart';

/// Manages UI visibility, interaction tracking, and auto-hide behavior.
///
/// This is an internal implementation class. SDK users should interact
/// with [PlayerController] instead.
class UIStateManager {
  // ===============================================================
  // Dependencies & Configuration
  // ===============================================================

  final WindowDelegate? _windowDelegate;
  PlayerBehavior _behavior;

  // ===============================================================
  // State Streams & Controllers
  // ===============================================================

  final StreamController<UIVisibilityState> _visibilityCtrl =
      StreamController<UIVisibilityState>.broadcast();
  final StreamController<InteractionState> _interactionController =
      StreamController<InteractionState>.broadcast();
  final StreamController<ViewModeState> _viewModeCtrl =
      StreamController<ViewModeState>.broadcast();

  // Current State
  UIVisibilityState _visibility = const UIVisibilityState();
  InteractionState _interaction = const InteractionState();
  ViewModeState _viewMode = const ViewModeState();

  // Internal Flags - Window
  bool _windowHasFocus = true;
  bool _windowIsMinimized = false;

  // Internal Flags - Playback
  bool _isPlaying = false;
  bool _isInitialized = false;
  bool _isDisposed = false;
  int _hoveringControlsCount = 0;

  // ===============================================================
  // Timers
  // ===============================================================

  Timer? _autoHideTimer;
  Timer? _mouseHideTimer;
  Timer? _interactionDebounceTimer;
  Timer? _skipNotificationTimer;
  Timer? _seekFeedbackTimer;

  // ===============================================================
  // Construction & Initialization
  // ===============================================================

  UIStateManager({
    required PlayerBehavior behavior,
    WindowDelegate? windowDelegate,
  }) : _behavior = behavior,
       _windowDelegate = windowDelegate;

  // ===============================================================
  // State Accessors
  // ===============================================================

  Stream<UIVisibilityState> get visibilityStream => _visibilityCtrl.stream;
  Stream<InteractionState> get interactionStream =>
      _interactionController.stream;
  Stream<ViewModeState> get viewModeStream => _viewModeCtrl.stream;

  UIVisibilityState get currentVisibility => _visibility;
  InteractionState get currentInteraction => _interaction;
  ViewModeState get currentViewMode => _viewMode;

  // ===============================================================
  // Public Control API (Visibility)
  // ===============================================================

  /// Force show controls (e.g., user interaction)
  void showControlsForced({Duration duration = const Duration(seconds: 5)}) {
    if (_isDisposed) return;

    // A resume/replay dialog owns the screen: the control bars are
    // IgnorePointer-blocked while it's up, so showing them (e.g. a tap
    // outside the dialog card falling through to toggleControls) paints
    // visible but dead buttons.
    if (_visibility.showResumeDialog || _visibility.showReplayDialog) {
      return;
    }

    // Cancel previous timer
    _cancelAutoHideTimer();

    // Show controls and mouse cursor
    _updateVisibility(
      _visibility.copyWith(showControls: true, showMouseCursor: true),
    );

    // If duration is specified, set timer to auto hide
    if (duration > Duration.zero) {
      _autoHideTimer = Timer(duration, () {
        if (_isDisposed ||
            _visibility.showEpisodeList ||
            _visibility.showResumeDialog ||
            _visibility.showReplayDialog ||
            _visibility.showErrorDialog) {
          return;
        }

        // Only auto hide when playing and window has focus
        if (_isPlaying && _windowHasFocus && _shouldAutoHide()) {
          _hideControlsAndMouse();
        }
      });
    }
  }

  /// Show controls persistently (no auto hide)
  void showControlsPersistently() {
    if (_isDisposed) return;
    _showControlsPersistently(); // internal impl
  }

  /// Show controls temporarily (default 3 seconds auto hide)
  void showControlsTemporarily() {
    // print("[UI DEBUG] [UIManager ${identityHashCode(this)}] showControlsTemporarily"); // Verbose
    if (_isDisposed) return;
    _showControlsTemporarily(); // internal impl
  }

  /// Hide controls and mouse immediately
  void hideControlsImmediately() {
    if (_isDisposed) return;
    _hideControlsAndMouse();
  }

  /// Toggle control visibility
  void toggleControls() {
    if (_isDisposed) return;

    // Dialog owns the screen — a video-area tap must neither summon dead
    // controls nor hide anything behind the dialog.
    if (_visibility.showResumeDialog || _visibility.showReplayDialog) {
      return;
    }

    if (_visibility.showControls) {
      hideControlsImmediately();
    } else {
      showControlsForced();
    }
  }

  /// Set control visibility directly
  void setControlsVisible(bool visible, {bool keepMouse = true}) {
    if (_isDisposed) return;

    _updateVisibility(
      _visibility.copyWith(
        showControls: visible,
        showMouseCursor: keepMouse ? true : _visibility.showMouseCursor,
      ),
    );

    if (visible) {
      _cancelAutoHideTimer();
      if (_isPlaying && _windowHasFocus) {
        _resetAutoHideTimer();
      }
    }
  }

  /// Refresh UI state (trigger rebuild). Emits directly because the new value
  /// equals the current one — the equality guard in [_updateVisibility] would
  /// otherwise swallow theme/locale/config-driven repaints.
  void refresh() {
    if (_isDisposed) return;
    _emitVisibility();
  }

  void updateBehavior(PlayerBehavior behavior) {
    if (_isDisposed) return;
    _behavior = behavior;
  }

  // ===============================================================
  // Event Handlers (Mouse, Touch, Keyboard)
  // ===============================================================

  /// Handle mouse move
  void handleMouseMove(Offset position) {
    if (_isDisposed) return;

    final now = DateTime.now();

    _interaction = _interaction.copyWith(
      lastMouseMove: now,
      isMouseActive: true,
      isHoveringVideo: true,
      lastMousePosition: position,
    );

    _emitInteraction();

    // Reset auto-hide timer
    _resetAutoHideTimer();

    // Show mouse cursor
    _showMouseTemporarily();

    // If playing and window has focus, show controls
    if (_shouldShowControlsOnMouseMove()) {
      _showControlsTemporarily();
    }
  }

  /// Handle mouse enter controls
  void handleMouseEnterControls() {
    if (_isDisposed) return;

    _hoveringControlsCount++;
    if (!_interaction.isHoveringControls) {
      _interaction = _interaction.copyWith(isHoveringControls: true);
      _emitInteraction();
    }

    _cancelAutoHideTimer();

    // Immediately show controls (if should show)
    if (_shouldShowControlsOnHover()) {
      _showControlsTemporarily();
    }
  }

  /// Handle mouse leave controls
  void handleMouseLeaveControls() {
    if (_isDisposed) return;

    if (_hoveringControlsCount > 0) {
      _hoveringControlsCount--;
    }

    if (_hoveringControlsCount > 0) return;

    if (_interaction.isHoveringControls) {
      _interaction = _interaction.copyWith(isHoveringControls: false);
      _emitInteraction();
    }

    if (_isPlaying && _windowHasFocus) {
      _resetAutoHideTimer();
    }
  }

  /// Handle mouse enter video
  void handleMouseEnterVideo() {
    if (_isDisposed) return;
    _interaction = _interaction.copyWith(isHoveringVideo: true);
    _emitInteraction();
  }

  /// Handle mouse leave video
  void handleMouseLeaveVideo() {
    if (_isDisposed) return;

    _interaction = _interaction.copyWith(isHoveringVideo: false);
    _emitInteraction();

    // If mouse completely leaves player area, hide mouse cursor
    if (!_interaction.isHoveringControls) {
      _hideMouse();
    }
  }

  /// Handle keyboard interaction
  void handleKeyboardInteraction() {
    if (_isDisposed) return;

    final now = DateTime.now();

    _interaction = _interaction.copyWith(lastKeyboardInteraction: now);

    _emitInteraction();

    // Show controls
    _showControlsTemporarily();
    _resetAutoHideTimer();
  }

  // ===============================================================
  // Window & Lifecycle Logic
  // ===============================================================

  void updateWindowState({bool? hasFocus, bool? isMinimized}) {
    if (_isDisposed) return;

    bool changed = false;
    if (hasFocus != null && hasFocus != _windowHasFocus) {
      _windowHasFocus = hasFocus;
      changed = true;
    }
    if (isMinimized != null && isMinimized != _windowIsMinimized) {
      _windowIsMinimized = isMinimized;
      changed = true;
    }

    if (changed) {
      _evaluateVisibility();
    }
  }

  void updatePlaybackState({bool? isPlaying, bool? isInitialized}) {
    if (_isDisposed) return;

    bool changed = false;
    if (isPlaying != null && isPlaying != _isPlaying) {
      _isPlaying = isPlaying;
      changed = true;
    }
    if (isInitialized != null && isInitialized != _isInitialized) {
      _isInitialized = isInitialized;
      changed = true;
    }

    if (changed) {
      _evaluateVisibility();
      return;
    }

    // Backstop: a "playing" report that isn't a state change (isPlaying was
    // already true) still needs to re-arm the auto-hide timer if controls are
    // visible without an active timer — otherwise a toolbar shown while the
    // timer happened to be cancelled stays stuck visible. Guarded so idle
    // playing ticks no-op.
    if (isPlaying == true &&
        _visibility.showControls &&
        (_autoHideTimer == null || !_autoHideTimer!.isActive)) {
      _evaluateVisibility();
    }
  }

  void handleFullscreenToggle() {
    if (_isDisposed || _windowDelegate == null) return;

    _evaluateVisibility();

    if (_viewMode.isFullscreen) {
      _windowDelegate.exitFullscreen();
    } else {
      _windowDelegate.enterFullscreen();
    }
    _viewMode = _viewMode.copyWith(isFullscreen: !_viewMode.isFullscreen);
    _viewModeCtrl.add(_viewMode);
  }

  /// Absolutely set the view mode from an authoritative source (native
  /// fullscreen/PiP callbacks, host notifications). Unlike the toggle
  /// handlers, this does NOT drive the WindowDelegate — it reconciles our
  /// optimistic state with what the system actually did (e.g. the user
  /// pressed Esc / the green traffic-light button / swiped PiP away).
  void setViewMode({bool? isFullscreen, bool? isPip}) {
    if (_isDisposed) return;

    final next = _viewMode.copyWith(isFullscreen: isFullscreen, isPip: isPip);
    if (next.isFullscreen == _viewMode.isFullscreen &&
        next.isPip == _viewMode.isPip) {
      return;
    }
    _viewMode = next;
    if (!_viewModeCtrl.isClosed) {
      _viewModeCtrl.add(_viewMode);
    }
    _evaluateVisibility();
  }

  void handlePictureInPicture() {
    if (_isDisposed || _windowDelegate == null) return;

    if (!_viewMode.isPip) {
      _hideAllUI();
    } else {
      _evaluateVisibility();
    }
    if (_viewMode.isPip) {
      _windowDelegate.exitPip();
    } else {
      _windowDelegate.enterPip();
    }
    _viewMode = _viewMode.copyWith(isPip: !_viewMode.isPip);
    _viewModeCtrl.add(_viewMode);
  }

  // ===============================================================
  // Panel & Dialog Management
  // ===============================================================

  void showResumeDialog(ResumeState state) {
    if (_isDisposed) return;
    _updateVisibility(
      _visibility.copyWith(
        showResumeDialog: true,
        showControls: false,
        showMouseCursor: false,
        resumeState: state,
      ),
    );
  }

  void hideResumeDialog() {
    if (_isDisposed) return;
    _updateVisibility(
      _visibility.copyWith(
        showResumeDialog: false,
        forceClearResumeState: true,
      ),
    );
  }

  void showReplayDialog(ResumeState state) {
    if (_isDisposed) return;
    _updateVisibility(
      _visibility.copyWith(
        showReplayDialog: true,
        showControls: false,
        showMouseCursor: true,
        replayState: state,
      ),
    );
  }

  void hideReplayDialog() {
    if (_isDisposed) return;
    _updateVisibility(
      _visibility.copyWith(
        showReplayDialog: false,
        forceClearReplayState: true,
      ),
    );
  }

  void showSkipIntroNotification() {
    if (_isDisposed) return;

    _skipNotificationTimer?.cancel();
    _updateVisibility(
      _visibility.copyWith(skipNotification: SkipNotificationType.intro),
    );

    _skipNotificationTimer = Timer(const Duration(seconds: 3), () {
      hideSkipNotification();
    });
  }

  void showSkipOutroNotification() {
    if (_isDisposed) return;
    _updateVisibility(
      _visibility.copyWith(skipNotification: SkipNotificationType.outro),
    );
  }

  void hideSkipNotification() {
    if (_isDisposed) return;

    _skipNotificationTimer?.cancel();
    if (_visibility.skipNotification != SkipNotificationType.none) {
      _updateVisibility(
        _visibility.copyWith(skipNotification: SkipNotificationType.none),
      );
    }
  }

  void showEpisodeList() {
    if (_isDisposed) return;
    _updateVisibility(
      _visibility.copyWith(
        showEpisodeList: true,
        showControls: true,
        showMouseCursor: true,
      ),
    );
    _cancelAutoHideTimer();
  }

  void hideEpisodeList() {
    if (_isDisposed) return;
    _updateVisibility(_visibility.copyWith(showEpisodeList: false));
    if (_isPlaying && _windowHasFocus) {
      _resetAutoHideTimer();
    }
  }

  // Open dropdown menus (settings/quality/speed). While any is open the
  // auto-hide timer must stay disarmed: the menu lives in the root overlay
  // with a full-screen close barrier, so hiding the controls underneath it
  // leaves an invisible tap-eater on screen. A count (not a bool) because
  // menus nest (MoreMenu → QualitySelector).
  int _openMenuCount = 0;

  void showMoreMenu() {
    if (_isDisposed) return;
    _openMenuCount++;
    _cancelAutoHideTimer();
  }

  void hideMoreMenu() {
    if (_isDisposed) return;
    if (_openMenuCount > 0) _openMenuCount--;
    _resetAutoHideTimer();
  }

  void showSeekFeedback(Duration amount) {
    if (_isDisposed) return;

    _seekFeedbackTimer?.cancel();

    // Accumulate if there's an existing feedback that hasn't expired
    final current = _visibility.seekFeedback ?? Duration.zero;
    final total = current + amount;

    // If total cancels out to zero, clear feedback
    if (total.inSeconds == 0) {
      _updateVisibility(_visibility.copyWith(forceClearSeekFeedback: true));
      return;
    }

    _updateVisibility(_visibility.copyWith(seekFeedback: total));

    // Reset timer (slightly longer to allow reading accumulated value)
    _seekFeedbackTimer = Timer(const Duration(milliseconds: 1000), () {
      if (_isDisposed) return;
      _updateVisibility(_visibility.copyWith(forceClearSeekFeedback: true));
    });
  }

  // ===============================================================
  // Private Helper Methods
  // ===============================================================

  void _showMouseTemporarily() {
    if (_isDisposed || !_behavior.hideMouseWhenIdle) return;

    _mouseHideTimer?.cancel();

    // 显示鼠标指针
    if (!_visibility.showMouseCursor) {
      _updateVisibility(_visibility.copyWith(showMouseCursor: true));
    }

    // 设置隐藏计时
    _mouseHideTimer = Timer(_behavior.mouseHideDelay, () {
      if (_isDisposed) return;

      // Reset mouse active state when timer fires
      _interaction = _interaction.copyWith(isMouseActive: false);
      _emitInteraction();

      // 只有在播放中、且控制面板隐藏时才隐藏鼠标
      if (_isPlaying && !_visibility.showControls) {
        _updateVisibility(_visibility.copyWith(showMouseCursor: false));
      }
    });
  }

  void _hideMouse() {
    if (_isDisposed) return;

    _mouseHideTimer?.cancel();

    if (_visibility.showMouseCursor && _behavior.hideMouseWhenIdle) {
      _updateVisibility(_visibility.copyWith(showMouseCursor: false));
    }
  }

  void _showControlsTemporarily() {
    if (_isDisposed) return;

    // 取消之前的debounce计时器
    _interactionDebounceTimer?.cancel();

    // 使用防抖防止频繁更新
    _interactionDebounceTimer = Timer(const Duration(milliseconds: 50), () {
      if (_isDisposed) return;

      // While a resume/replay dialog owns the screen the control bars are
      // IgnorePointer-blocked — showing them (e.g. a keypress during the
      // startup resume prompt) would paint visible but dead buttons.
      if (_visibility.showResumeDialog || _visibility.showReplayDialog) {
        return;
      }

      _updateVisibility(
        _visibility.copyWith(showControls: true, showMouseCursor: true),
      );

      _resetAutoHideTimer();
    });
  }

  void _showControlsPersistently() {
    if (_isDisposed) return;

    _updateVisibility(
      _visibility.copyWith(showControls: true, showMouseCursor: true),
    );
    _cancelAutoHideTimer();
  }

  void _hideControlsAndMouse() {
    if (_isDisposed) return;

    _updateVisibility(
      _visibility.copyWith(showControls: false, showMouseCursor: false),
    );
    _cancelAutoHideTimer();
  }

  void _hideAllUI() {
    if (_isDisposed) return;

    _updateVisibility(const UIVisibilityState());

    _cancelAutoHideTimer();
    _mouseHideTimer?.cancel();
    _interactionDebounceTimer?.cancel();
    _seekFeedbackTimer?.cancel();
  }

  bool _shouldShowControlsOnMouseMove() {
    return _behavior.showControlsOnHover && _isPlaying;
  }

  bool _shouldShowControlsOnHover() {
    return _behavior.showControlsOnHover &&
        _isPlaying &&
        !_visibility.showControls;
  }

  bool _shouldAutoHide() {
    // 检查是否应该自动隐藏
    final interactionTime = _getLastInteractionTime();
    if (interactionTime != null) {
      final timeSinceInteraction = DateTime.now().difference(interactionTime);
      return timeSinceInteraction > _behavior.autoHideDelay;
    }

    // 根据状态判断 (不再强制要求 _windowHasFocus)
    return _isPlaying &&
        !_visibility.showEpisodeList &&
        !_visibility.showResumeDialog &&
        !_visibility.showErrorDialog &&
        !_interaction.isHoveringControls; // Don't hide if hovering controls
  }

  DateTime? _getLastInteractionTime() {
    final times = [
      _interaction.lastMouseMove,
      _interaction.lastKeyboardInteraction,
      _interaction.lastTouchInteraction,
    ].whereType<DateTime>();

    // Find the latest DateTime
    return times.isNotEmpty
        ? times.reduce((a, b) => a.isAfter(b) ? a : b)
        : null;
  }

  void _evaluateVisibility() {
    final bool isMin = _windowIsMinimized;
    final bool isPip = _viewMode.isPip;

    if (_isDisposed) return;

    // 1. Critical visibility blockers (Minimized)
    // In PiP mode, we no longer hide everything immediately if controls are visible.
    // This allows hover-triggered visibility to persist.
    //
    // Guard: an open dropdown menu anchors its overlay to a control button via
    // a LayerLink. _hideAllUI collapses the control bars (the button stops
    // painting), which strands the still-open menu at the top-left corner
    // (CompositedTransformFollower falls back to Offset.zero when its leader is
    // gone). A spurious "minimized" — e.g. a transient host window-occlusion
    // event — would then visibly throw the menu into the corner. Hold the hide
    // while a menu is open; it re-evaluates when the menu closes.
    if (isMin && _openMenuCount == 0) {
      _hideAllUI();
      return;
    }
    if (isMin) {
      return;
    }

    if (isPip &&
        !_visibility.showControls &&
        !_visibility.showResumeDialog &&
        !_visibility.showReplayDialog &&
        !_visibility.showErrorDialog) {
      _hideAllUI();
      return;
    }

    // 2. Not initialized
    if (!_isInitialized) {
      _hideControlsAndMouse();
      return;
    }

    // 3. Status-based persistence (Paused)
    // Buffering deliberately does NOT force controls up: a mid-playback stall
    // is transient, the spinner already signals it, and popping the toolbar
    // cancels the auto-hide timer that nothing reliably re-arms afterwards.
    if (!_isPlaying) {
      // Resume/replay dialogs own the screen: they set showControls=false and
      // the control bars are IgnorePointer-blocked while a dialog flag is up,
      // so re-asserting them here would paint fully visible but pointer-dead
      // controls behind the dialog.
      if (!_visibility.showResumeDialog && !_visibility.showReplayDialog) {
        _showControlsPersistently();
      }
      return;
    }

    // 4. Playback state (Playing)
    if (_isPlaying) {
      // Ensure auto-hide is running if controls are visible.
      // In PiP mode, we don't strictly require window focus to start the timer
      // because the user might be clicking the small window which quickly loses focus.
      if (_windowHasFocus || isPip) {
        if (_autoHideTimer == null || !_autoHideTimer!.isActive) {
          _resetAutoHideTimer();
        }
      } else {
        // Playing but background - usually allow it to hide if it was already hiding,
        // but don't force it to hide immediately unless it's a specific behavior
        // If we want it to hide in background, we'd call _hideControlsAndMouse() here.
        // But usually we just let the previous timer finish.
      }
    }
  }

  void _resetAutoHideTimer() {
    _autoHideTimer?.cancel();

    if (_isDisposed || !_isPlaying) {
      return;
    }

    // Every re-arm path (mouse move, updatePlaybackState backstop,
    // _evaluateVisibility) funnels through here, so this single guard keeps
    // the timer disarmed for the whole menu-open window.
    if (_openMenuCount > 0) {
      return;
    }

    if (_interaction.isHoveringControls) {
      return;
    }

    if (_visibility.showEpisodeList ||
        _visibility.showResumeDialog ||
        _visibility.showReplayDialog ||
        _visibility.showErrorDialog) {
      return;
    }

    final delay = _viewMode.isFullscreen
        ? Duration(seconds: _behavior.autoHideDelay.inSeconds ~/ 2)
        : _behavior.autoHideDelay;

    _autoHideTimer = Timer(delay, () {
      if (_isDisposed || !_isPlaying) {
        return;
      }

      // 1. If hovering controls, NEVER hide. Reset timer and wait.
      if (_interaction.isHoveringControls) {
        _resetAutoHideTimer();
        return;
      }

      // 2. Check if there was recent interaction (debounce)
      final lastInteraction = _getLastInteractionTime();
      if (lastInteraction != null) {
        final timeSinceInteraction = DateTime.now().difference(lastInteraction);
        if (timeSinceInteraction < delay) {
          _resetAutoHideTimer();
          return;
        }
      }

      // 3. Hide
      _hideControlsAndMouse();
    });
  }

  void _cancelAutoHideTimer() {
    _autoHideTimer?.cancel();
  }

  void _updateVisibility(UIVisibilityState newVisibility) {
    if (_isDisposed || _visibility == newVisibility) return;

    if (_visibility.showControls && !newVisibility.showControls) {
      _clearControlsHoverState();
    }

    _visibility = newVisibility;
    _emitVisibility();
  }

  void _emitVisibility() {
    if (_isDisposed) return;
    _visibilityCtrl.add(_visibility);
  }

  void _emitInteraction() {
    if (_isDisposed) return;
    _interactionController.add(_interaction);
  }

  void _clearControlsHoverState() {
    _hoveringControlsCount = 0;
    if (!_interaction.isHoveringControls) return;

    _interaction = _interaction.copyWith(isHoveringControls: false);
    _emitInteraction();
  }

  void clearAllTimers() {
    _autoHideTimer?.cancel();
    _mouseHideTimer?.cancel();
    _interactionDebounceTimer?.cancel();
    _seekFeedbackTimer?.cancel();
  }

  // ===============================================================
  // Disposal
  // ===============================================================

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;

    // Restore host window/view state so disposing while fullscreen or in PiP
    // doesn't strand the host app locked in that mode (e.g. landscape).
    final delegate = _windowDelegate;
    if (delegate != null) {
      if (_viewMode.isFullscreen) {
        delegate.exitFullscreen().catchError((_) {});
      }
      if (_viewMode.isPip) {
        delegate.exitPip().catchError((_) {});
      }
    }

    clearAllTimers();
    _skipNotificationTimer?.cancel();

    _visibilityCtrl.close();
    _interactionController.close();

    _viewModeCtrl.close();
  }
}
