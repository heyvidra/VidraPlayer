// ui/overlays/episode_list.dart

import 'package:flutter/material.dart';
import '../../controller/player_controller.dart';
import '../../core/localization/localization.dart';
import '../../core/model/model.dart';

import '../../utils/screen.dart';
import '../../utils/no_scrollbar_behavior.dart';
import '../widget/blur.dart';

/// Episode list component
class EpisodeList extends StatefulWidget {
  final PlayerController controller;
  final List<VideoEpisode> episodes;
  final int currentEpisodeIndex;
  final List<EpisodeHistory> histories;
  final bool isDownloadMode;
  final ValueChanged<int> onEpisodeSelected;
  final ValueChanged<int>? onDownloadSelected;
  final VoidCallback onClose;
  final bool showWatchedStatus;
  final bool showDownloadStatus;
  final String? title;
  final bool showSearch;
  final bool? episodesSort;

  const EpisodeList({
    super.key,
    required this.controller,
    required this.episodes,
    required this.currentEpisodeIndex,
    this.histories = const [],
    this.isDownloadMode = false,
    required this.onEpisodeSelected,
    this.onDownloadSelected,
    required this.onClose,
    this.showWatchedStatus = true,
    this.showDownloadStatus = false,
    this.title,
    this.showSearch = false,
    this.episodesSort = true,
  });

  @override
  State<EpisodeList> createState() => _EpisodeListState();
}

class _EpisodeListState extends State<EpisodeList> {
  late List<VideoEpisode> _filteredEpisodes;
  late TextEditingController _searchController;
  late ScrollController _scrollController;

  bool _isAscending = true;

