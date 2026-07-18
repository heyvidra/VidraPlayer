import 'package:flutter/material.dart';
import '../../controller/player_controller.dart';
import '../../core/state/states.dart';
import '../../core/model/video_quality.dart';
import '../widget/dropdown_menu.dart';

class QualitySelector extends StatelessWidget {
  final PlayerController controller;
  final bool showTooltip;
  final Widget Function(BuildContext context, VideoQuality? currentQuality)?
  triggerBuilder;

  final VoidCallback? onOpen;
  final VoidCallback? onClose;
  final Alignment? alignment;
  final Offset? offset;

  const QualitySelector({
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
    if (!controller.config.features.enableQualitySelection ||
        controller.media.availableQualities.length < 2) {
      return const SizedBox.shrink();
    }

    final theme = controller.config.theme;

    return StreamBuilder<MediaContextState>(
      stream: controller.mediaStream,
      initialData: controller.media,
      builder: (context, snapshot) {
        final mediaState = snapshot.data ?? controller.media;

        if (mediaState.availableQualities.isEmpty) {
          return const SizedBox.shrink();
        }
        return VOptionSelector<VideoQuality>(
          alignment: alignment ?? Alignment.topRight,
          offset: offset ?? const Offset(0, -10),
          tooltip: showTooltip && triggerBuilder == null
              ? controller.localization.translate('quality')
              : null,
          currentLabel: mediaState.currentQuality?.label ??
              controller.localization.translate('auto'),
          currentValue: mediaState.currentQuality!,
          items: mediaState.availableQualities,
          itemLabelBuilder: (q) => q.label,
          onSelected: (q) {
            final index = mediaState.availableQualities.indexOf(q);
            if (index != -1) {
              controller.switchQuality(index);
            }
          },
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
