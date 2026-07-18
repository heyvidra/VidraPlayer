import 'package:flutter/material.dart';

@immutable
class VideoMetadata {
  final String id;
  final String title;
  final String coverUrl;

  const VideoMetadata({
    required this.id,
    required this.title,
    required this.coverUrl,
  });
}
