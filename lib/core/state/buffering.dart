// foundation, not material: this file needs @immutable and mapEquals, both of
// which live here, and a state class has no business dragging in a UI library.
import 'package:flutter/foundation.dart';

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

  // Value equality, because tick-driven adapters build a fresh instance on
  // every poll: fvp's `_onTick` runs ~10x a second off video_player's 100ms
  // position timer and allocates `BufferingState(isBuffering: ...)` each time.
  // Under identity comparison every one of those is a distinct object, so the
  // buffering stream fanned out at tick rate for the whole of playback —
  // rebuilding the indicator's StreamBuilder ten times a second to draw the
  // same nothing. The guard lives in PlaybackManager; it needs this to work.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BufferingState &&
          isBuffering == other.isBuffering &&
          message == other.message &&
          messageKey == other.messageKey &&
          mapEquals(messageArgs, other.messageArgs);

  // messageArgs contributes its LENGTH, not its contents: equal maps have
  // equal length, which is all the hash contract asks, and it keeps this off
  // the "hash depends on iteration order" rake.
  @override
  int get hashCode =>
      Object.hash(isBuffering, message, messageKey, messageArgs?.length);
}
