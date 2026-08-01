import 'package:flutter/material.dart';

@immutable
class SwitchingState {
  final bool isSwitching;
  final String? targetQualityLabel;

  /// Monotonic id of the switch this state belongs to, bumped by every
  /// startSwitching. Exists because "cancel, then immediately switch again"
  /// delivers end+start in the same task: the overlay's StreamBuilder sees
  /// one rebuild whose latest snapshot has isSwitching still true, so an
  /// isSwitching-edge check never fires and per-switch UI state (the cancel
  /// button's reveal timer) would silently carry over from the dead switch.
  final int attempt;

  const SwitchingState({
    this.isSwitching = false,
    this.targetQualityLabel,
    this.attempt = 0,
  });

  SwitchingState copyWith({
    bool? isSwitching,
    String? targetQualityLabel,
    int? attempt,
  }) {
    return SwitchingState(
      isSwitching: isSwitching ?? this.isSwitching,
      targetQualityLabel: targetQualityLabel ?? this.targetQualityLabel,
      attempt: attempt ?? this.attempt,
    );
  }

  @override
  String toString() {
    return 'SwitchingState(isSwitching: $isSwitching, targetQualityLabel: $targetQualityLabel, attempt: $attempt)';
  }
}
