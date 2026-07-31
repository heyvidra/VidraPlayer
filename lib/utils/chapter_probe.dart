import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/model/episode_markers.dart';
import 'log.dart';

/// A chapter read out of the media's own metadata.
class Chapter {
  final Duration start;
  final String title;

  const Chapter({required this.start, required this.title});

  @override
  String toString() => 'Chapter($start, "$title")';
}

// Titles/IDs publishers actually use. Deliberately loose: a false match costs
// one wrong marker the user can fix by right-clicking, a miss costs the whole
// feature. Bare "op"/"ed" are excluded — too many false hits on real words.
final RegExp _introPattern = RegExp(
  r'\b(intro|opening|openning|title\s*sequence)\b|片头|片頭|オープニング',
  caseSensitive: false,
);
final RegExp _outroPattern = RegExp(
  r'\b(outro|ending|credits|end\s*credits|closing)\b|片尾|片尾曲|エンディング',
  caseSensitive: false,
);

/// Parse chapters out of an HLS media playlist.
///
/// Only `#EXT-X-DATERANGE` carries them, and its START-DATE is a wall-clock
/// timestamp — meaningless on its own, so it is resolved against the first
/// `#EXT-X-PROGRAM-DATE-TIME` to get a media offset. A playlist with dateranges
/// but no program-date-time yields nothing; there is no other anchor.
List<Chapter> parseHlsChapters(String playlist) {
  DateTime? anchor;
  final chapters = <Chapter>[];

  for (final raw in const LineSplitter().convert(playlist)) {
    final line = raw.trim();

    if (line.startsWith('#EXT-X-PROGRAM-DATE-TIME:')) {
      anchor ??= DateTime.tryParse(line.substring(25).trim());
      continue;
    }
    if (!line.startsWith('#EXT-X-DATERANGE:')) continue;

    final attrs = _parseAttributes(line.substring(17));
    final startDate = DateTime.tryParse(attrs['START-DATE'] ?? '');
    if (anchor == null || startDate == null) continue;

    // A title can live in any of these depending on the packager.
    final title = attrs['X-TITLE'] ?? attrs['TITLE'] ?? attrs['ID'] ?? '';
    if (title.isEmpty) continue;

    final offset = startDate.difference(anchor);
    if (offset.isNegative) continue;
    chapters.add(Chapter(start: offset, title: title));
  }

  chapters.sort((a, b) => a.start.compareTo(b.start));
  return chapters;
}

/// Pick out the intro/outro chapters. Returns null when nothing recognisable is
/// in there — an unlabelled chapter list tells us nothing about where the intro
/// is, and guessing "chapter 1 is the intro" is wrong more often than not.
EpisodeMarkers? markersFromChapters(
  List<Chapter> chapters,
  int episodeIndex, {
  Duration? mediaDuration,
}) {
  Duration? introStart, introEnd, outroStart;

  for (var i = 0; i < chapters.length; i++) {
    final chapter = chapters[i];
    // A chapter's end is the next chapter's start; the last one runs to the
    // end of the media (unknown here unless the caller passed it).
    final end = i + 1 < chapters.length ? chapters[i + 1].start : mediaDuration;

    if (introEnd == null && _introPattern.hasMatch(chapter.title)) {
      introStart = chapter.start;
      introEnd = end;
    } else if (_outroPattern.hasMatch(chapter.title)) {
      // Last outro-ish chapter wins: "Ending" then "Preview" both match late,
      // and the earliest credits boundary is the useful one.
      outroStart ??= chapter.start;
    }
  }

  if (introEnd == null && outroStart == null) return null;
  return EpisodeMarkers(
    episodeIndex: episodeIndex,
    introStart: introStart,
    introEnd: introEnd,
    outroStart: outroStart,
    source: MarkerSource.chapter,
  );
}

/// Fetch [url] and read its chapters. HLS only — probing an mp4 would download
/// the whole file, so anything that isn't a playlist is skipped outright.
///
/// Never throws and never runs longer than [timeout]: this sits in the episode
/// load path and a slow CDN must not hold up playback.
Future<EpisodeMarkers?> probeChapters(
  String url,
  int episodeIndex, {
  Duration? mediaDuration,
  Duration timeout = const Duration(seconds: 3),
}) async {
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.path.toLowerCase().endsWith('.m3u8')) return null;

  final client = HttpClient()..connectionTimeout = timeout;
  try {
    var body = await _get(client, uri).timeout(timeout);
    if (body == null) return null;

    // Master playlist: chapters live in the variant, so follow the first one.
    final variant = _firstVariant(body, uri);
    if (variant != null) {
      body = await _get(client, variant).timeout(timeout);
      if (body == null) return null;
    }

    return markersFromChapters(
      parseHlsChapters(body),
      episodeIndex,
      mediaDuration: mediaDuration,
    );
  } catch (e) {
    logger.d('[ChapterProbe] no chapters for $url: $e');
    return null;
  } finally {
    client.close(force: true);
  }
}

Future<String?> _get(HttpClient client, Uri uri) async {
  final response = await (await client.getUrl(uri)).close();
  if (response.statusCode != 200) {
    unawaited(response.drain<void>());
    return null;
  }
  return response.transform(utf8.decoder).join();
}

/// The first `#EXT-X-STREAM-INF` target, or null if this is already a media
/// playlist.
Uri? _firstVariant(String playlist, Uri base) {
  final lines = const LineSplitter().convert(playlist);
  for (var i = 0; i < lines.length; i++) {
    if (!lines[i].startsWith('#EXT-X-STREAM-INF')) continue;
    for (var j = i + 1; j < lines.length; j++) {
      final candidate = lines[j].trim();
      if (candidate.isEmpty || candidate.startsWith('#')) continue;
      return base.resolve(candidate);
    }
  }
  return null;
}

/// Split an HLS attribute list, honouring quoted values (which may contain
/// commas — ISO timestamps with offsets do).
Map<String, String> _parseAttributes(String input) {
  final attrs = <String, String>{};
  final pattern = RegExp(r'([A-Za-z0-9\-]+)=("[^"]*"|[^,]*)');
  for (final match in pattern.allMatches(input)) {
    var value = match.group(2) ?? '';
    if (value.startsWith('"') && value.endsWith('"') && value.length >= 2) {
      value = value.substring(1, value.length - 1);
    }
    attrs[match.group(1)!.toUpperCase()] = value;
  }
  return attrs;
}
