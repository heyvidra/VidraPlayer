import 'package:flutter/material.dart';

@immutable
class SwitchingState {
  final bool isSwitching;
  final String? targetQualityLabel;

  const SwitchingState({this.isSwitching = false, this.targetQualityLabel});

  SwitchingState copyWith({bool? isSwitching, String? targetQualityLabel}) {
    return SwitchingState(
      isSwitching: isSwitching ?? this.isSwitching,
      targetQualityLabel: targetQualityLabel ?? this.targetQualityLabel,
    );
  }

  @override
  String toString() {
    return 'SwitchingState(isSwitching: $isSwitching, targetQualityLabel: $targetQualityLabel)';
  }
}
