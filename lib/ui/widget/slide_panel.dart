import 'package:flutter/material.dart';

class SlidePanel extends StatelessWidget {
  final Widget? child;
  final Offset begin;

  const SlidePanel({
    super.key,
    this.child,
    this.begin = const Offset(1.0, 0.0),
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      reverseDuration: const Duration(milliseconds: 300),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: begin,
            end: Offset.zero,
          ).animate(animation),
          child: child,
        );
      },
      child: child,
    );
  }
}