  @override
  void initState() {
    super.initState();
    _isAscending = widget.episodesSort!;
    _filteredEpisodes = List.from(widget.episodes);
    _searchController = TextEditingController();
    _scrollController = ScrollController();

    _filterEpisodes();

    // Delay scroll to current episode
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToCurrentEpisode();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant EpisodeList oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.episodes != widget.episodes ||
        oldWidget.currentEpisodeIndex != widget.currentEpisodeIndex) {
      _filterEpisodes();
      _scrollToCurrentEpisode();
    }
  }

  void _filterEpisodes() {
    // Always derive from the latest widget.episodes so added / removed /
    // replaced episodes (lazy-loaded or paginated catalogs) actually render —
    // previously this sorted a stale copy taken once in initState.
    _filteredEpisodes = List<VideoEpisode>.from(widget.episodes)
      ..sort((a, b) {
        if (_isAscending) {
          return a.index.compareTo(b.index);
        } else {
          return b.index.compareTo(a.index);
        }
      });

    if (mounted) {
      setState(() {});
    }
  }

  void _scrollToCurrentEpisode() {
    if (_scrollController.hasClients && _filteredEpisodes.isNotEmpty) {
      final indexInFiltered = _filteredEpisodes.indexWhere(
        (e) => widget.episodes.indexOf(e) == widget.currentEpisodeIndex,
      );
      if (indexInFiltered != -1) {
        final row = indexInFiltered ~/ 4; // 4 columns
        final scrollOffset = row * 60.0; // Estimate grid row height

        _scrollController.animateTo(
          scrollOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.controller.config.theme;
    final localization = widget.controller.localization;
    final totalEpisodes = widget.episodes.length;

    return GestureDetector(
      onTap: widget.onClose,
      behavior: HitTestBehavior.opaque,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isSmall = ScreenHelper.isMediumScreen(context);
          final panelWidth = isSmall
              ? (constraints.maxWidth > 300
                    ? constraints.maxWidth * 0.65
                    : constraints.maxWidth * 0.85)
              : 400.0;

          return Container(
            color: Colors.transparent,
            child: Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: () {}, // Prevent closing when clicking inside panel
                child: BlurPanel(
                  child: Container(
                    width: panelWidth,
                    color: theme.dialogBackgroundColor.withValues(alpha: 0.6),
                    child: SafeArea(
                      left:
                          isSmall, // Add safe area for mobile notch/island if on right
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Title bar
                          _buildHeader(theme, totalEpisodes, localization),

                          // Episode list
                          Expanded(child: _buildEpisodeList(theme, panelWidth)),

                          // Bottom info
                          _buildFooter(theme, localization),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(
    PlayerUITheme theme,
    int totalEpisodes,
    VidraLocalization l10n,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 2),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.textColor.withValues(alpha: 0.12)),
        ),
      ),
      child: Row(
        children: [
          Icon(
            widget.isDownloadMode ? Icons.download : Icons.list,
            color: theme.iconColor,
            size: 20.0,
          ),
          const SizedBox(width: 12.0),
          Text(
            widget.title ??
                (widget.isDownloadMode
                    ? l10n.translate('download_manager')
                    : l10n.translate('episode_list')),
            style: TextStyle(
              color: theme.textColor,
              fontSize: 14.0,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 4.0),
          Text(
            '（$totalEpisodes）',
            style: TextStyle(
              color: theme.textColor.withValues(alpha: 0.7),
              fontSize: 12.0,
            ),
          ),
          Spacer(),

          IconButton(
            key: const ValueKey('episode_list_sort_button'),
            icon: Icon(
              _isAscending ? Icons.sort_rounded : Icons.sort_rounded,
              color: theme.iconColor.withValues(alpha: 0.7),
              size: 20.0,
            ),
            tooltip: _isAscending
                ? l10n.translate('sort_ascending')
                : l10n.translate('sort_descending'),
            onPressed: () {
              setState(() {
                _isAscending = !_isAscending;
                _filterEpisodes();
              });
            },
          ),
          const SizedBox(width: 8.0),
          IconButton(
            key: const ValueKey('episode_list_close_button'),
            icon: Icon(Icons.close, color: theme.iconColor),
            iconSize: 20.0,
            onPressed: widget.onClose,
          ),
        ],
      ),
    );
  }

  Widget _buildEpisodeList(PlayerUITheme theme, double panelWidth) {
    // Calculate columns based on panel width
    // Assuming each item needs ~90-100 pixels width including spacing
    final int crossAxisCount = (panelWidth / 90).floor().clamp(3, 5);

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        return false;
      },
      child: ScrollConfiguration(
        behavior: NoScrollbarBehavior(),
        child: GridView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(12.0),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.6,
          ),
          itemCount: _filteredEpisodes.length,
          itemBuilder: (context, index) {
            final episode = _filteredEpisodes[index];
            final isCurrent = episode.index == widget.currentEpisodeIndex;
            EpisodeHistory? history;
            try {
              history = widget.histories.firstWhere(
                (h) => h.index == episode.index,
              );
            } catch (_) {}

            final isWatched = history != null;
            // final isDownloaded = episode.isDownloaded ?? false;

            return _EpisodeGridItemCustom(
              episode: episode,
              index: episode.index,
              isCurrent: isCurrent,
              history: history,
              isWatched: widget.showWatchedStatus && isWatched,
              // isDownloaded: widget.showDownloadStatus && isDownloaded,
              isDownloadMode: widget.isDownloadMode,
              onTap: () {
                widget.onEpisodeSelected(episode.index);
              },
              // onLongPress: () => _showEpisodeContextMenu(episode.index),
              onDownload: widget.onDownloadSelected != null
                  ? () => widget.onDownloadSelected!(episode.index)
                  : null,
              theme: theme,
            );
          },
        ),
      ),
    );
  }

  Widget _buildFooter(PlayerUITheme theme, VidraLocalization l10n) {
    if (!widget.isDownloadMode) return const SizedBox();

    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: theme.textColor.withValues(alpha: 0.12)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.translate('download_options'),
            style: TextStyle(
              color: theme.textColor,
              fontSize: 14.0,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12.0),
          Row(
            children: [
              // Download all button
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    _downloadAllEpisodes();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.primaryColor,
                    foregroundColor: theme.textColor,
                    padding: const EdgeInsets.symmetric(vertical: 12.0),
                  ),
                  icon: const Icon(Icons.download, size: 18.0),
                  label: Text(l10n.translate('download_all_episodes')),
                ),
              ),
              const SizedBox(width: 12.0),
              // Batch selection button
              OutlinedButton.icon(
                onPressed: () {
                  _showBatchSelection();
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.textColor.withValues(alpha: 0.7),
                  side: BorderSide(
                    color: theme.textColor.withValues(alpha: 0.3),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 12.0,
                  ),
                ),
                icon: const Icon(Icons.select_all, size: 18.0),
                label: Text(l10n.translate('batch_selection')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _downloadAllEpisodes() {
    if (widget.episodes.isEmpty) return;

    final theme = widget.controller.config.theme;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: theme.dialogBackgroundColor,
          title: Text(
            widget.controller.localization.translate('download_all'),
            style: TextStyle(color: theme.dialogTextColor),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.controller.localization.translate(
                  'confirm_download_all',
                  args: {'count': widget.episodes.length.toString()},
                ),
                style: TextStyle(
                  color: theme.dialogTextColor.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 12.0),
              Text(
                '${widget.controller.localization.translate('download_options')}：',
                style: TextStyle(
                  color: theme.dialogTextColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8.0),
              _DownloadQualitySelector(
                theme: theme,
                qualities: widget.episodes.first.qualities,
                onQualitySelected: (quality) {},
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                widget.controller.localization.translate('cancel'),
                style: TextStyle(
                  color: theme.dialogTextColor.withValues(alpha: 0.7),
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.primaryColor,
                foregroundColor: theme.textColor,
              ),
              onPressed: () {
                Navigator.pop(context);
                widget.onClose();
              },
              child: Text(widget.controller.localization.translate('start_download')),
            ),
          ],
        );
      },
    );
  }

  void _showBatchSelection() {
    final theme = widget.controller.config.theme;

    showModalBottomSheet(
      context: context,
      backgroundColor: theme.dialogBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12.0)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.controller.localization.translate(
                  'batch_select_episodes',
                ),
                style: TextStyle(
                  color: theme.dialogTextColor,
                  fontSize: 18.0,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16.0),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.controller.localization.translate('from'),
                          style: TextStyle(
                            color: theme.dialogTextColor.withValues(alpha: 0.7),
                          ),
                        ),
                        const SizedBox(height: 4.0),
                        Container(
                          height: 40.0,
                          padding: const EdgeInsets.symmetric(horizontal: 12.0),
                          decoration: BoxDecoration(
                            color: theme.controlsBackground,
                            borderRadius: BorderRadius.circular(8.0),
                            border: Border.all(
                              color: theme.dialogTextColor.withValues(
                                alpha: 0.12,
                              ),
                            ),
                          ),
                          child: DropdownButton<int>(
                            value: 1,
                            items: List.generate(widget.episodes.length, (
                              index,
                            ) {
                              return DropdownMenuItem<int>(
                                value: index + 1,
                                child: Text(
                                  widget.controller.localization.translate(
                                    'episode_number',
                                    args: {'number': '${index + 1}'},
                                  ),
                                  style: TextStyle(
                                    color: theme.dialogTextColor,
                                  ),
                                ),
                              );
                            }),
                            onChanged: (value) {},
                            dropdownColor: theme.dialogBackgroundColor,
                            style: TextStyle(color: theme.dialogTextColor),
                            underline: Container(),
                            icon: Icon(
                              Icons.arrow_drop_down,
                              color: theme.dialogTextColor.withValues(
                                alpha: 0.7,
                              ),
                            ),
                            isExpanded: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16.0),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.controller.localization.translate('to'),
                          style: TextStyle(
                            color: theme.dialogTextColor.withValues(alpha: 0.7),
                          ),
                        ),
                        const SizedBox(height: 4.0),
                        Container(
                          height: 40.0,
                          padding: const EdgeInsets.symmetric(horizontal: 12.0),
                          decoration: BoxDecoration(
                            color: theme.controlsBackground,
                            borderRadius: BorderRadius.circular(8.0),
                            border: Border.all(
                              color: theme.dialogTextColor.withValues(
                                alpha: 0.12,
                              ),
                            ),
                          ),
                          child: DropdownButton<int>(
                            value: widget.episodes.length,
                            items: List.generate(widget.episodes.length, (
                              index,
                            ) {
                              return DropdownMenuItem<int>(
                                value: index + 1,
                                child: Text(
                                  widget.controller.localization.translate(
                                    'episode_number',
                                    args: {'number': '${index + 1}'},
                                  ),
                                  style: TextStyle(
                                    color: theme.dialogTextColor,
                                  ),
                                ),
                              );
                            }),
                            onChanged: (value) {},
                            dropdownColor: theme.dialogBackgroundColor,
                            style: TextStyle(color: theme.dialogTextColor),
                            underline: Container(),
                            icon: Icon(
                              Icons.arrow_drop_down,
                              color: theme.dialogTextColor.withValues(
                                alpha: 0.7,
                              ),
                            ),
                            isExpanded: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16.0),
              Text(
                '${widget.controller.localization.translate('select_quality')}：',
                style: TextStyle(
                  color: theme.dialogTextColor.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 8.0),
              if (widget.episodes.isNotEmpty)
                _DownloadQualitySelector(
                  theme: theme,
                  qualities: widget.episodes.first.qualities,
                  onQualitySelected: (quality) {},
                ),
              const SizedBox(height: 24.0),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: theme.dialogTextColor,
                        side: BorderSide(
                          color: theme.dialogTextColor.withValues(alpha: 0.3),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14.0),
                      ),
                      child: Text(
                        widget.controller.localization.translate('cancel'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12.0),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        widget.onClose();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.primaryColor,
                        foregroundColor: theme.textColor,
                        padding: const EdgeInsets.symmetric(vertical: 14.0),
                      ),
                      child: Text(
                        widget.controller.localization.translate(
                          'start_download',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // void _showEpisodeContextMenu(int index) {
  // final episode = widget.episodes[index];
  // final isDownloaded = episode.isDownloaded ?? false;

  // showModalBottomSheet(
  //   context: context,
  //   backgroundColor: Colors.black87,
  //   shape: const RoundedRectangleBorder(
  //     borderRadius: BorderRadius.vertical(top: Radius.circular(12.0)),
  //   ),
  //   builder: (context) {
  //     return Container(
  //       padding: const EdgeInsets.all(20.0),
  //       child: Column(
  //         mainAxisSize: MainAxisSize.min,
  //         children: [
  //           Text(
  //             episode.title,
  //             style: const TextStyle(
  //               color: Colors.white,
  //               fontSize: 16.0,
  //               fontWeight: FontWeight.w600,
  //             ),
  //             textAlign: TextAlign.center,
  //             maxLines: 2,
  //             overflow: TextOverflow.ellipsis,
  //           ),
  //           const SizedBox(height: 16.0),
  //           Wrap(
  //             spacing: 12.0,
  //             runSpacing: 12.0,
  //             children: [
  //               _ContextMenuButton(
  //                 icon: Icons.play_arrow,
  //                 label: '播放',
  //                 onTap: () {
  //                   Navigator.pop(context);
  //                   widget.onEpisodeSelected(index);
  //                 },
  //               ),
  //               if (widget.onDownloadSelected != null)
  //                 _ContextMenuButton(
  //                   icon: isDownloaded ? Icons.download_done : Icons.download,
  //                   label: isDownloaded ? '已下载' : '下载',
  //                   onTap: () {
  //                     Navigator.pop(context);
  //                     widget.onDownloadSelected!(index);
  //                   },
  //                 ),
  //             ],
  //           ),
  //           const SizedBox(height: 20.0),
  //           SizedBox(
  //             width: double.infinity,
  //             child: OutlinedButton(
  //               onPressed: () => Navigator.pop(context),
  //               style: OutlinedButton.styleFrom(
  //                 foregroundColor: Colors.white70,
  //                 side: const BorderSide(color: Colors.white30),
  //                 padding: const EdgeInsets.symmetric(vertical: 12.0),
  //               ),
  //               child: const Text('取消'),
  //             ),
  //           ),
  //         ],
  //       ),
  //     );
  //   },
  // );
  // }
}

class _EpisodeGridItemCustom extends StatelessWidget {
  final VideoEpisode episode;
  final int index;
  final bool isCurrent;
  final EpisodeHistory? history;
  final bool isWatched;
  // final bool isDownloaded;
  final bool isDownloadMode;
  final VoidCallback onTap;

  final VoidCallback? onDownload;
  final PlayerUITheme theme;

  const _EpisodeGridItemCustom({
    required this.episode,
    required this.index,
    required this.isCurrent,
    this.history,
    required this.isWatched,
    // required this.isDownloaded,
    required this.isDownloadMode,
    required this.onTap,

    this.onDownload,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final hasWatched = (history?.watchedProgress ?? 0.0) > 0.05;
    return InkWell(
      onTap: onTap,
      onLongPress: null,
      borderRadius: BorderRadius.circular(8.0),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8.0),
          border: Border.all(
            color: isCurrent
                ? theme.primaryColor
                : theme.textColor.withValues(alpha: 0.1),
            width: isCurrent ? 2 : 1,
          ),
          color: isCurrent
              ? theme.primaryColor.withValues(alpha: 0.1)
              : theme.hoverColor,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8.0),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Text content
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (isCurrent)
                        Icon(
                          Icons.play_arrow_rounded,
                          color: theme.primaryColor,
                          size: 20,
                        ),
                      Text(
                        episode.title,
                        style: TextStyle(
                          color: isCurrent
                              ? theme.primaryColor
                              : theme.textColor.withValues(alpha: 0.7),
                          fontSize: 12.0,
                          fontWeight: isCurrent
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),

              // Progress bar
              if (hasWatched)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 3,
                    decoration: BoxDecoration(
                      color: theme.bufferedColor,
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(8),
                        bottomRight: Radius.circular(8),
                      ),
                    ),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: history?.watchedProgress ?? 0.0,
                      child: Container(
                        decoration: BoxDecoration(
                          color: theme.progressBarColor,
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(8),
                            bottomRight: Radius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

              // Download indicator
              // if (isDownloaded)
              //   Positioned(
              //     top: 4,
              //     right: 4,
              //     child: Icon(
              //       Icons.download_done,
              //       color: Colors.green.withValues(alpha: 0.8),
              //       size: 12,
              //     ),
              //   ),

              // Watched indicator (check mark)
              if ((history?.watchedProgress ?? 0.0) > 0.9)
                Positioned(
                  top: 4,
                  left: 4,
                  child: Icon(
                    Icons.check_circle,
                    color: theme.primaryColor.withValues(alpha: 0.8),
                    size: 14,
                  ),
                ),
              if (episode.badge != null)
                Positioned(top: 2, right: 2, child: episode.badge!),
            ],
          ),
        ),
      ),
    );
  }
}

