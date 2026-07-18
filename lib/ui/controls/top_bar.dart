import 'package:flutter/material.dart';
import '../../controller/player_controller.dart';
import '../../utils/screen.dart';
import 'more_menu_parts.dart';
import '../widget/animation_button.dart';

class TopBar extends StatelessWidget {
  final PlayerController controller;

  const TopBar({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = controller.config.theme;
    final useMobileLayout = ScreenHelper.isMobileLayout(context);

    return ValueListenableBuilder<bool>(
      valueListenable: controller.isLiveListenable,
      builder: (context, isLive, _) {
        return Row(
          children: [
            if (controller.config.leading != null) ...[
              controller.config.leading!,
              const SizedBox(width: 16),
            ],
            Expanded(
              child: Text(
                controller.media.title,
                style: TextStyle(
                  color: theme.textColor,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (controller.hasNextEpisode || controller.hasPreviousEpisode) ...[
              AnimationButton(
                onTap: () => controller.toggleEpisodeList(),
                child: useMobileLayout
                    ? Icon(Icons.list, color: theme.iconColor)
                    : IconButton(
                        key: const ValueKey('top_bar_episode_list_button'),
                        icon: Icon(Icons.list, color: theme.iconColor),
                        onPressed: () {},
                      ),
              ),
            ],

            if (useMobileLayout && !isLive) ...[
              const SizedBox(width: 8),
              SettingsMenu(
                controller: controller,
                theme: theme,
                offset: const Offset(-2, 4),
                alignment: Alignment.bottomRight,
                useMobileLayout: useMobileLayout,
              ),
            ],
          ],
        );
      },
    );
  }
}
