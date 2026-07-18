import 'package:flutter/material.dart';
import '../../controller/player_controller.dart';
import '../../core/state/states.dart';
import '../overlays/episode_list.dart';
import '../overlays/resume_dialog.dart';
import '../overlays/switching_overlay.dart';
import '../controls/video_controls.dart';
import '../widget/slide_panel.dart';

/// 控制及覆盖层
/// 包含: 控制栏, 对话框(Resume/Replay), 侧边栏(EpisodeList), 切换覆盖层
class ControlsOverlayLayer extends StatelessWidget {
  final PlayerController controller;

  const ControlsOverlayLayer({
    super.key,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<UIVisibilityState>(
      stream: controller.visibilityStream,
      initialData: controller.visibility,
      builder: (context, snapshot) {
        final ui = snapshot.data ?? const UIVisibilityState();

        return Stack(
          children: [
            // 控制栏 (包含 TopBar, BottomBar, Gradient 等内部逻辑)
            _buildDefaultControls(context, ui),

            // 3. Resume Dialog (继续播放提示)
            if (ui.showResumeDialog && ui.resumeState != null)
              ResumeDialog(
                controller: controller,
                position: Duration(
                  milliseconds: ui.resumeState!.positionMillis,
                ),
                duration: Duration(
                  milliseconds: ui.resumeState!.durationMillis,
                ),
                autoClose: !controller.config.behavior.resumeOnFocus,
                onResume: () =>
                    controller.continuePlayback(ui.resumeState!.positionMillis),
                onRestart: () => controller.restartPlayback(),
              ),

            // 4. Replay Dialog (重播提示)
            if (ui.showReplayDialog && ui.replayState != null)
              ReplayDialog(
                controller: controller,
                position: Duration(
                  milliseconds: ui.replayState!.positionMillis,
                ),
                duration: Duration(
                  milliseconds: ui.replayState!.durationMillis,
                ),
                hasNextEpisode: controller.hasNextEpisode,
                onReplay: () => controller.replayEpisode(),
                onDismiss: () => controller.dismissReplayDialog(),
                onPlayNext: controller.hasNextEpisode
                    ? () => controller.playNextEpisodeFromReplay()
                    : null,
              ),

            // 5. Side Panel (Episode List)
            // IgnorePointer while closed: SlidePanel's AnimatedSwitcher keeps
            // the outgoing EpisodeList mounted for its 300ms exit animation,
            // and that panel's full-screen opaque onClose barrier sits ON TOP
            // of the top bar here — so during the exit it would eat a tap on
            // the episodes button (reopen "stuck", works only after the
            // animation finishes). Ignoring pointers unless actually open lets
            // the reopen tap fall through to the button.
            Positioned.fill(
              child: IgnorePointer(
                ignoring: !ui.showEpisodeList,
                child: SlidePanel(
                child: ui.showEpisodeList
                    ? EpisodeList(
                        key: const ValueKey('EpisodeListPanel'),
                        controller: controller,
                        episodes: controller.media.episodes,
                        histories: controller.media.episodeHistory,
                        onClose: () => controller.hideEpisodeList(),
                        currentEpisodeIndex:
                            controller.media.currentEpisodeIndex,
                        onEpisodeSelected: (int index) {
                          controller.switchEpisode(index);
                          controller.hideEpisodeList();
                        },
                        episodesSort: controller.config.episodesSort,
                      )
                    : const SizedBox.shrink(),
                ),
              ),
            ),

            // 6. Switching Overlay (切集时的Loading)
            Positioned.fill(
              child: StreamBuilder<SwitchingState>(
                stream: controller.switchingStream,
                initialData: controller.switching,
                builder: (context, snapshot) {
                  final switchingState =
                      snapshot.data ?? const SwitchingState();
                  return SwitchingOverlay(
                    controller: controller,
                    state: switchingState,
                    coverUrl: controller.media.video?.coverUrl,
                    theme: controller.config.theme,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDefaultControls(
    BuildContext context,
    UIVisibilityState visibility,
  ) {
    final theme = controller.config.theme;
    return Stack(
      fit: StackFit.expand,
      children: [
        // Gradient Overlay
        Positioned.fill(
          child: IgnorePointer(
            ignoring: true,
            child: AnimatedOpacity(
              opacity: visibility.showControls ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      theme.backgroundColor.withAlpha(128),
                      Colors.transparent,
                      Colors.transparent,
                      theme.backgroundColor.withAlpha(128),
                    ],
                    stops: const [0.0, 0.2, 0.8, 1.0],
                  ),
                ),
              ),
            ),
          ),
        ),
        // Video Controls Widget
        Positioned.fill(
          child: VideoControls(controller: controller, visibility: visibility),
        ),
      ],
    );
  }
}
