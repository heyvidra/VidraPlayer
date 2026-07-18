import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../controller/player_controller.dart';
import '../../core/model/model.dart';
import '../../core/state/states.dart';
import '../../utils/util.dart';
import '../widget/thumbnail_preview.dart';

class VideoProgressBar extends StatefulWidget {
  /// Position updates are consumed internally: per-tick changes only drive the
  /// CustomPainter's repaint listenable (no widget rebuild); the subtree
  /// rebuilds only when duration / buffered / isLive actually change. Keeping
  /// ticks out of the parent's build path is the whole point — don't wrap this
  /// widget in a position-driven builder.
  final ValueListenable<PlaybackPositionState> positionListenable;
  final ValueChanged<Duration>? onSeek;
  final VoidCallback? onSeekStart;
  final VoidCallback? onSeekEnd;
  final Color? playedColor;
  final Color? bufferedColor;
  final Color? handleColor;
  final double barHeight;
  final double handleRadius;
  final double padding;
  final bool thumbVisible;
  final PlayerController? controller;

  const VideoProgressBar({
    super.key,
    required this.positionListenable,
    this.onSeek,
    this.onSeekStart,
    this.onSeekEnd,
    this.playedColor,
    this.bufferedColor,
    this.handleColor,
    this.barHeight = 3.0,
    this.handleRadius = 6.0,
    this.padding = 12,
    this.thumbVisible = true,
    this.controller,
  });

  @override
  State<VideoProgressBar> createState() => _VideoProgressBarState();
}

