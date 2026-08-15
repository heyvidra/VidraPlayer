import 'dart:async';

import 'package:flutter/material.dart';
import '../../controller/player_controller.dart';
import '../../core/state/quality_switching.dart';
import '../indicators/netflix_loading.dart';
import '../widget/blur.dart';
import '../../core/model/player_ui_theme.dart';

class SwitchingOverlay extends StatefulWidget {
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
  State<SwitchingOverlay> createState() => _SwitchingOverlayState();
}

class _SwitchingOverlayState extends State<SwitchingOverlay> {
  /// A switch that outlives this gets a cancel button. Short of it the
  /// overlay stays button-free — a fast switch flashing an escape hatch the
  /// user can't reach in time is just noise.
  static const _cancelAfter = Duration(seconds: 3);

  Timer? _cancelTimer;
  bool _showCancel = false;

  @override
  void initState() {
    super.initState();
    if (widget.state.isSwitching) _armCancelTimer();
  }

  @override
  void didUpdateWidget(SwitchingOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Keyed on the attempt id, not the isSwitching edge: cancel followed by
    // an immediate new switch delivers end+start in one task, so this State
    // sees a single update where isSwitching never flips — but the attempt
    // id always moves. Without this the dead switch's reveal timer carries
    // over and the new overlay shows the cancel button from frame one.
    if (widget.state.isSwitching &&
        (!oldWidget.state.isSwitching ||
            widget.state.attempt != oldWidget.state.attempt)) {
      _armCancelTimer();
    } else if (!widget.state.isSwitching && oldWidget.state.isSwitching) {
      _cancelTimer?.cancel();
      _showCancel = false;
    }
  }

  void _armCancelTimer() {
    _showCancel = false;
    _cancelTimer?.cancel();
    _cancelTimer = Timer(_cancelAfter, () {
      if (mounted) setState(() => _showCancel = true);
    });
  }

  @override
  void dispose() {
    _cancelTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final theme = widget.theme;
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
            // scaleDown: identity in a normal window, shrinks the whole block
            // proportionally in a small one (PiP, mini window). The cancel
            // button pushed the fixed-height column past short viewports —
            // overflow banner on real hardware.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Cover Image
                  if (widget.coverUrl != null && widget.coverUrl!.isNotEmpty)
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
                        // Decoded at the 200x120 it is drawn at, not at
                        // whatever the source happens to be — a 4K poster
                        // behind a switching overlay is megabytes of bitmap on
                        // a machine already busy opening a decoder.
                        child: Image.network(
                          widget.coverUrl!,
                          fit: BoxFit.cover,
                          cacheWidth:
                              (200 *
                                      MediaQuery.devicePixelRatioOf(context))
                                  .round(),
                          errorBuilder: (context, error, stack) {
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
                    widget.controller.localization.translate(
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
                    widget.controller.localization.translate('please_wait'),
                    style: TextStyle(
                      color: theme.textColor.withAlpha(128),
                      fontSize: 14,
                    ),
                  ),

                  // Escape hatch for a switch that drags on. This overlay
                  // swallows ALL player input while up; before this button a
                  // stalled open pinned the user for the full retry ladder.
                  const SizedBox(height: 24),
                  AnimatedOpacity(
                    opacity: _showCancel ? 1.0 : 0.0,
                    duration: theme.animationDuration,
                    child: TextButton(
                      // Null while hidden: opacity+IgnorePointer only stop the
                      // mouse — a disabled button also can't be reached by
                      // keyboard focus and activated invisibly.
                      onPressed: _showCancel
                          ? widget.controller.cancelSwitching
                          : null,
                      style: TextButton.styleFrom(
                        foregroundColor: theme.textColor.withAlpha(200),
                        side: BorderSide(color: theme.textColor.withAlpha(77)),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 8,
                        ),
                      ),
                      child: Text(
                        widget.controller.localization.translate('cancel'),
                      ),
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
