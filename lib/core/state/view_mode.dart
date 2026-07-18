import 'package:flutter/material.dart';

@immutable
class ViewModeState {
  final bool isFullscreen;
  final bool isPip;

  const ViewModeState({this.isFullscreen = false, this.isPip = false});

  ViewModeState copyWith({bool? isFullscreen, bool? isPip}) {
    return ViewModeState(
      isFullscreen: isFullscreen ?? this.isFullscreen,
      isPip: isPip ?? this.isPip,
    );
  }
}
