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
  bool _isLoading = false;

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

    // Only show the spinner when we have nothing to display yet — while
    // scrubbing, keep the previous frame visible instead of flashing.
    if (_thumbnailData == null && !_isLoading) {
      setState(() {
        _isLoading = true;
      });
    }

    final data = await _manager!.getThumbnail(widget.seconds);

    if (mounted) {
      setState(() {
        if (data != null) {
          _thumbnailData = data;
        }
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_thumbnailData != null)
              Image.memory(_thumbnailData!, fit: BoxFit.cover)
            else if (_isLoading)
              const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                  ),
                ),
              )
            else
              const Center(
                child: Icon(
                  Icons.image_not_supported,
                  color: Colors.white24,
                  size: 24,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
