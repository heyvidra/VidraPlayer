import 'dart:ui';

import 'package:flutter/material.dart';

class BlurPanel extends StatelessWidget {
  final Widget child;

  const BlurPanel({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: child,
      ),
    );
  }
}
