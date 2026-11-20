import 'package:material_ui/material_ui.dart';

import 'video_source.dart';

@immutable
class VideoQuality {
  final String label;
  final VideoSource source;
  final String? resolution;
  final int? bitrate;
  final String? codec;

  const VideoQuality({
    required this.label,
    required this.source,
    this.resolution,
    this.bitrate,
    this.codec,
  });
}
