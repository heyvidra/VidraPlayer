import 'package:flutter/material.dart';

@immutable
class PlayerError {
  final String code;
  final String message;
  final String? details;
  final DateTime timestamp;
  final StackTrace? stackTrace;

  PlayerError({
    required this.code,
    required this.message,
    this.details,
    DateTime? timestamp,
    this.stackTrace,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  String toString() =>
      'PlayerError[$code]: $message${details != null ? '\n$details' : ''}';
}
