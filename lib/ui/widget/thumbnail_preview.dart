import 'package:flutter/material.dart';
import 'dart:typed_data';
import '../../controller/player_controller.dart';
import '../../managers/thumbnail_manager.dart';

class ThumbnailPreview extends StatefulWidget {
  final PlayerController controller;
  final String url;
  final double seconds;
  final double width;
  final double height;

  const ThumbnailPreview({
    super.key,
    required this.controller,
    required this.url,
    required this.seconds,
    this.width = 160,
    this.height = 90,
  });

  @override
  State<ThumbnailPreview> createState() => _ThumbnailPreviewState();
}

class _ThumbnailPreviewState extends State<ThumbnailPreview> {
  ThumbnailManager? _manager;
  Uint8List? _thumbnailData;

  @override
  void initState() {
    super.initState();
    _initManager();
    _loadThumbnail();
  }

  @override
  void didUpdateWidget(ThumbnailPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _initManager();
    }
    if (oldWidget.seconds != widget.seconds) {
      _loadThumbnail();
    }
  }

  @override
  void dispose() {
    // The manager is owned by the controller (shared across previews); just
    // drop our reference.
    _manager = null;
    super.dispose();
  }

  void _initManager() {
    // The controller owns one manager per media URL, so the LRU cache and
    // native generator survive across hover sessions and preview remounts.
    _manager = widget.controller.thumbnailManagerFor(widget.url);
  }

  Future<void> _loadThumbnail() async {
    if (_manager == null) return;

    final data = await _manager!.getThumbnail(widget.seconds);

    if (mounted && data != null) {
      // While scrubbing, a miss keeps the previous frame visible instead of
      // flashing — sprite coverage is sparse until the sweep catches up.
      setState(() => _thumbnailData = data);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Nothing to show yet (position not swept, native generator empty):
    // collapse entirely. A broken-image placeholder box over every hover
    // reads as "previews are broken", not "previews are coming" — the time
    // bubble below carries the hover on its own until a frame exists.
    if (_thumbnailData == null) return const SizedBox.shrink();

    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white24, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black45,
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.memory(_thumbnailData!, fit: BoxFit.cover),
      ),
    );
  }
}
