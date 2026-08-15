import 'package:flutter/material.dart';
import '../../controller/player_controller.dart';
import '../../core/state/states.dart';

/// 视频渲染层
class VideoSurfaceLayer extends StatelessWidget {
  final PlayerController controller;
  final Widget? customLoading;

  const VideoSurfaceLayer({
    super.key,
    required this.controller,
    this.customLoading,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlaybackLifecycleState>(
      stream: controller.lifecycleStream,
      initialData: controller.lifecycle,
      builder: (context, snapshot) {
        final state = snapshot.data;

        if (state == null || !state.isInitialized) {
          final coverUrl = controller.media.video?.coverUrl;

          if (coverUrl == null) {
            return const SizedBox.shrink();
          }

          return Stack(
            fit: StackFit.expand,
            children: [
              // cacheWidth caps the decode at the window width. Without it a
              // 4K poster decodes at full size behind a black scrim, which on
              // a low-end machine is the most expensive thing on screen before
              // the video has even opened.
              Image.network(
                coverUrl,
                fit: BoxFit.cover,
                cacheWidth: (MediaQuery.sizeOf(context).width *
                        MediaQuery.devicePixelRatioOf(context))
                    .round(),
                errorBuilder: (context, error, stack) =>
                    const SizedBox.shrink(),
              ),
              Container(color: Colors.black54),
            ],
          );
        }

        return Center(
          child: RepaintBoundary(
            child: AspectRatio(
              aspectRatio: state.aspectRatio,
              child: controller.renderPlayer(),
            ),
          ),
        );
      },
    );
  }
}
