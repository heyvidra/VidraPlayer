import 'package:flutter/material.dart';
import '../../controller/player_controller.dart';
import '../../core/state/states.dart';
import 'volume_control.dart';
import '../widget/animation_button.dart';

class PlaybackControls extends StatelessWidget {
  final PlayerController controller;
  final bool isSmall;

  const PlaybackControls({
    super.key,
    required this.controller,
    this.isSmall = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = controller.config.theme;
    // final l10n = controller.localization;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (Widget child, Animation<double> animation) {
              return FadeTransition(
                opacity: animation,
                child: SizeTransition(
                  sizeFactor: animation,
                  axis: Axis.horizontal,
                  child: child,
                ),
              );
            },
            child: !isSmall
                ? Row(
                    key: const ValueKey('play_pause_group'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      StreamBuilder<PlaybackLifecycleState>(
                        stream: controller.lifecycleStream,
                        initialData: controller.lifecycle,
                        builder: (context, stateSnapshot) {
                          final state =
                              stateSnapshot.data ??
                              const PlaybackLifecycleState();
                          return AnimationButton(
                            onTap: () => controller.togglePlayPause(),
                            child: IconButton(
                              key: const ValueKey(
                                'bottom_bar_play_pause_button',
                              ),
                              icon: Icon(
                                state.isPlaying
                                    ? Icons.pause
                                    : Icons.play_arrow,
                                color: theme.iconColor,
                              ),
                              onPressed: () {},
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                    ],
                  )
                : const SizedBox.shrink(key: ValueKey('play_pause_empty')),
          ),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: controller.isLiveListenable,
          builder: (context, isLive, _) {
            if (isLive) return const SizedBox.shrink();
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimationButton(
                  onCompleted: controller.hasPreviousEpisode
                      ? () => controller.playPreviousEpisode()
                      : null,
                  debounce: true,
                  child: IconButton(
                    key: const ValueKey('bottom_bar_previous_button'),
                    icon: Icon(
                      Icons.skip_previous,
                      color: controller.hasPreviousEpisode
                          ? theme.iconColor
                          : theme.iconColorDisabled,
                    ),
                    onPressed: () {},
                  ),
                ),
                const SizedBox(width: 8),
                AnimationButton(
                  onCompleted: controller.hasNextEpisode
                      ? () => controller.playNextEpisode()
                      : null,
                  debounce: true,
                  child: IconButton(
                    key: const ValueKey('bottom_bar_next_button'),
                    icon: Icon(
                      Icons.skip_next,
                      color: controller.hasNextEpisode
                          ? theme.iconColor
                          : theme.iconColorDisabled,
                    ),
                    onPressed: () {},
                  ),
                ),
                const SizedBox(width: 8),
              ],
            );
          },
        ),
        // Volume Control
        VolumeControl(controller: controller),
      ],
    );
  }
}
