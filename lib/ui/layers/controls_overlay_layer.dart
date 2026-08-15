import 'package:flutter/material.dart';
import '../../controller/player_controller.dart';
import '../../core/model/player_behavior.dart';
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

  const ControlsOverlayLayer({super.key, required this.controller});

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
                // Was wired to resumeOnFocus, which has nothing to do with
                // countdowns and meant nobody could find the switch.
                autoClose:
                    controller.config.behavior.resumeMode ==
                    ResumeMode.promptWithCountdown,
                onResume: () =>
                    controller.continuePlayback(ui.resumeState!.positionMillis),
                onRestart: () => controller.restartPlayback(),
              ),

            // 3b. Non-blocking resume card. Sits in a corner ABOVE nothing —
            // no barrier, no IgnorePointer — because playback is already
            // running at the restored position; this only reports it and
            // offers the way back to 0:00.
            if (ui.resumeHint != null)
              Positioned(
                left: 0,
                bottom: 72,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: InlineResumePrompt(
                    controller: controller,
                    position: Duration(
                      milliseconds: ui.resumeHint!.positionMillis,
                    ),
                    onRestart: controller.restartFromResumeHint,
                    onDismiss: controller.dismissResumeHint,
                  ),
                ),
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
        // Gradient Overlay.
        //
        // Faded by tweening the gradient's own alpha, NOT with AnimatedOpacity.
        // This box is the size of the window and sits directly on top of the
        // video, so an opacity animation over it meant a full-screen
        // `saveLayer` — allocate an offscreen buffer the size of the player,
        // draw into it, composite it back — on every frame for 300ms, every
        // single time the controls showed or hid. Painting the same gradient
        // with pre-multiplied alpha is one flat fill and looks identical.
        Positioned.fill(
          child: IgnorePointer(
            ignoring: true,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(
                end: visibility.showControls ? 1.0 : 0.0,
              ),
              duration: const Duration(milliseconds: 300),
              builder: (context, t, _) {
                if (t == 0) return const SizedBox.expand();
                final edge = theme.backgroundColor.withValues(
                  alpha: theme.backgroundColor.a * (128 / 255) * t,
                );
                return DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        edge,
                        Colors.transparent,
                        Colors.transparent,
                        edge,
                      ],
                      stops: const [0.0, 0.2, 0.8, 1.0],
                    ),
                  ),
                  child: const SizedBox.expand(),
                );
              },
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
