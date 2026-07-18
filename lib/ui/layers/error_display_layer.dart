import 'package:flutter/material.dart';
import '../../controller/player_controller.dart';
import '../../core/state/states.dart';
import '../indicators/error_display.dart';

/// 错误显示层
class ErrorDisplayLayer extends StatelessWidget {
  final PlayerController controller;
  final Widget? customError;

  const ErrorDisplayLayer({
    super.key,
    required this.controller,
    this.customError,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ErrorState>(
      stream: controller.errorStream,
      initialData: controller.error,
      builder: (context, snapshot) {
        final error = snapshot.data;
        if (error == null || !error.hasError) {
          return const SizedBox.shrink();
        }

        if (customError != null) return customError!;

        return ErrorDisplay(
          controller: controller,
          error: error.error!,
          onRetry: () {
            // Force reload current quality and auto-play
            controller.switchQuality(
              controller.media.currentQualityIndex,
              forcePlay: true,
            );
          },
          onTryAnotherSource: controller.media.availableQualities.length > 1
              ? () {
                  final current = controller.media.currentQualityIndex;
                  final next =
                      (current + 1) %
                      controller.media.availableQualities.length;
                  controller.switchQuality(next, forcePlay: true);
                }
              : null,
        );
      },
    );
  }
}
