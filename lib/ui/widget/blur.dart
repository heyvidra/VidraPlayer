import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/player_effects.dart';

/// A rounded panel that blurs whatever it is drawn over.
///
/// The blur is the single most expensive thing this player draws — it reads
/// back everything underneath, the live video texture included, and gaussian
/// blurs it every frame — and it is used by the episode list, the switching
/// overlay, the dialogs, the dropdown menus and the seek feedback pill. It is
/// skipped entirely when [PlayerEffects.reduced] is set.
class BlurPanel extends StatelessWidget {
  final Widget child;

  const BlurPanel({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    // The clip stays either way — callers lean on it for their rounded
    // corners, so dropping it would square them off. Only the filter goes.
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: PlayerEffects.reduced
          ? child
          : BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
              child: child,
            ),
    );
  }
}
