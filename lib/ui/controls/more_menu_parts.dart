import 'package:flutter/material.dart';
import '../../controller/player_controller.dart';
import '../../core/model/model.dart';
import '../../core/state/states.dart';
import '../widget/dropdown_menu.dart';
import 'quality_selector.dart';
import 'speed_selector.dart';

class SettingsMenu extends StatelessWidget {
  final PlayerController controller;
  final PlayerUITheme theme;
  final bool isMoreMenu;
  final Offset? offset;
  final Alignment? alignment;
  final bool useMobileLayout;

  const SettingsMenu({
    super.key,
    required this.controller,
    required this.theme,
    this.isMoreMenu = false,
    this.offset,
    this.alignment,
    this.useMobileLayout = false,
  });

  @override
  Widget build(BuildContext context) {
    return VMenuSelector(
      menuWidth: 280,
      offset:
          offset ?? (isMoreMenu ? const Offset(-10, 0) : const Offset(0, -10)),
      alignment:
          alignment ?? (isMoreMenu ? Alignment.centerLeft : Alignment.topRight),
      tooltip: controller.localization.translate('settings'),
      onOpen: () {
        if (!isMoreMenu) controller.showMoreMenu();
      },
      onClose: () {
        if (!isMoreMenu) controller.hideMoreMenu();
      },
      useAnimation: true,
      child: isMoreMenu
          ? PlayerMenuItem(
              leading: const Icon(Icons.settings),
              text: controller.localization.translate('settings'),
              theme: theme,
            )
          : useMobileLayout
          ? Icon(Icons.settings, color: theme.iconColor)
          : IconButton(
              icon: Icon(Icons.settings, color: theme.iconColor),
              // tooltip: controller.localization.translate('more'),
              onPressed: () {}, // Handled by AnimationButton -> VDropdownMenu
            ),
      menuBuilder: (context, close) {
        return [
          StreamBuilder<MediaContextState>(
            stream: controller.mediaStream,
            initialData: controller.media,
            builder: (context, snapshot) {
              final setting =
                  snapshot.data?.playerSetting ??
                  PlayerSetting(videoId: controller.media.video!.id);
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PlayerMenuToggleItem(
                    leading: const Icon(Icons.skip_next),
                    text: controller.localization.translate(
                      'auto_skip_opening',
                    ),
                    value: setting.autoSkip,
                    onChanged: (val) {
                      controller.updateAutoSkip(val);
                    },
                    theme: theme,
                  ),
                  PlayerMenuAdjustmentItem(
                    leading: const Icon(Icons.start),
                    text: controller.localization.translate('skip_opening'),
                    value: setting.skipIntro,
                    suffix: 's',
                    onIncrement: () {
                      controller.updateSkipIntro(setting.skipIntro + 5);
                    },
                    onDecrement: () {
                      if (setting.skipIntro > 0) {
                        controller.updateSkipIntro(setting.skipIntro - 5);
                      }
                    },
                    theme: theme,
                  ),
                  PlayerMenuAdjustmentItem(
                    leading: const Icon(Icons.last_page),
                    text: controller.localization.translate('skip_ending'),
                    value: setting.skipOutro,
                    suffix: 's',
                    onIncrement: () {
                      controller.updateSkipOutro(setting.skipOutro + 5);
                    },
                    onDecrement: () {
                      if (setting.skipOutro > 0) {
                        controller.updateSkipOutro(setting.skipOutro - 5);
                      }
                    },
                    theme: theme,
                  ),
                ],
              );
            },
          ),
        ];
      },
    );
  }
}

class MoreMenu extends StatelessWidget {
  final PlayerController controller;
  final PlayerUITheme theme;
  final ViewModeState? view;
  final Offset offset;
  final Alignment alignment;

  const MoreMenu({
    super.key,
    required this.controller,
    required this.theme,
    this.view,
    this.offset = const Offset(0, -10),
    this.alignment = Alignment.topRight,
  });

  @override
  Widget build(BuildContext context) {
    return VDropdownMenu(
      menuWidth: 160,
      offset: offset,
      alignment: alignment,
      theme: theme,
      useAnimation: true,
      child: IconButton(
        icon: Icon(Icons.more_vert, color: theme.iconColor),
        // tooltip: controller.localization.translate('more'),
        onPressed: () {}, // Handled by AnimationButton -> VDropdownMenu
      ),
      onOpen: () => controller.showMoreMenu(),
      onClose: () => controller.hideMoreMenu(),
      menuBuilder: (context, close) {
        final currentView = view ?? controller.view;
        final pip = currentView.isPip;
        final fullscreen = currentView.isFullscreen;

        return [
          if (!pip)
            ValueListenableBuilder<bool>(
              valueListenable: controller.isLiveListenable,
              builder: (context, isLive, _) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!isLive)
                      SettingsMenu(
                        controller: controller,
                        theme: theme,
                        isMoreMenu: true,
                      ),
                    QualitySelector(
                      controller: controller,
                      showTooltip: false,
                      onOpen: () => controller.showMoreMenu(),
                      // Must mirror onOpen: an unbalanced open-count would
                      // leave the auto-hide timer disarmed forever.
                      onClose: () => controller.hideMoreMenu(),
                      alignment: Alignment.centerLeft,
                      offset: const Offset(-10, 0),
                      triggerBuilder: (context, VideoQuality? quality) {
                        return PlayerMenuItem(
                          leading: const Icon(Icons.high_quality),
                          text: controller.localization.translate('quality'),
                          trailing: Text(
                            quality?.label ??
                                controller.localization.translate('auto'),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                          onTap: null, // VDropdownMenu handles tap
                          theme: theme,
                        );
                      },
                    ),
                    if (!isLive)
                      SpeedSelector(
                        controller: controller,
                        showTooltip: false,
                        onOpen: () => controller.showMoreMenu(),
                        onClose: () => controller.hideMoreMenu(),
                        alignment: Alignment.centerLeft,
                        offset: const Offset(-10, 0),
                        triggerBuilder: (context, speed) {
                          return PlayerMenuItem(
                            leading: const Icon(Icons.speed),
                            text: controller.localization.translate('speed'),
                            trailing: Text(
                              '${speed}x',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                            onTap: null, // VDropdownMenu handles tap
                            theme: theme,
                          );
                        },
                      ),
                  ],
                );
              },
            ),
          if (controller.config.features.enablePictureInPicture && !fullscreen)
            PlayerMenuItem(
              leading: Icon(
                pip ? Icons.picture_in_picture : Icons.picture_in_picture_alt,
              ),
              text: controller.localization.translate('picture_in_picture'),
              onTap: () {
                controller.togglePip();
                close();
              },
              theme: theme,
            ),
          if (!pip)
            PlayerMenuItem(
              leading: Icon(
                fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
              ),
              text: fullscreen
                  ? controller.localization.translate('exit_fullscreen')
                  : controller.localization.translate('fullscreen'),
              onTap: () {
                controller.toggleFullscreen();
                close();
              },
              theme: theme,
            ),
        ];
      },
    );
  }
}
