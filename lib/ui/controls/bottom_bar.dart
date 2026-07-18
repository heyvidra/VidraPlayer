import 'package:flutter/material.dart';
import '../../controller/player_controller.dart';
import '../../core/state/states.dart';
import 'progress_bar.dart';
import 'playback_controls.dart';
import 'time_display.dart';
import '../../utils/screen.dart';
import 'widgets/control_buttons_row.dart';

class BottomBar extends StatelessWidget {
  final PlayerController controller;

  const BottomBar({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [_buildProgressBar(), _buildControlsArea(context)],
    );
  }

  Widget _buildProgressBar() {
    final theme = controller.config.theme;
    // Position ticks are consumed inside VideoProgressBar (paint-only) — no
    // position-driven builder here, or every tick would rebuild the subtree.
    return RepaintBoundary(
      child: VideoProgressBar(
        key: const ValueKey("video_progress_bar"),
        positionListenable: controller.positionListenable,
        onSeek: (pos) => controller.seek(pos, SeekSource.userDrag),
        onSeekStart: controller.seekStart,
        onSeekEnd: controller.seekEnd,
        controller: controller,
        playedColor: theme.progressBarColor,
        bufferedColor: theme.bufferedColor,
        handleColor: theme.progressBarColor,
      ),
    );
  }

  Widget _buildControlsArea(BuildContext context) {
    final isSmall = ScreenHelper.isMediumScreen(context);
    return StreamBuilder<ViewModeState>(
      stream: controller.viewStream,
      initialData: controller.view,
      builder: (context, viewSnapshot) {
        final view = viewSnapshot.data ?? controller.view;
        return _buildControlRow(context, isSmall, view);
      },
    );
  }

  Widget _buildControlRow(
    BuildContext context,
    bool isSmall,
    ViewModeState view,
  ) {
    return Row(
      children: [
        PlaybackControls(
          key: const ValueKey('playback_controls'),
          controller: controller,
          isSmall: isSmall,
        ),
        SizedBox(width: isSmall ? 4.0 : 8.0),
        RepaintBoundary(child: TimeDisplay(controller: controller)),
        const Spacer(),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          layoutBuilder: (currentChild, previousChildren) {
            return Stack(
              alignment: Alignment.centerRight,
              children: [...previousChildren, ?currentChild],
            );
          },
          transitionBuilder: (Widget child, Animation<double> animation) {
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.1, 0),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            );
          },
          child: ControlButtonsRow(
            key: ValueKey('control_row_$isSmall'),
            isSmall: isSmall,
            controller: controller,
            view: view,
          ),
        ),
      ],
    );
  }
}
