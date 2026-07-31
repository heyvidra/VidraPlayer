import 'package:flutter/material.dart';

import '../../controller/player_controller.dart';
import '../../core/state/states.dart';

/// The small pill that sits just above the progress bar: "skipping intro",
/// "skipping outro", or the one-off nudge that the bar has a right-click menu.
///
/// Shared by the desktop and mobile control layers — they rendered byte-identical
/// copies apart from the horizontal inset, and a third variant would have meant
/// maintaining the branch twice.
class SkipPrompt extends StatelessWidget {
  final PlayerController controller;
  final SkipNotificationType type;
  final double horizontalPadding;

  const SkipPrompt({
    super.key,
    required this.controller,
    required this.type,
    this.horizontalPadding = 24.0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = controller.config.theme;
    final isIntro = type == SkipNotificationType.intro;
    final isHint = type == SkipNotificationType.markerHint;

    final text = switch (type) {
      SkipNotificationType.intro => controller.localization.translate(
        'skipping_intro',
      ),
      SkipNotificationType.outro => controller.localization.translate(
        'skipping_outro',
      ),
      SkipNotificationType.markerHint => controller.localization.translate(
        'marker_hint',
      ),
      SkipNotificationType.none => '',
    };

    // Intro skips read left-to-right from the start of the bar, outro from the
    // end; the hint is about the whole bar, so it sits in the middle.
    final alignment = isHint
        ? Alignment.center
        : (isIntro ? Alignment.centerLeft : Alignment.centerRight);
    final icon = isHint ? Icons.ads_click : Icons.skip_next;
    final iconLeading = isHint || isIntro;

    return Padding(
      key: ValueKey(type),
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: 8.0,
      ),
      child: Align(
        alignment: alignment,
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
              if (iconLeading) ...[
                Icon(icon, color: theme.iconColor, size: 18),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  text,
                  style: TextStyle(
                    color: theme.textColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (!iconLeading) ...[
                const SizedBox(width: 8),
                Icon(icon, color: theme.iconColor, size: 18),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
