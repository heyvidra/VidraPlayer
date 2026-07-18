// ui/player_widget.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../controller/player_controller.dart';
import 'layers/video_surface_layer.dart';
import 'layers/gesture_detector_layer.dart';
import 'layers/buffering_indicator_layer.dart';
import 'layers/controls_overlay_layer.dart';
import 'layers/error_display_layer.dart';

/// The main video player widget for VidraPlayer.
///
/// This widget renders the video player UI using a layered architecture:
/// - [VideoSurfaceLayer]: Video display area
/// - [GestureDetectorLayer]: Background interaction (Tap/Double Tap/Hover)
/// - [BufferingIndicatorLayer]: Loading indicator
/// - [ErrorDisplayLayer]: Error display
/// - [ControlsOverlayLayer]: Playback controls and overlays (Episode list, etc.)
///
/// The widget is controlled via a [PlayerController] which must be Provide.
class VideoPlayerWidget extends StatefulWidget {
  final PlayerController controller;
  final Widget? customLoading;
  final Widget? customError;

  const VideoPlayerWidget({
    super.key,
    required this.controller,
    this.customLoading,
    this.customError,
  });

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget>
    with AutomaticKeepAliveClientMixin {
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => false;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        // Only claim the event when we actually handle it; otherwise return
        // ignored so Tab traversal, screen-reader navigation, and host-app
        // shortcuts keep working while the player is focused.
        if (!widget.controller.config.features.enableKeyboardShortcuts) {
          return KeyEventResult.ignored;
        }
        final isRepeat = event is KeyRepeatEvent;
        if (event is! KeyDownEvent && !isRepeat) {
          return KeyEventResult.ignored;
        }
        if (_handleKeyEvent(event.logicalKey, isRepeat: isRepeat)) {
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: ColoredBox(
        color: Colors.black,
        child: CustomMultiChildLayout(
          delegate: VideoPlayerLayoutDelegate(),
          children: [
            // 1. Video Display Area
            LayoutId(
              id: 'video',
              child: VideoSurfaceLayer(
                controller: widget.controller,
                customLoading: widget.customLoading,
              ),
            ),
            // 2. Background Interaction Layer
            LayoutId(
              id: 'gestures',
              child: GestureDetectorLayer(
                controller: widget.controller,
                onDoubleTap: _handleDoubleTap,
              ),
            ),
            // 3. Buffering Indicator
            LayoutId(
              id: 'indicators',
              child: BufferingIndicatorLayer(
                controller: widget.controller,
                customLoading: widget.customLoading,
              ),
            ),
            // 4. Error Display
            LayoutId(
              id: 'errors',
              child: ErrorDisplayLayer(
                controller: widget.controller,
                customError: widget.customError,
              ),
            ),
            // 5. UI Controls & Overlays
            LayoutId(
              id: 'controls',
              child: ControlsOverlayLayer(
                controller: widget.controller,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleDoubleTap(Offset localPosition) {
    if (!mounted) return;
    if (context.size == null) return;

    final width = context.size!.width;
    final isLeft = localPosition.dx < width / 2;

    if (isLeft) {
      const amount = Duration(seconds: -10);
      widget.controller.seekRelative(amount);
      widget.controller.showSeekFeedback(amount);
    } else {
      const amount = Duration(seconds: 10);
      widget.controller.seekRelative(amount);
      widget.controller.showSeekFeedback(amount);
    }
  }

  /// Keys that make sense to fire repeatedly while held (hold-to-scrub,
  /// hold-to-adjust-volume). Toggles (space/f/m/escape/speed) fire once.
  static final Set<LogicalKeyboardKey> _repeatableKeys = {
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.keyJ,
    LogicalKeyboardKey.keyL,
  };

  /// Every key the player claims on KeyDown. Repeats of these must be
  /// swallowed (reported handled without acting) — otherwise holding a
  /// consumed key leaks its auto-repeats to host Shortcuts / the OS.
  static final Set<LogicalKeyboardKey> _mappedKeys = {
    LogicalKeyboardKey.space,
    LogicalKeyboardKey.keyF,
    LogicalKeyboardKey.keyM,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.keyJ,
    LogicalKeyboardKey.keyL,
    LogicalKeyboardKey.escape,
    LogicalKeyboardKey.period,
    LogicalKeyboardKey.greater,
    LogicalKeyboardKey.comma,
    LogicalKeyboardKey.less,
  };

  /// Returns true only when the key maps to a player shortcut, so the caller
  /// can report the event as handled vs. ignored.
  bool _handleKeyEvent(LogicalKeyboardKey key, {required bool isRepeat}) {
    // Repeats of non-repeatable keys: claim without acting if we own the key
    // (its KeyDown was consumed); propagate genuinely unmapped keys.
    if (isRepeat && !_repeatableKeys.contains(key)) {
      return _mappedKeys.contains(key);
    }

    if (key == LogicalKeyboardKey.space) {
      widget.controller.handleKeyboardShortcut('space');
    } else if (key == LogicalKeyboardKey.keyF) {
      widget.controller.handleKeyboardShortcut('f');
    } else if (key == LogicalKeyboardKey.keyM) {
      widget.controller.handleKeyboardShortcut('m');
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      widget.controller.handleKeyboardShortcut('arrow_left');
    } else if (key == LogicalKeyboardKey.arrowRight) {
      widget.controller.handleKeyboardShortcut('arrow_right');
    } else if (key == LogicalKeyboardKey.arrowUp) {
      widget.controller.handleKeyboardShortcut('arrow_up');
    } else if (key == LogicalKeyboardKey.arrowDown) {
      widget.controller.handleKeyboardShortcut('arrow_down');
    } else if (key == LogicalKeyboardKey.keyJ) {
      widget.controller.handleKeyboardShortcut('j');
    } else if (key == LogicalKeyboardKey.keyL) {
      widget.controller.handleKeyboardShortcut('l');
    } else if (key == LogicalKeyboardKey.escape) {
      widget.controller.handleKeyboardShortcut('escape');
    } else if (key == LogicalKeyboardKey.period ||
        key == LogicalKeyboardKey.greater) {
      widget.controller.handleKeyboardShortcut('>');
    } else if (key == LogicalKeyboardKey.comma ||
        key == LogicalKeyboardKey.less) {
      widget.controller.handleKeyboardShortcut('<');
    } else {
      return false;
    }
    return true;
  }
}

class VideoPlayerLayoutDelegate extends MultiChildLayoutDelegate {
  @override
  void performLayout(Size size) {
    if (hasChild('video')) {
      layoutChild('video', BoxConstraints.tight(size));
      positionChild('video', Offset.zero);
    }
    if (hasChild('gestures')) {
      layoutChild('gestures', BoxConstraints.tight(size));
      positionChild('gestures', Offset.zero);
    }
    if (hasChild('indicators')) {
      layoutChild('indicators', BoxConstraints.tight(size));
      positionChild('indicators', Offset.zero);
    }
    if (hasChild('errors')) {
      layoutChild('errors', BoxConstraints.tight(size));
      positionChild('errors', Offset.zero);
    }
    if (hasChild('controls')) {
      layoutChild('controls', BoxConstraints.tight(size));
      positionChild('controls', Offset.zero);
    }
  }

  @override
  bool shouldRelayout(covariant MultiChildLayoutDelegate oldDelegate) => false;
}
