import 'package:flutter/widgets.dart';

enum RevealDirection { fromTop, fromBottom }

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
      // Built ONCE, not once per frame. This wraps the top and bottom control
      // bars — a deep subtree of StreamBuilders, icon rows and nested
      // AnimatedSwitchers — and rebuilding all of it for 300ms every time the
      // controls showed or hid (i.e. on every mouse move after an auto-hide)
      // was the single biggest stutter on low-end machines. Only the Align
      // factors actually depend on the animation value; the fade is driven by
      // FadeTransition's own listener, no rebuild needed.
      child: FadeTransition(opacity: animation, child: child),
      builder: (context, child) {
        return Align(
          alignment: _alignment,
          heightFactor: animation.value,
          child: child,
        );
      },
    );

    return clip ? ClipRect(child: content) : content;
  }

  Alignment get _alignment {
    switch (direction) {
      case RevealDirection.fromTop:
        return Alignment.topCenter;
      case RevealDirection.fromBottom:
        return Alignment.bottomCenter;
    }
  }
}
