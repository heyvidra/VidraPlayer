import 'package:flutter/material.dart';

import 'enums.dart';

@immutable
class VideoSource {
  final VideoSourceType type;
  final String path;

  const VideoSource.network(this.path) : type = VideoSourceType.network;
  const VideoSource.file(this.path) : type = VideoSourceType.file;
  const VideoSource.asset(this.path) : type = VideoSourceType.asset;
}

@immutable
class VideoSize {
  final int width;
  final int height;

  const VideoSize(this.width, this.height);

  double get aspectRatio => width / height;
}
