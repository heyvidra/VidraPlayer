import 'package:flutter/material.dart';
import 'package:vidra_player/core/state/states.dart';
import '../../controller/player_controller.dart';
import '../../core/model/player_ui_theme.dart';
import '../widget/reveal_animation.dart';
import '../widget/blur.dart';
import 'top_bar.dart';
import 'progress_bar.dart';
import 'time_display.dart';
import '../widget/animation_button.dart';
import '../widget/control_hover_region.dart';

/// Mobile video control panel
class MobileVideoControls extends StatelessWidget {
  final PlayerController controller;
  final UIVisibilityState visibility;
  final Animation<double> animation;

  const MobileVideoControls({
    super.key,
    required this.controller,
    required this.visibility,
    required this.animation,
  });

  @override
  Widget build(BuildContext context) {
    final shouldBlockInteractions =
        visibility.showResumeDialog || visibility.showReplayDialog;
    final controlsInteractive =
        visibility.showControls && !shouldBlockInteractions;
    final theme = controller.config.theme;
    return IgnorePointer(
      ignoring: !visibility.showControls || shouldBlockInteractions,
      child: Stack(
        children: [
          // Center Controls (Play/Pause + Seek)
          _MobileCenterControls(
            controller: controller,
            opacity: animation,
            enabled: controlsInteractive,
          ),

          // Top Control Bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ControlHoverRegion(
              controller: controller,
              enabled: controlsInteractive,
              child: RevealAnimation(
                animation: animation,
                direction: RevealDirection.fromTop,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: theme.topControlsGradient,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: TopBar(
                    key: const Key("mobile_top_bar"),
                    controller: controller,
                  ),
                ),
              ),
            ),
          ),

          // Bottom Control Bar
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: ControlHoverRegion(
              controller: controller,
              enabled: controlsInteractive,
              child: RevealAnimation(
                animation: animation,
                direction: RevealDirection.fromBottom,
                child: Column(
                  children: [
                    // Skip Prompts
                    _buildSkipPrompt(),
                    _MobileBottomControls(
                      key: const Key("mobile_bottom_bar"),
                      controller: controller,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Persistent Progress Bar
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _MobileProgressBar(
              controller: controller,
              thumbVisible: visibility.showControls,
            ),
          ),

          // Seek Feedback
          Positioned(
            bottom: 60,
            left: 0,
            right: 0,
            child: _buildSeekFeedback(),
          ),
        ],
      ),
    );
  }

  Widget _buildSkipPrompt() {
    final theme = controller.config.theme;
    // Read from the passed-in `visibility`; the parent StreamBuilder already
    // rebuilds this widget on every emission (redundant inner subscription).
    final type = visibility.skipNotification;

    return AnimatedSwitcher(
      duration: theme.animationDuration,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.2),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: type == SkipNotificationType.none
          ? const SizedBox.shrink(key: ValueKey('none'))
          : _buildPromptContent(type),
    );
  }

