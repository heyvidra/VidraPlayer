import 'package:flutter/material.dart';
import '../../controller/player_controller.dart';
import '../../core/state/states.dart';
import '../widget/control_hover_region.dart';
import '../widget/toggle_icon_button.dart';

class CenterPlayButton extends StatelessWidget {
  final PlayerController controller;
  final Animation<double> opacity;
  final bool enabled;

  const CenterPlayButton({
    super.key,
    required this.controller,
    required this.opacity,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = controller.config.theme;
    return Positioned.fill(
      child: StreamBuilder<PlaybackLifecycleState>(
        stream: controller.lifecycleStream,
        initialData: controller.lifecycle,
        builder: (context, stateSnapshot) {
          final state = stateSnapshot.data ?? const PlaybackLifecycleState();
          return Center(
            child: FadeTransition(
              opacity: opacity,
              child: ControlHoverRegion(
                controller: controller,
                enabled: enabled,
                cursor: SystemMouseCursors.click,
                child: PlayPauseButton(
                  size: 80,
                  color: theme.iconColor,
                  isPlaying: state.isPlaying,
                  onTap: () {
                    controller.togglePlayPause();
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
