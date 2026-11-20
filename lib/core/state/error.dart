import 'package:material_ui/material_ui.dart';

import '../model/player_error.dart';

@immutable
class ErrorState {
  final PlayerError? error;

  const ErrorState({this.error});

  bool get hasError => error != null;
}
