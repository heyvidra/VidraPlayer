import 'package:flutter/material.dart';
import '../../controller/player_controller.dart';
import '../../core/state/states.dart';
import '../widget/dropdown_menu.dart';

class SpeedSelector extends StatelessWidget {
  final PlayerController controller;
  final bool showTooltip;
  final Widget Function(BuildContext context, double speed)? triggerBuilder;
  final VoidCallback? onOpen;
  final VoidCallback? onClose;
  final Alignment? alignment;
  final Offset? offset;

  const SpeedSelector({
    super.key,
    required this.controller,
    this.showTooltip = true,
    this.triggerBuilder,
    this.onOpen,
    this.onClose,
    this.alignment,
    this.offset,
  });

  @override
  Widget build(BuildContext context) {
    if (!controller.config.features.enablePlaybackSpeed) {
      return const SizedBox.shrink();
    }

    final theme = controller.config.theme;

    return StreamBuilder<AudioState>(
      stream: controller.audioStream,
      initialData: controller.audio,
      builder: (context, snapshot) {
        final audioState = snapshot.data ?? controller.audio;

        return VOptionSelector<double>(
          alignment: alignment ?? Alignment.topRight,
          offset: offset ?? const Offset(0, -10),
          tooltip: showTooltip && triggerBuilder == null
              ? controller.localization.translate('playback_speed')
              : null,
          currentLabel: '${audioState.playbackSpeed}x',
          currentValue: audioState.playbackSpeed,
          items: const [0.5, 0.75, 1.0, 1.25, 1.5, 2.0],
          itemLabelBuilder: (s) => '${s}x',
          onSelected: (s) => controller.setPlaybackSpeed(s),
          onOpen: onOpen,
          onClose: onClose,
          triggerBuilder: triggerBuilder,
          textColor: theme.iconColor,
          checkmarkColor: theme.primaryColor, // NEW
          useAnimation: true,
        );
      },
    );
  }
}
