import 'package:flutter/material.dart';
import '../../controller/player_controller.dart';
import '../../core/state/states.dart';
import '../widget/animation_button.dart';

class VolumeControl extends StatefulWidget {
  final PlayerController controller;

  const VolumeControl({super.key, required this.controller});

  @override
  State<VolumeControl> createState() => _VolumeControlState();
}

class _VolumeControlState extends State<VolumeControl> {
  bool _isHovering = false;

  @override
  void dispose() {
    // MouseRegion.onExit is NOT invoked when the region is unmounted while
    // hovered (documented Flutter caveat). Without this reset the stuck
    // isHoveringControls flag makes the auto-hide timer re-arm forever and
    // the controls never hide again.
    if (_isHovering) {
      widget.controller.handleMouseLeaveControls();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.controller.config.theme;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        setState(() => _isHovering = true);
        widget.controller.handleMouseEnterControls();
      },
      onExit: (_) {
        setState(() => _isHovering = false);
        widget.controller.handleMouseLeaveControls();
      },
      child: StreamBuilder<AudioState>(
        stream: widget.controller.audioStream,
        initialData: widget.controller.audio,
        builder: (context, snapshot) {
          final audioState = snapshot.data!;
          final volume = audioState.volume;
          final isMuted = audioState.isMuted;

          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimationButton(
                onTap: () => widget.controller.toggleMute(),
                child: IconButton(
                  key: const ValueKey('volume_mute_button'),
                  icon: Icon(
                    isMuted || volume == 0
                        ? Icons.volume_off
                        : volume < 0.5
                        ? Icons.volume_down
                        : Icons.volume_up,
                    color: theme.iconColor,
                    size: 20,
                  ),
                  onPressed: () {},
                ),
              ),
              AnimatedContainer(
                margin: EdgeInsets.only(right: 5),
                duration: const Duration(milliseconds: 200),
                width: _isHovering ? 100 : 0,
                curve: Curves.easeInOut,
                clipBehavior: Clip.antiAlias,
                decoration: const BoxDecoration(),
                child: SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: theme.progressBarColor,
                    inactiveTrackColor: theme.bufferedColor,
                    thumbColor: theme.progressBarColor,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 6,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 12,
                    ),
                    trackHeight: 2,
                  ),
                  child: Slider(
                    value: isMuted ? 0 : volume,
                    onChanged: (value) {
                      widget.controller.setVolume(value);
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
