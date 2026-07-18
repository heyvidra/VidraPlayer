import 'package:flutter/material.dart';

@immutable
class ResumeState {
  final int positionMillis;
  final int durationMillis;

  const ResumeState({
    required this.positionMillis,
    required this.durationMillis,
  });

  bool get hasResume => positionMillis > 0 && durationMillis > 0;

  /// Watch progress percentage (0.0 - 1.0)
  double get progress =>
      durationMillis > 0 ? positionMillis / durationMillis : 0.0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResumeState &&
          runtimeType == other.runtimeType &&
          positionMillis == other.positionMillis &&
          durationMillis == other.durationMillis;

  @override
  int get hashCode => Object.hash(positionMillis, durationMillis);
}
