import 'package:flutter/foundation.dart';

import '../model/model.dart';

enum SeekSource {
  userDrag,
  external, // Init resume / Switch episode / Code call
}

@immutable
class PlaybackPositionState {
  final Duration position;
  final Duration duration;
  final List<BufferRange> buffered;

  /// Whether currently seeking (user or external)
  final bool isSeeking;

  /// Seek target (milliseconds)
  final Duration? seekTarget;

  /// Source of this seek (for debugging & behavior distinction)
  final SeekSource? seekSource;

  /// Whether this is a live stream
  final bool isLive;

  const PlaybackPositionState({
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.buffered = const <BufferRange>[],
    this.isSeeking = false,
    this.seekTarget,
    this.seekSource,
    this.isLive = false,
  });

  double get progress => isLive
      ? 1.0
      : (duration.inMilliseconds == 0
          ? 0
          : position.inMilliseconds / duration.inMilliseconds);

  /// [clearSeek] resets [seekTarget] and [seekSource] to null — `?? this.x`
  /// semantics make passing `seekTarget: null` a silent no-op, which
  /// previously left a stale seek target behind after every completed seek.
  PlaybackPositionState copyWith({
    Duration? position,
    Duration? duration,
    List<BufferRange>? buffered,
    bool? isSeeking,
    Duration? seekTarget,
    SeekSource? seekSource,
    bool? isLive,
    bool clearSeek = false,
  }) {
    return PlaybackPositionState(
      position: position ?? this.position,
      duration: duration ?? this.duration,
      buffered: buffered ?? this.buffered,
      isSeeking: isSeeking ?? this.isSeeking,
      seekTarget: clearSeek ? null : (seekTarget ?? this.seekTarget),
      seekSource: clearSeek ? null : (seekSource ?? this.seekSource),
      isLive: isLive ?? this.isLive,
    );
  }

  bool get hasDuration => duration > Duration.zero;

  // Value equality lets ValueNotifier/emission guards swallow no-op updates
  // (e.g. adapters re-reporting an identical buffered list every tick), so
  // position consumers only get notified when something actually changed.
  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is PlaybackPositionState &&
            runtimeType == other.runtimeType &&
            position == other.position &&
            duration == other.duration &&
            isSeeking == other.isSeeking &&
            seekTarget == other.seekTarget &&
            seekSource == other.seekSource &&
            isLive == other.isLive &&
            listEquals(buffered, other.buffered);
  }

  @override
  int get hashCode => Object.hash(
        position,
        duration,
        isSeeking,
        seekTarget,
        seekSource,
        isLive,
        Object.hashAll(buffered),
      );

  @override
  String toString() {
    return 'PlaybackPositionState(position: $position, duration: $duration, isLive: $isLive, buffered: $buffered)';
  }
}
