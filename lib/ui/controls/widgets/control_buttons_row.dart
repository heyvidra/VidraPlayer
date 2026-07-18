import 'package:flutter/material.dart';
import '../../../controller/player_controller.dart';
import '../../../core/state/states.dart';
import '../../widget/animation_button.dart';
import '../more_menu_parts.dart';
import '../quality_selector.dart';
import '../speed_selector.dart';

class ControlButtonsRow extends StatelessWidget {
  final bool isSmall;
  final PlayerController controller;
  final ViewModeState view;

  const ControlButtonsRow({
    super.key,
    required this.isSmall,
    required this.controller,
    required this.view,
  });

  @override
  Widget build(BuildContext context) {
    final theme = controller.config.theme;

    if (isSmall) {
      return MoreMenu(controller: controller, theme: theme, view: view);
    }

    final enablePip = controller.config.features.enablePictureInPicture;

    return ValueListenableBuilder<bool>(
      valueListenable: controller.isLiveListenable,
      builder: (context, isLive, _) {
        return Row(
          key: const ValueKey('desktop_controls_row'),
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (!view.isPip) ...[
              if (!isLive) ...[
                SettingsMenu(
                  key: const ValueKey('bottom_bar_settings_menu'),
                  controller: controller,
                  theme: theme,
                ),
                const SizedBox(width: 8),
              ],
              QualitySelector(
                key: const ValueKey('quality_selector'),
                controller: controller,
                onOpen: () => controller.showMoreMenu(),
                onClose: () => controller.hideMoreMenu(),
              ),
              const SizedBox(width: 8),
              if (!isLive) ...[
                SpeedSelector(
                  key: const ValueKey('speed_selector'),
                  controller: controller,
                  onOpen: () => controller.showMoreMenu(),
                  onClose: () => controller.hideMoreMenu(),
                ),
                const SizedBox(width: 8),
              ],
            ],

            if (enablePip && !view.isFullscreen) ...[
              AnimationButton(
                onTap: () => controller.togglePip(),
                child: IconButton(
                  key: const ValueKey('bottom_bar_pip_button'),
                  icon: Icon(
                    view.isPip
                        ? Icons.picture_in_picture
                        : Icons.picture_in_picture_alt,
                    color: theme.iconColor,
                    size: 20,
                  ),
                  onPressed: () {},
                ),
              ),
              // Add spacing if we are not in PIP mode (because fullscreen button comes next)
              if (!view.isPip) const SizedBox(width: 8),
            ],

            if (!view.isPip)
              AnimationButton(
                onTap: () => controller.toggleFullscreen(),
                child: IconButton(
                  key: const ValueKey('bottom_bar_fullscreen_button'),
                  icon: Icon(
                    view.isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                    color: theme.iconColor,
                  ),
                  onPressed: () {},
                ),
              ),
          ],
        );
      },
    );
  }
}
