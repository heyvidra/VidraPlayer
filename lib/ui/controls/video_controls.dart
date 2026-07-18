import 'package:flutter/material.dart';
import 'package:vidra_player/core/state/states.dart';
import 'package:vidra_player/utils/screen.dart';
import '../../controller/player_controller.dart';
import 'desktop_controls.dart';
import 'mobile_controls.dart';

/// Video control panel: Unifies animation state management to ensure animation controller stability when switching between layouts (Desktop/Mobile)
class VideoControls extends StatefulWidget {
  final PlayerController controller;
  final UIVisibilityState visibility;

  const VideoControls({
    super.key,
    required this.controller,
    required this.visibility,
  });

  @override
  State<VideoControls> createState() => _VideoControlsState();
}

class _VideoControlsState extends State<VideoControls>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _animation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    if (widget.visibility.showControls) {
      _animationController.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(VideoControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visibility.showControls != oldWidget.visibility.showControls) {
      if (widget.visibility.showControls) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (ScreenHelper.isMobileLayout(context)) {
      return MobileVideoControls(
        controller: widget.controller,
        visibility: widget.visibility,
        animation: _animation,
      );
    }

    return DesktopVideoControls(
      controller: widget.controller,
      visibility: widget.visibility,
      animation: _animation,
    );
  }
}
