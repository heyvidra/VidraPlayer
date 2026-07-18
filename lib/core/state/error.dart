import 'package:flutter/material.dart';

import '../model/player_error.dart';

@immutable
class ErrorState {
  final PlayerError? error;

  const ErrorState({this.error});

  bool get hasError => error != null;
}
