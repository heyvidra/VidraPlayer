import 'package:flutter/material.dart';

import 'enums.dart';

@immutable
class VideoSource {
  final VideoSourceType type;
  final String path;

  /// HTTP headers to open a network source with, replacing the adapter's
  /// default set outright rather than merging into it.
  ///
  /// The default guesses (see `getHttpProxyHeaders`) suit a CDN that wants to
  /// see a request refer to itself, which is the common anti-hotlinking shape.
  /// It is not universal: some CDNs answer 520 to exactly that referer and
  /// want a plain user agent instead. A host that knows what its CDN expects
  /// says so here; every other source leaves this null and keeps the defaults.
  final Map<String, String>? headers;

  const VideoSource.network(this.path, {this.headers})
    : type = VideoSourceType.network;
  const VideoSource.file(this.path) : type = VideoSourceType.file, headers = null;
  const VideoSource.asset(this.path)
    : type = VideoSourceType.asset,
      headers = null;
}

@immutable
class VideoSize {
  final int width;
  final int height;

  const VideoSize(this.width, this.height);

  double get aspectRatio => width / height;
}
