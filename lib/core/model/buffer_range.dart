import 'package:flutter/material.dart';

@immutable
class BufferRange {
  final Duration start;
  final Duration end;

  const BufferRange({required this.start, required this.end});

  bool contains(Duration position) {
    return position >= start && position <= end;
  }

  Duration get length => end - start;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BufferRange && start == other.start && end == other.end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'BufferRange($start → $end)';
}
