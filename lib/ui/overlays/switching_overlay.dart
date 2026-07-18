import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../controller/player_controller.dart';
import '../../core/state/quality_switching.dart';
import '../indicators/netflix_loading.dart';
import '../widget/blur.dart';
import '../../core/model/player_ui_theme.dart';

class SwitchingOverlay extends StatelessWidget {
  final PlayerController controller;
  final SwitchingState state;
  final String? coverUrl;
  final PlayerUITheme theme;

  const SwitchingOverlay({
    super.key,
    required this.controller,
    required this.state,
    this.coverUrl,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    if (!state.isSwitching) {
      return const SizedBox.shrink();
    }

    return AnimatedOpacity(
      opacity: state.isSwitching ? 1.0 : 0.0,
      duration: theme.animationDuration,
      child: BlurPanel(
        child: Container(
          color: theme.backgroundColor.withAlpha(222), // ~87% opacity
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Cover Image
                if (coverUrl != null && coverUrl!.isNotEmpty)
                  Container(
                    width: 200,
                    height: 120,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(
                            128,
                          ), // Shadow remains black
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        imageUrl: coverUrl!,
                        fit: BoxFit.cover,
                        errorWidget: (context, url, error) {
                          return Container(
                            color: theme.controlsBackground,
                            child: Icon(
                              Icons.video_library,
                              size: 48,
                              color: theme.iconColorDisabled,
                            ),
                          );
                        },
                      ),
                    ),
                  ),

                const SizedBox(height: 24),

                // Loading Animation
                NetflixLoading(height: 48, color: theme.primaryColor),

                const SizedBox(height: 16),

                // Switching Text
                Text(
                  controller.localization.translate(
                    'switching_to_quality',
                    args: {'quality': state.targetQualityLabel ?? ''},
                  ),
                  style: TextStyle(
                    color: theme.textColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),

                const SizedBox(height: 4),

                // Hint Text
                Text(
                  controller.localization.translate('please_wait'),
                  style: TextStyle(
                    color: theme.textColor.withAlpha(128),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
