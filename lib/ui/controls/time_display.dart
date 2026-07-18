import 'package:flutter/material.dart';
import 'package:vidra_player/utils/util.dart';
import '../../controller/player_controller.dart';
import '../../core/state/states.dart';

class TimeDisplay extends StatefulWidget {
  final PlayerController controller;

  const TimeDisplay({super.key, required this.controller});

  @override
  State<TimeDisplay> createState() => _TimeDisplayState();
}

class _TimeDisplayState extends State<TimeDisplay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    // Don't repeat unconditionally — the pulse is only shown for live content.
    // A permanently-running ticker keeps the whole UI scheduling frames even
    // for VOD (where nothing pulses) and while controls are hidden. Started on
    // demand from build() below.
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _pulseAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.controller.config.theme;
    return ValueListenableBuilder<PlaybackPositionState>(
      valueListenable: widget.controller.positionListenable,
      builder: (context, state, _) {
        if (state.isLive) {
          // Run the pulse only while live. For VOD (the common case) it never
          // starts, so the UI can go fully idle.
          // ponytail: still ticks while live-and-controls-hidden; wrap the
          // controls subtree in TickerMode(enabled: showControls) if that ever
          // shows up on a profile (skipped now — it can freeze the hide fade).
          if (!_pulseController.isAnimating) {
            _pulseController.repeat(reverse: true);
          }
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FadeTransition(
                opacity: _pulseAnimation,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: theme.progressBarColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: theme.progressBarColor.withValues(alpha: 0.5),
                        blurRadius: 4,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'LIVE',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          );
        }
        // Not live — make sure the pulse ticker isn't burning frames.
        if (_pulseController.isAnimating) _pulseController.stop();
        return Text(
          '${Util.formatDuration(state.position)} / ${Util.formatDuration(state.duration)}',
          style: TextStyle(color: theme.textColor),
        );
      },
    );
  }
}