  Widget _buildPromptContent(SkipNotificationType type) {
    final theme = controller.config.theme;
    final isIntro = type == SkipNotificationType.intro;
    final text = isIntro
        ? controller.localization.translate('skipping_intro')
        : controller.localization.translate('skipping_outro');

    return Padding(
      key: ValueKey(type),
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Align(
        alignment: isIntro ? Alignment.centerLeft : Alignment.centerRight,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          decoration: BoxDecoration(
            color: theme.backgroundColor.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: theme.iconColor.withValues(alpha: 0.15),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isIntro) ...[
                Icon(Icons.skip_next, color: theme.iconColor, size: 18),
                const SizedBox(width: 8),
              ],
              Text(
                text,
                style: TextStyle(
                  color: theme.textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (!isIntro) ...[
                const SizedBox(width: 8),
                Icon(Icons.skip_next, color: theme.iconColor, size: 18),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSeekFeedback() {
    final theme = controller.config.theme;
    final seekAmount = visibility.seekFeedback;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.8, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
            ),
            child: child,
          ),
        );
      },
      child: seekAmount == null
          ? const SizedBox.shrink(key: ValueKey('none'))
          : Padding(
              key: const ValueKey('seek_feedback_container'),
              padding: const EdgeInsets.only(bottom: 10),
              child: Center(
                child: BlurPanel(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 6.0,
                    ),
                    decoration: BoxDecoration(
                      color: theme.dialogBackgroundColor.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          seekAmount.isNegative
                              ? Icons.replay_10
                              : Icons.forward_10,
                          color: theme.iconColor,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '${seekAmount.inSeconds > 0 ? '+' : ''}${seekAmount.inSeconds}s',
                          style: TextStyle(
                            color: theme.textColor,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

class _MobileCenterControls extends StatelessWidget {
  final PlayerController controller;
  final Animation<double> opacity;
  final bool enabled;

  const _MobileCenterControls({
    required this.controller,
    required this.opacity,
    required this.enabled,
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
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Seek Backward 10s
                    // _buildCircleButton(
                    //   theme: theme,
                    //   icon: Icons.replay_10,
                    //   onTap: () {
                    //     controller.seekRelative(const Duration(seconds: -10));
                    //     controller.uiManager.showSeekFeedback(
                    //       const Duration(seconds: -10),
                    //     );
                    //   },
                    //   size: 48,
                    // ),
                    // const SizedBox(width: 48),

                    // Play/Pause
                    _buildCircleButton(
                      theme: theme,
                      icon: state.isPlaying ? Icons.pause : Icons.play_arrow,
                      onTap: () => controller.togglePlayPause(),
                      size: 72,
                      iconSize: 40,
                    ),

                    // const SizedBox(width: 48),

                    // // Seek Forward 10s
                    // _buildCircleButton(
                    //   theme: theme,
                    //   icon: Icons.forward_10,
                    //   onTap: () {
                    //     controller.seekRelative(const Duration(seconds: 10));
                    //     controller.uiManager.showSeekFeedback(
                    //       const Duration(seconds: 10),
                    //     );
                    //   },
                    //   size: 48,
                    // ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCircleButton({
    required PlayerUITheme theme,
    required IconData icon,
    required VoidCallback onTap,
    required double size,
    double iconSize = 28,
  }) {
    return AnimationButton(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: theme.backgroundColor.withValues(alpha: 0.6),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: iconSize, color: theme.iconColor),
      ),
    );
  }
}

class _MobileBottomControls extends StatelessWidget {
  final PlayerController controller;

  const _MobileBottomControls({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = controller.config.theme;

    return Container(
      decoration: BoxDecoration(gradient: theme.bottomControlsGradient),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          TimeDisplay(controller: controller),
          const Spacer(),

          StreamBuilder<ViewModeState>(
            stream: controller.viewStream,
            initialData: controller.view,
            builder: (context, snapshot) {
              final viewState = snapshot.data ?? controller.view;
              final isFullscreen = viewState.isFullscreen;
              final isPip = viewState.isPip;

              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (controller.config.features.enablePictureInPicture &&
                      !isFullscreen)
                    AnimationButton(
                      onTap: () => controller.togglePip(),
                      child: Icon(
                        isPip
                            ? Icons.picture_in_picture
                            : Icons.picture_in_picture_alt,
                        color: theme.iconColor,
                        size: 20,
                      ),
                    ),
                  const SizedBox(width: 8),
                  AnimationButton(
                    onTap: () => controller.toggleFullscreen(),
                    child: Icon(
                      isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                      color: theme.iconColor,
                      size: 24,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MobileProgressBar extends StatelessWidget {
  final PlayerController controller;
  final bool thumbVisible;

  const _MobileProgressBar({
    required this.controller,
    required this.thumbVisible,
  });

  @override
  Widget build(BuildContext context) {
    final theme = controller.config.theme;
    // Position ticks are consumed inside VideoProgressBar (paint-only) — no
    // position-driven builder here, or every tick would rebuild the subtree.
    return RepaintBoundary(
      child: VideoProgressBar(
        key: const ValueKey("mobile_video_progress_bar"),
        positionListenable: controller.positionListenable,
        onSeek: (pos) => controller.seek(pos, SeekSource.userDrag),
        onSeekStart: controller.seekStart,
        onSeekEnd: controller.seekEnd,
        playedColor: theme.progressBarColor,
        bufferedColor: theme.bufferedColor,
        handleColor: theme.progressBarColor,
        barHeight: thumbVisible ? 3 : 2, // Thinner when hidden
        handleRadius: 4, // Larger handle for touch
        padding: 0,
        thumbVisible: thumbVisible,
        controller: controller,
      ),
    );
  }
}