class _VideoProgressBarState extends State<VideoProgressBar>
    with TickerProviderStateMixin {
  late final ValueNotifier<double> _currentPosition;

  late final AnimationController _toggleController;
  late final Animation<double> _toggleAnimation;

  bool _isDragging = false;
  bool _isSeeking = false;
  double? _seekTarget;

  late final ValueNotifier<double?> _hoverX;
  late final ValueNotifier<bool> _isHovering;

  late final AnimationController _hoverController;
  late final Animation<double> _hoverAnimation;

  // Snapshot of the last seen position state. Structural fields (duration,
  // buffered, isLive) trigger setState when they change; the position itself
  // never does — it flows into [_currentPosition] paint-only.
  late PlaybackPositionState _lastState;

  @override
  void initState() {
    super.initState();
    _lastState = widget.positionListenable.value;
    _currentPosition = ValueNotifier(_displayPositionMs(_lastState));
    _hoverX = ValueNotifier(null);
    _isHovering = ValueNotifier(false);
    widget.positionListenable.addListener(_onPositionChanged);

    _toggleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _toggleAnimation = CurvedAnimation(
      parent: _toggleController,
      curve: Curves.easeInOut,
    );

    _hoverController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _hoverAnimation = CurvedAnimation(
      parent: _hoverController,
      curve: Curves.easeOutCubic,
    );

    if (widget.thumbVisible) {
      _toggleController.value = 1.0;
    }
  }

  @override
  void dispose() {
    // MouseRegion.onExit is NOT invoked when the region is unmounted while
    // hovered (documented Flutter caveat). onEnter switched the controls to
    // persistent (auto-hide timer cancelled), so mirror onExit here or the
    // controls stay pinned visible after a layout flip unmounts the bar.
    if (_isHovering.value) {
      widget.controller?.showControlsTemporarily();
    }
    widget.positionListenable.removeListener(_onPositionChanged);
    _toggleController.dispose();
    _hoverController.dispose();
    _currentPosition.dispose();
    _hoverX.dispose();
    _isHovering.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant VideoProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!identical(
      oldWidget.positionListenable,
      widget.positionListenable,
    )) {
      oldWidget.positionListenable.removeListener(_onPositionChanged);
      widget.positionListenable.addListener(_onPositionChanged);
      _lastState = widget.positionListenable.value;
    }

    if (oldWidget.thumbVisible != widget.thumbVisible) {
      if (widget.thumbVisible) {
        _toggleController.forward();
      } else {
        _toggleController.reverse();
      }
    }
  }

  /// External seeks pin the display to the seek target until the player
  /// catches up; otherwise show the raw position.
  static double _displayPositionMs(PlaybackPositionState state) {
    final displayed = state.isSeeking && state.seekTarget != null
        ? state.seekTarget!
        : state.position;
    return displayed.inMilliseconds.toDouble();
  }

  void _onPositionChanged() {
    final state = widget.positionListenable.value;
    final prev = _lastState;
    _lastState = state;

    // Structural changes are rare (duration once per media, buffered on real
    // buffer progress, isLive once) — only they rebuild the subtree.
    if (state.duration != prev.duration ||
        state.isLive != prev.isLive ||
        !listEquals(state.buffered, prev.buffered)) {
      setState(() {});
    }

    if (state.isLive != prev.isLive && state.isLive) {
      _currentPosition.value = state.duration.inMilliseconds.toDouble();
    }

    if (_isDragging) return;

    final newPos = _displayPositionMs(state);

    if (_isSeeking && _seekTarget != null) {
      // Hold the dragged-to value until the player reports a position near
      // the target, so the handle doesn't snap back mid-seek.
      const double threshold = 1000.0;
      final delta = (newPos - _seekTarget!).abs();

      if (delta < threshold) {
        _isSeeking = false;
        _seekTarget = null;
        _currentPosition.value = newPos;
      }
    } else {
      _currentPosition.value = newPos;
    }
  }

  void _handleSliderChanged(double value) {
    if (!_isDragging) _isDragging = true;
    _currentPosition.value = value;
    widget.controller?.showControlsTemporarily();
  }

  void _handleSliderChangeStart(double value) {
    _isDragging = true;
    _currentPosition.value = value;
    widget.controller?.showControlsPersistently();
    widget.onSeekStart?.call();
  }

  void _handleSliderChangeEnd(double value) {
    _isDragging = false;
    _isSeeking = true;
    _seekTarget = value;
    _currentPosition.value = value;
    widget.onSeek?.call(Duration(milliseconds: value.toInt()));
    widget.controller?.showControlsTemporarily();
    widget.onSeekEnd?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (_lastState.isLive) return _buildLiveProgressBar();

    final double maxDuration = _lastState.duration.inMilliseconds.toDouble();

    return MouseRegion(
      hitTestBehavior: HitTestBehavior.opaque,
      onEnter: (_) {
        _isHovering.value = true;
        _hoverController.forward();
        widget.controller?.showControlsPersistently();
      },
      onExit: (_) {
        _isHovering.value = false;
        _hoverController.reverse();
        widget.controller?.showControlsTemporarily();
      },
      onHover: (event) {
        _hoverX.value = event.localPosition.dx;
        widget.controller?.showControlsTemporarily();
      },
      child: RepaintBoundary(
        child: SizedBox(
          height: widget.barHeight + widget.padding * 2,
          // Measure the bar's OWN width. hoverX (event.localPosition.dx) is in
          // this box's coordinate space, so the tooltip/time math must use this
          // width — MediaQuery screen width is wrong whenever the player isn't
          // full-width (windowed desktop, split pane, PiP) and mispositions the
          // tooltip + thumbnail.
          child: LayoutBuilder(
            builder: (context, constraints) {
              final barWidth = constraints.maxWidth;
              return Stack(
                clipBehavior: Clip.none,
                children: [
              // CustomPaint for zero-layout updates
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: widget.padding),
                  child: CustomPaint(
                    painter: ProgressBarPainter(
                      position: _currentPosition,
                      duration: maxDuration,
                      buffered: _lastState.buffered,
                      toggleAnimation: _toggleAnimation,
                      hoverAnimation: _hoverAnimation,
                      playedColor: widget.playedColor ?? Colors.red,
                      bufferedColor: widget.bufferedColor ?? Colors.white38,
                      backgroundColor: Colors.white24,
                      handleColor: widget.handleColor ?? Colors.red,
                      barHeight: widget.barHeight,
                      handleRadius: widget.handleRadius,
                    ),
                  ),
                ),
              ),

              // Invisible Slider for interactions
              Padding(
                padding: EdgeInsets.symmetric(horizontal: widget.padding),
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: widget.barHeight * 2,
                    trackShape: _ZeroPaddingTrackShape(),
                    activeTrackColor: Colors.transparent,
                    inactiveTrackColor: Colors.transparent,
                    thumbColor: Colors.transparent,
                    thumbShape: _InvisibleThumbShape(),
                    overlayColor: Colors.transparent,
                  ),
                  child: ValueListenableBuilder<double>(
                    valueListenable: _currentPosition,
                    builder: (context, currentPos, _) {
                      return Slider(
                        padding: EdgeInsets.zero,
                        value: currentPos.clamp(0.0, maxDuration),
                        min: 0.0,
                        max: maxDuration,
                        onChanged: _handleSliderChanged,
                        onChangeStart: _handleSliderChangeStart,
                        onChangeEnd: _handleSliderChangeEnd,
                      );
                    },
                  ),
                ),
              ),
                  _buildHoverTooltipWrapper(maxDuration, barWidth),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildLiveProgressBar() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: widget.padding),
      child: Container(
        width: double.infinity,
        height: widget.barHeight,
        decoration: BoxDecoration(
          color: widget.playedColor ?? Colors.red,
          borderRadius: BorderRadius.circular(widget.barHeight / 2),
        ),
      ),
    );
  }


  Widget _buildHoverTooltipWrapper(double maxDuration, double width) {
    return ValueListenableBuilder<bool>(
      valueListenable: _isHovering,
      builder: (context, isHovering, child) {
        if (!isHovering && !_isDragging) return const SizedBox.shrink();

        return ValueListenableBuilder<double?>(
          valueListenable: _hoverX,
          builder: (context, hoverX, child) {
            return ValueListenableBuilder<double>(
              valueListenable: _currentPosition,
              builder: (context, currentPos, child) {
                final effectiveWidth = width - widget.padding * 2;
                final double displayTime;
                final double innerDisplayX;

                if (_isDragging) {
                  displayTime = currentPos;
                  final percent = maxDuration > 0
                      ? (currentPos / maxDuration).clamp(0.0, 1.0)
                      : 0.0;
                  innerDisplayX = percent * effectiveWidth;
                } else {
                  if (hoverX == null || width <= 0) {
                    return const SizedBox.shrink();
                  }
                  final relativeX = (hoverX - widget.padding).clamp(
                    0.0,
                    effectiveWidth,
                  );
                  displayTime = effectiveWidth > 0
                      ? (relativeX / effectiveWidth) * maxDuration
                      : 0.0;
                  innerDisplayX = relativeX;
                }

                final duration = Duration(milliseconds: displayTime.toInt());

                final bool showThumbnail =
                    widget.controller != null &&
                    widget.controller!.enableThumbnail;
                final double tooltipWidth = showThumbnail ? 160.0 : 50.0;

                final double leftPos =
                    (widget.padding + innerDisplayX - (tooltipWidth / 2)).clamp(
                      0.0,
                      width - tooltipWidth,
                    );

                return Positioned(
                  left: leftPos,
                  bottom: 18,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (showThumbnail)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 5),
                          child: ThumbnailPreview(
                            controller: widget.controller!,
                            url: widget
                                .controller!
                                .media
                                .currentEpisode!
                                .qualities
                                .first
                                .source
                                .path,
                            // Quantize to whole seconds: the thumbnail cache is
                            // second-keyed anyway, and per-pixel fractional
                            // values would re-trigger a load on every hover
                            // movement.
                            seconds: (displayTime / 1000).floorToDouble(),
                          ),
                        ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          Util.formatDuration(duration),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class ProgressBarPainter extends CustomPainter {
  final ValueNotifier<double> position;
  final double duration;
  final List<BufferRange> buffered;
  final Animation<double> toggleAnimation;
  final Animation<double> hoverAnimation;
  final Color playedColor;
  final Color bufferedColor;
  final Color backgroundColor;
  final Color handleColor;
  final double barHeight;
  final double handleRadius;

  ProgressBarPainter({
    required this.position,
    required this.duration,
    required this.buffered,
    required this.toggleAnimation,
    required this.hoverAnimation,
    required this.playedColor,
    required this.bufferedColor,
    required this.backgroundColor,
    required this.handleColor,
    required this.barHeight,
    required this.handleRadius,
  }) : super(
         repaint: Listenable.merge([position, toggleAnimation, hoverAnimation]),
       );

  @override
  void paint(Canvas canvas, Size size) {
    if (duration <= 0) return;

    final toggleValue = toggleAnimation.value;
    final hoverValue = hoverAnimation.value;

    final trackHoverScale = 1.0 + (hoverValue * 1.0);
    final thumbHoverScale = 1.0 + (hoverValue * 0.2);

    final currentHeight =
        (2.0 + (barHeight - 2.0) * toggleValue) * trackHoverScale;
    final currentRadius = (handleRadius * toggleValue) * thumbHoverScale;

    final centerY = size.height / 2;
    final barRect = Rect.fromLTWH(
      0,
      centerY - currentHeight / 2,
      size.width,
      currentHeight,
    );
    final RRect barRRect = RRect.fromRectAndRadius(
      barRect,
      Radius.circular(currentHeight / 2),
    );

    // 1. Draw Background
    final Paint bgPaint = Paint()..color = backgroundColor;
    canvas.drawRRect(barRRect, bgPaint);

    // 2. Draw Buffered Ranges
    final Paint bufferPaint = Paint()..color = bufferedColor;
    for (final range in buffered) {
      final start =
          (range.start.inMilliseconds / duration).clamp(0.0, 1.0) * size.width;
      final end =
          (range.end.inMilliseconds / duration).clamp(0.0, 1.0) * size.width;
      if (end > start) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              start,
              centerY - currentHeight / 2,
              end - start,
              currentHeight,
            ),
            Radius.circular(currentHeight / 2),
          ),
          bufferPaint,
        );
      }
    }

    // 3. Draw Played Progress
    final playedWidth =
        (position.value / duration).clamp(0.0, 1.0) * size.width;
    final Paint playedPaint = Paint()..color = playedColor;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          0,
          centerY - currentHeight / 2,
          playedWidth,
          currentHeight,
        ),
        Radius.circular(currentHeight / 2),
      ),
      playedPaint,
    );

    // 4. Draw Handle
    if (toggleValue > 0) {
      final Paint handlePaint = Paint()
        ..color = handleColor.withValues(alpha: toggleValue);
      canvas.drawCircle(
        Offset(playedWidth, centerY),
        currentRadius,
        handlePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant ProgressBarPainter oldDelegate) => true;
}

class _ZeroPaddingTrackShape extends RoundedRectSliderTrackShape {
  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final trackHeight = sliderTheme.trackHeight ?? 2.0;
    final trackLeft = offset.dx;
    final trackTop = offset.dy + (parentBox.size.height - trackHeight) / 2;
    final trackWidth = parentBox.size.width;
    return Rect.fromLTWH(trackLeft, trackTop, trackWidth, trackHeight);
  }
}

class _InvisibleThumbShape extends SliderComponentShape {
  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(20, 20);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    // Zero-draw: ensures no shadow or default material artifacts appear
  }
}
