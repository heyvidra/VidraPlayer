import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../controller/player_controller.dart';
import '../../core/model/model.dart';
import '../../core/state/states.dart';
import '../../utils/util.dart';
import '../widget/dropdown_menu.dart';
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

  OverlayEntry? _markerMenu;

  // Markers arrive on the media stream, not the position stream, so the paint
  // -only path the rest of this widget is built around can't see them. This is
  // the one extra subscription — it setStates only when the drawn values
  // actually move, so it costs nothing per tick.
  StreamSubscription<MediaContextState>? _mediaSub;
  EpisodeMarkers? _markers;

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

    final controller = widget.controller;
    if (controller != null) {
      _markers = controller.currentMarkers;
      _mediaSub = controller.mediaStream.listen((state) {
        final next = state.episodeMarkers[state.currentEpisodeIndex];
        if (next == _markers) return;
        if (mounted) setState(() => _markers = next);
      });
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
    _closeMarkerMenu();
    _mediaSub?.cancel();
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

    if (!identical(oldWidget.positionListenable, widget.positionListenable)) {
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
              return GestureDetector(
                // Right-click marks the intro/outro boundary at the clicked
                // time. Opaque so the padded edges of the bar are covered too.
                behavior: HitTestBehavior.opaque,
                onSecondaryTapDown: widget.controller == null
                    ? null
                    : (d) => _showMarkerMenu(context, d, barWidth, maxDuration),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // CustomPaint for zero-layout updates
                    Positioned.fill(
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: widget.padding,
                        ),
                        child: CustomPaint(
                          painter: ProgressBarPainter(
                            position: _currentPosition,
                            duration: maxDuration,
                            buffered: _lastState.buffered,
                            toggleAnimation: _toggleAnimation,
                            hoverAnimation: _hoverAnimation,
                            hoverX: _hoverX,
                            horizontalPadding: widget.padding,
                            playedColor: widget.playedColor ?? Colors.red,
                            bufferedColor:
                                widget.bufferedColor ?? Colors.white38,
                            backgroundColor: Colors.white24,
                            handleColor: widget.handleColor ?? Colors.red,
                            barHeight: widget.barHeight,
                            handleRadius: widget.handleRadius,
                            introEndMs: _drawnMarkers?.introEnd?.inMilliseconds
                                .toDouble(),
                            outroStartMs: _drawnMarkers
                                ?.outroStart
                                ?.inMilliseconds
                                .toDouble(),
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
                ),
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

  /// The markers to draw. A cleared record means "nothing here", not "these
  /// null fields merge onto whatever was drawn before".
  EpisodeMarkers? get _drawnMarkers {
    final m = _markers;
    return (m == null || m.clear) ? null : m;
  }

  /// Right-click menu: mark the clicked time as the intro end or the outro
  /// start. skipIntro is seconds from the start, skipOutro seconds from the end
  /// (see SkipDelegate), so the outro value is the remainder.
  void _showMarkerMenu(
    BuildContext context,
    TapDownDetails details,
    double width,
    double maxDuration,
  ) {
    final controller = widget.controller;
    if (controller == null || maxDuration <= 0 || _markerMenu != null) return;

    final marks = markerSecondsAt(
      localDx: details.localPosition.dx,
      width: width,
      padding: widget.padding,
      maxDurationMs: maxDuration,
    );
    if (marks == null) return;
    // Both entries record — and display — the SAME clicked time. Showing the
    // intro row as an absolute time and the outro row as a remaining duration
    // made the two rows read against different baselines, which cost users a
    // beat of arithmetic to work out they had clicked one spot, not two.
    final (intro: fromStart, outro: _) = marks;
    final clicked = Duration(seconds: fromStart);

    final l10n = controller.localization;
    final theme = controller.config.theme;
    final tap = details.globalPosition;

    final entry = OverlayEntry(
      builder: (context) => LayoutBuilder(
        builder: (context, constraints) {
          const menuWidth = 220.0;
          final left = (tap.dx - menuWidth / 2).clamp(
            8.0,
            (constraints.maxWidth - menuWidth - 8).clamp(8.0, double.infinity),
          );
          return Stack(
            children: [
              // Close on click outside, same as VDropdownMenu's barrier.
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _closeMarkerMenu,
                  onSecondaryTap: _closeMarkerMenu,
                  child: const SizedBox.expand(),
                ),
              ),
              Positioned(
                left: left,
                // Open upward: the bar sits at the bottom of the player.
                bottom: constraints.maxHeight - tap.dy + 8,
                width: menuWidth,
                child: Material(
                  type: MaterialType.transparency,
                  child: PlayerMenuPanel(
                    theme: theme,
                    children: [
                      PlayerMenuItem(
                        leading: const Icon(Icons.start),
                        text: l10n.translate('set_as_opening'),
                        trailing: Text(
                          Util.formatDuration(clicked),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                        onTap: () {
                          _closeMarkerMenu();
                          // Marks this episode AND becomes the series-wide
                          // default, so it persists and covers every episode.
                          controller.setSkipPoint(introEnd: clicked);
                        },
                        theme: theme,
                      ),
                      PlayerMenuItem(
                        leading: const Icon(Icons.last_page),
                        text: l10n.translate('set_as_ending'),
                        trailing: Text(
                          Util.formatDuration(clicked),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                        onTap: () {
                          _closeMarkerMenu();
                          controller.setSkipPoint(outroStart: clicked);
                        },
                        theme: theme,
                      ),
                      // Only worth offering when there is something to remove.
                      // Until now a wrong value could only be walked back 5
                      // seconds at a time, and a marker not at all.
                      if (controller.hasSkipPoints)
                        PlayerMenuItem(
                          leading: const Icon(Icons.layers_clear),
                          text: l10n.translate('clear_markers'),
                          onTap: () {
                            _closeMarkerMenu();
                            controller.clearSkipPoints();
                          },
                          theme: theme,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );

    _markerMenu = entry;
    Overlay.of(context).insert(entry);
    // Keeps the auto-hide timer disarmed while the menu's barrier is up —
    // hiding the controls underneath would strand an invisible tap-eater.
    controller.showMoreMenu();
  }

  void _closeMarkerMenu() {
    if (_markerMenu == null) return;
    _markerMenu!.remove();
    _markerMenu = null;
    widget.controller?.hideMoreMenu();
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

                // Preview and bubble are positioned INDEPENDENTLY, each
                // clamped by its own width. One shared frame clamped for the
                // 160px preview froze the bubble 80px short of either edge —
                // felt broken whenever the preview was collapsed (position
                // not swept yet). Near an edge the preview parks while the
                // bubble keeps tracking the cursor, same as every mainstream
                // player.
                const double previewWidth = 160.0;
                const double bubbleFrameWidth = 70.0;
                final double hoverCenter = widget.padding + innerDisplayX;
                final double previewLeft = (hoverCenter - previewWidth / 2)
                    .clamp(0.0, width - previewWidth);
                final double bubbleLeft = (hoverCenter - bubbleFrameWidth / 2)
                    .clamp(0.0, width - bubbleFrameWidth);

                // Clear the handle instead of sitting on it: the handle is
                // centred at height/2 and grows 20% while hovered. Floored at
                // the old flat 18 so the compact mobile layout is unchanged.
                final double tooltipBottom =
                    ((widget.barHeight + widget.padding * 2) / 2 +
                            widget.handleRadius * 1.2 +
                            8)
                        .clamp(18.0, double.infinity);
                // Bubble pill: ~16px text line + 8px vertical padding, plus
                // the 5px gap the preview keeps above it.
                const double bubbleHeight = 24.0;

                return Positioned.fill(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      if (showThumbnail)
                        Positioned(
                          left: previewLeft,
                          bottom: tooltipBottom + bubbleHeight + 5,
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
                      Positioned(
                        left: bubbleLeft,
                        bottom: tooltipBottom,
                        // Fixed frame, intrinsic pill centred inside: the
                        // clamp needs a known width, the pill keeps its size.
                        child: SizedBox(
                          width: bubbleFrameWidth,
                          height: bubbleHeight,
                          child: Center(
                            child: Container(
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

/// The two skip values a right-click at [localDx] means: `intro` is seconds
/// from the start, `outro` seconds from the END (that's how SkipDelegate reads
/// skipOutro), so they always sum to the media length. Null when the bar has no
/// usable width. [localDx] is in the bar box's own space, [padding] the
/// horizontal inset the track is drawn inside.
({int intro, int outro})? markerSecondsAt({
  required double localDx,
  required double width,
  required double padding,
  required double maxDurationMs,
}) {
  final effectiveWidth = width - padding * 2;
  if (effectiveWidth <= 0 || maxDurationMs <= 0) return null;

  final relativeX = (localDx - padding).clamp(0.0, effectiveWidth);
  final total = (maxDurationMs / 1000).round();
  final intro = (relativeX / effectiveWidth * maxDurationMs / 1000)
      .round()
      .clamp(0, total);
  return (intro: intro, outro: total - intro);
}

class ProgressBarPainter extends CustomPainter {
  final ValueNotifier<double> position;
  final double duration;
  final List<BufferRange> buffered;
  final Animation<double> toggleAnimation;
  final Animation<double> hoverAnimation;

  /// Cursor x in the BAR BOX's space (includes [horizontalPadding]); null when
  /// the mouse is elsewhere. Drives the YouTube-style fill from the track
  /// start to the cursor — a paint-only signal, same as [position].
  final ValueNotifier<double?> hoverX;
  final double horizontalPadding;
  final Color playedColor;
  final Color bufferedColor;
  final Color backgroundColor;
  final Color handleColor;
  final double barHeight;
  final double handleRadius;

  /// Absolute times of the configured skip boundaries, in ms. Drawn as bands so
  /// a skip point placed by right-click is verifiable at a glance — before this
  /// the only way to confirm one had registered was to reopen a menu.
  final double? introEndMs;
  final double? outroStartMs;

  ProgressBarPainter({
    required this.position,
    required this.duration,
    required this.buffered,
    required this.toggleAnimation,
    required this.hoverAnimation,
    required this.hoverX,
    required this.horizontalPadding,
    required this.playedColor,
    required this.bufferedColor,
    required this.backgroundColor,
    required this.handleColor,
    required this.barHeight,
    required this.handleRadius,
    this.introEndMs,
    this.outroStartMs,
  }) : super(
         repaint: Listenable.merge([
           position,
           toggleAnimation,
           hoverAnimation,
           hoverX,
         ]),
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

    // 3. Hover scrub fill: track start -> cursor, faded in/out by the hover
    // animation (so a stale hoverX after the mouse leaves paints nothing).
    // Drawn UNDER the played fill: behind the playhead it vanishes into the
    // red, ahead of it it lights the stretch the cursor would seek to.
    final double? hx = hoverX.value;
    if (hx != null && hoverValue > 0) {
      final fillPx = (hx - horizontalPadding).clamp(0.0, size.width);
      if (fillPx > 0) {
        final Paint hoverFill = Paint()
          ..color = Colors.white.withValues(alpha: 0.30 * hoverValue);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              0,
              centerY - currentHeight / 2,
              fillPx,
              currentHeight,
            ),
            Radius.circular(currentHeight / 2),
          ),
          hoverFill,
        );
      }
    }

    // 4. Draw Played Progress
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

    // 5. Draw skip bands. On TOP of the played fill, or a watched intro would
    // hide the band that proves the setting took. Kept low-alpha and inset so
    // it annotates the track rather than competing with progress.
    if (introEndMs != null || outroStartMs != null) {
      final Paint markerPaint = Paint()
        ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.45);
      void band(double startMs, double endMs) {
        final left = (startMs / duration).clamp(0.0, 1.0) * size.width;
        final right = (endMs / duration).clamp(0.0, 1.0) * size.width;
        if (right - left < 1.0) return;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              left,
              centerY - currentHeight / 2,
              right - left,
              currentHeight,
            ),
            Radius.circular(currentHeight / 2),
          ),
          markerPaint,
        );
      }

      if (introEndMs != null) band(0, introEndMs!);
      if (outroStartMs != null) band(outroStartMs!, duration);
    }

    // 6. Draw Handle
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
