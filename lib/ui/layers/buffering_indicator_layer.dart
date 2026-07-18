import 'package:flutter/material.dart';
import '../../controller/player_controller.dart';
import '../../core/state/states.dart';
import '../indicators/netflix_loading.dart';

class BufferingIndicatorLayer extends StatelessWidget {
  final PlayerController controller;
  final Widget? customLoading;

  const BufferingIndicatorLayer({
    super.key,
    required this.controller,
    this.customLoading,
  });

  @override
  Widget build(BuildContext context) {
    final theme = controller.config.theme;

    return StreamBuilder<PlaybackLifecycleState>(
      stream: controller.lifecycleStream,
      initialData: controller.lifecycle,
      builder: (context, lifecycleSnapshot) {
        final lifecycle = lifecycleSnapshot.data ?? controller.lifecycle;

        return StreamBuilder<BufferingState>(
          stream: controller.bufferingStream,
          initialData: controller.buffering,
          builder: (context, bufferingSnapshot) {
            final isBuffering = bufferingSnapshot.data?.isBuffering ?? false;

            // Only show buffering indicator if:
            // 1. We haven't finished initializing yet (initial load)
            // 2. OR we are actually buffering
            final shouldShow = !lifecycle.isInitialized || isBuffering;

            if (!shouldShow) return const SizedBox.shrink();
            final bufferingDetail = bufferingSnapshot.data;
            final String? message;
            if (bufferingDetail?.messageKey != null) {
              message = controller.localization.translate(
                bufferingDetail!.messageKey!,
                args: bufferingDetail.messageArgs,
              );
            } else {
              message = bufferingDetail?.message;
            }

            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  customLoading ?? NetflixLoading(color: theme.primaryColor),
                  if (message != null && message.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      message,
                      style: TextStyle(color: theme.textColor, fontSize: 14),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }
}
