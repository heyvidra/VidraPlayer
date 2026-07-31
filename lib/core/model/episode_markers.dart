import 'package:flutter/foundation.dart';

/// Where a marker came from. Order is precedence: a later value overwrites an
/// earlier one, so a hand-placed marker survives a chapter probe or a detector
/// run and never has to be re-entered.
enum MarkerSource { chapter, detected, manual }

/// Intro/outro boundaries for ONE episode.
///
/// These are absolute times into the media, unlike the series-wide
/// [PlayerSetting.skipIntro] / [PlayerSetting.skipOutro] seconds they take
/// precedence over — those are a single pair for the whole video and cannot
/// describe an intro that moves between episodes. [PlayerSetting] stays the
/// fallback, so nothing that only sets those breaks.
@immutable
class EpisodeMarkers {
  final int episodeIndex;

  /// Where the intro begins. Null means "from the start" — only useful for
  /// showing a skip button in the right window; skipping itself uses
  /// [introEnd].
  final Duration? introStart;

  /// Where the intro ends — the seek target when skipping it.
  final Duration? introEnd;

  /// Where the end credits begin.
  final Duration? outroStart;

  final MarkerSource source;

  const EpisodeMarkers({
    required this.episodeIndex,
    this.introStart,
    this.introEnd,
    this.outroStart,
    this.source = MarkerSource.manual,
  });

  bool get isEmpty => introEnd == null && outroStart == null;

  /// True when this should replace [other]. Equal sources also replace, so a
  /// re-run of the same source refreshes rather than sticking to a stale value.
  bool outranks(EpisodeMarkers other) => source.index >= other.source.index;

  /// Seconds of tail after [outroStart], which is what the auto-skip logic and
  /// [PlayerSetting.skipOutro] are expressed in. 0 when there is no outro.
  int outroTailSeconds(Duration mediaDuration) {
    final start = outroStart;
    if (start == null || mediaDuration <= Duration.zero) return 0;
    final tail = mediaDuration - start;
    return tail.isNegative ? 0 : tail.inSeconds;
  }

  EpisodeMarkers copyWith({
    int? episodeIndex,
    Duration? introStart,
    Duration? introEnd,
    Duration? outroStart,
    MarkerSource? source,
  }) {
    return EpisodeMarkers(
      episodeIndex: episodeIndex ?? this.episodeIndex,
      introStart: introStart ?? this.introStart,
      introEnd: introEnd ?? this.introEnd,
      outroStart: outroStart ?? this.outroStart,
      source: source ?? this.source,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EpisodeMarkers &&
          episodeIndex == other.episodeIndex &&
          introStart == other.introStart &&
          introEnd == other.introEnd &&
          outroStart == other.outroStart &&
          source == other.source;

  @override
  int get hashCode =>
      Object.hash(episodeIndex, introStart, introEnd, outroStart, source);

  @override
  String toString() =>
      'EpisodeMarkers(episode: $episodeIndex, intro: $introStart-$introEnd, '
      'outro: $outroStart, source: ${source.name})';
}
