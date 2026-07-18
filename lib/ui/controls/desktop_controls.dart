import 'package:flutter/material.dart';
import 'package:vidra_player/core/state/states.dart';
import 'package:vidra_player/ui/widget/blur.dart';
import 'package:vidra_player/ui/widget/control_hover_region.dart';
import '../../controller/player_controller.dart';
import '../widget/reveal_animation.dart';
import 'center_play_button.dart';
import 'top_bar.dart';
import 'bottom_bar.dart';

/// Desktop video control panel
class DesktopVideoControls extends StatelessWidget {
  final PlayerController controller;
  final UIVisibilityState visibility;
  final Animation<double> animation;

  const DesktopVideoControls({
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
          CenterPlayButton(
            controller: controller,
            opacity: animation,
            enabled: controlsInteractive,
          ),
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
                    horizontal: 16.0,
                    vertical: 8,
                  ),
                  child: TopBar(
                    key: const Key("top_bar"),
                    controller: controller,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: ControlHoverRegion(
              controller: controller,
              enabled: controlsInteractive,
              child: Container(
                decoration: BoxDecoration(
                  gradient: theme.bottomControlsGradient,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Column(
                  children: [
                    _buildSkipPrompt(),
                    _buildSeekFeedback(),
                    RevealAnimation(
                      animation: animation,
                      direction: RevealDirection.fromBottom,
                      clip: false,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: BottomBar(
                          key: const Key("bottom_bar"),
                          controller: controller,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkipPrompt() {
    final theme = controller.config.theme;
    // Read from the `visibility` already passed in — the parent StreamBuilder
    // rebuilds this widget on every visibility emission, so an inner
    // StreamBuilder on the same stream was a redundant extra subscription.
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

  Widget _buildPromptContent(SkipNotificationType type) {
    final theme = controller.config.theme;
    final isIntro = type == SkipNotificationType.intro;
    final text = isIntro
        ? controller.localization.translate('skipping_intro')
        : controller.localization.translate('skipping_outro');

    return Padding(
      key: ValueKey(type),
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
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
}