class _DownloadQualitySelector extends StatefulWidget {
  final List<VideoQuality> qualities;
  final ValueChanged<VideoQuality> onQualitySelected;
  final PlayerUITheme theme;

  const _DownloadQualitySelector({
    required this.qualities,
    required this.onQualitySelected,
    required this.theme,
  });

  @override
  State<_DownloadQualitySelector> createState() =>
      _DownloadQualitySelectorState();
}

class _DownloadQualitySelectorState extends State<_DownloadQualitySelector> {
  late VideoQuality _selectedQuality;

  @override
  void initState() {
    super.initState();
    _selectedQuality = widget.qualities.first;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: widget.theme.controlsBackground,
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Column(
        children: widget.qualities.map((quality) {
          final isSelected = _selectedQuality == quality;
          return InkWell(
            onTap: () {
              setState(() {
                _selectedQuality = quality;
              });
              widget.onQualitySelected(quality);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 12.0,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          quality.label,
                          style: TextStyle(color: widget.theme.dialogTextColor),
                        ),
                        if (quality.resolution != null)
                          Text(
                            quality.resolution!,
                            style: TextStyle(
                              color: widget.theme.dialogTextColor.withValues(
                                alpha: 0.7,
                              ),
                              fontSize: 12.0,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected
                            ? widget.theme.primaryColor
                            : widget.theme.dialogTextColor.withValues(
                                alpha: 0.5,
                              ),
                        width: 2,
                      ),
                    ),
                    child: isSelected
                        ? Center(
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: widget.theme.primaryColor,
                              ),
                            ),
                          )
                        : null,
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
