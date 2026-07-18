import 'package:flutter/material.dart';

import '../../utils/event_control.dart';

class AnimationButton extends StatefulWidget {
  final Widget child;
  final Function? onTap;
  final Function? onCompleted;
  final bool debounce;

  const AnimationButton({
    super.key,
    required this.child,
    this.onTap,
    this.onCompleted,
    this.debounce = false,
  });

  @override
  State<AnimationButton> createState() => _AnimationWidgetState();
}

class _AnimationWidgetState extends State<AnimationButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  late final Debounce? _debounce;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    _animation = Tween(begin: 1.0, end: 0.7).animate(_controller);
    _animation.addStatusListener((AnimationStatus status) {
      if (status == AnimationStatus.completed) {
        _controller.reverse().then((value) {
          widget.onCompleted?.call();
        });
      }
    });

    _debounce = widget.debounce
        ? Debounce(const Duration(milliseconds: 300))
        : null;
  }

  void onTap() {
    if (widget.debounce) {
      _debounce!.call(() {
        _executeTap();
      });
    } else {
      _executeTap();
    }
  }

  void _executeTap() {
    widget.onTap?.call();
    _controller.forward();
  }

  @override
  void dispose() {
    _debounce?.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _animation,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) {
            onTap.call();
          },
          onPointerUp: (_) {},
          child: widget.child,
        ),
      ),
    );
  }
}
