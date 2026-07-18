import 'package:flutter/widgets.dart';

enum RevealDirection { fromTop, fromBottom, fromLeft, fromRight }

class RevealAnimation extends StatelessWidget {
  final Animation<double> animation; // 0.0 -> hidden, 1.0 -> shown
  final Widget child;
  final RevealDirection direction;
  final bool clip;

  const RevealAnimation({
    super.key,
    required this.animation,
    required this.child,
    this.direction = RevealDirection.fromBottom,
    this.clip = true,
  });

  @override
  Widget build(BuildContext context) {
    Widget content = AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        return Align(
          alignment: _alignment,
          heightFactor: _isVertical ? animation.value : 1.0,
          widthFactor: _isHorizontal ? animation.value : 1.0,
          child: FadeTransition(opacity: animation, child: child),
        );
      },
    );

    return clip ? ClipRect(child: content) : content;
  }

  bool get _isVertical =>
      direction == RevealDirection.fromTop ||
      direction == RevealDirection.fromBottom;

  bool get _isHorizontal =>
      direction == RevealDirection.fromLeft ||
      direction == RevealDirection.fromRight;

  Alignment get _alignment {
    switch (direction) {
      case RevealDirection.fromTop:
        return Alignment.topCenter;
      case RevealDirection.fromBottom:
        return Alignment.bottomCenter;
      case RevealDirection.fromLeft:
        return Alignment.centerLeft;
      case RevealDirection.fromRight:
        return Alignment.centerRight;
    }
  }
}
