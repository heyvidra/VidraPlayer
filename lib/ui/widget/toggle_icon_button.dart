import 'package:flutter/material.dart';

class PlayPauseButton extends StatefulWidget {
  final bool isPlaying;
  final double size;
  final Color color;
  final Duration duration;
  final VoidCallback? onTap;

  const PlayPauseButton({
    super.key,
    this.isPlaying = false,
    this.size = 60,
    this.color = Colors.red,
    this.duration = const Duration(milliseconds: 300),
    this.onTap,
  });

  @override
  State<PlayPauseButton> createState() => _PlayPauseButtonState();
}

class _PlayPauseButtonState extends State<PlayPauseButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnim;
  late Animation<double> _circleAnim;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(vsync: this, duration: widget.duration);

    // Scale animation
    _scaleAnim = Tween<double>(
      begin: 1.0,
      end: 0.8,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    // Background circle animation
    _circleAnim = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    if (widget.isPlaying) {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(PlayPauseButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Pure reflection of [widget.isPlaying] — NO local optimistic state. The
    // parent already flips lifecycle optimistically (PlaybackManager.play/
    // pause emit before awaiting the player), so this morphs with no
    // perceptible latency while staying impossible to desync from the
    // bottom-bar StreamBuilder icon that reads the same source. An earlier
    // local `isPlaying` flip could latch out of step (a rejected play() in
    // PiP, or a stale reconcile frame) and strand this glyph opposite the
    // bottom bar until a remount.
    if (widget.isPlaying) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: widget.size * 1.6 * _circleAnim.value,
                height: widget.size * 1.6 * _circleAnim.value,
                decoration: BoxDecoration(
                  color: widget.color.withValues(
                    alpha: 0.2 * _circleAnim.value,
                  ),
                  shape: BoxShape.circle,
                ),
              ),

              // Scale icon
              Transform.scale(
                scale: _scaleAnim.value,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Opacity(
                      opacity: 1 - _controller.value,
                      child: Icon(
                        Icons.play_arrow,
                        size: widget.size,
                        color: widget.color,
                      ),
                    ),
                    Opacity(
                      opacity: _controller.value,
                      child: Icon(
                        Icons.pause,
                        size: widget.size,
                        color: widget.color,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
