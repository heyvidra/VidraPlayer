import 'package:flutter/material.dart';

@immutable
class BufferingState {
  final bool isBuffering;

  /// The hardcoded simple message (optional)
  final String? message;

  /// Localization key for the message (optional, replaces [message])
  final String? messageKey;

  /// Arguments for the localization key (optional)
  final Map<String, String>? messageArgs;

  const BufferingState({
    this.isBuffering = false,
    this.message,
    this.messageKey,
    this.messageArgs,
  });
}
