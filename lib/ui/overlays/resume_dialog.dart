// ui/overlays/resume_dialog.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vidra_player/ui/widget/blur.dart';
import 'package:vidra_player/utils/util.dart';
import '../../controller/player_controller.dart';

/// 恢复播放对话框
class ResumeDialog extends StatefulWidget {
  final PlayerController controller; // Added
  final Duration position;
  final Duration duration;
  final VoidCallback onResume;
  final VoidCallback onRestart;
  final bool autoClose;
  final Duration autoCloseDelay;

  const ResumeDialog({
    super.key,
    required this.controller, // Added
    required this.position,
    required this.duration,
    required this.onResume,
    required this.onRestart,
    this.autoClose = true,
    this.autoCloseDelay = const Duration(seconds: 10),
  });

  @override
  State<ResumeDialog> createState() => _ResumeDialogState();
}

class _ResumeDialogState extends State<ResumeDialog> {
  Timer? _autoCloseTimer;
  late int _countdown;

  @override
  void initState() {
    super.initState();
    _countdown = widget.autoCloseDelay.inSeconds;

    if (widget.autoClose) {
      _autoCloseTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted) {
          setState(() {
            _countdown--;
          });

          if (_countdown <= 0) {
            timer.cancel();
            widget.onResume.call();
          }
        }
      });
    }
  }

  @override
  void dispose() {
    _autoCloseTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Use theme from controller config
    final theme = widget.controller.config.theme;
    final localization = widget.controller.localization;

    return Center(
      child: BlurPanel(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Container(
            padding: const EdgeInsets.all(24.0),
            decoration: BoxDecoration(
              color: theme.dialogBackgroundColor.withAlpha(240),
              borderRadius: BorderRadius.circular(16.0),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(128),
                  blurRadius: 12.0,
                  spreadRadius: 2.0,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Icon
                Icon(Icons.history, color: theme.primaryColor, size: 42.0),

                const SizedBox(height: 16.0),

                // Title
                Text(
                  localization.translate('resume_playback'),
                  style: TextStyle(
                    color: theme.dialogTextColor,
                    fontSize: 18.0,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 8.0),

                // Description
                Text(
                  '${localization.translate('last_watched_at')} ${Util.formatDuration(widget.position)} / ${Util.formatDuration(widget.duration)}',
                  style: TextStyle(
                    color: theme.dialogTextColor.withAlpha(160),
                    fontSize: 13.0,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 20.0),

                // Countdown Prompt
                if (widget.autoClose)
                  Text(
                    '$_countdown${localization.translate('auto_resume_in_seconds')}',
                    style: TextStyle(
                      color: theme.dialogTextColor.withAlpha(120),
                      fontSize: 12.0,
                    ),
                  ),

                if (widget.autoClose) const SizedBox(height: 16.0),

                // Buttons
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Restart Button
                    OutlinedButton(
                      onPressed: () {
                        _autoCloseTimer?.cancel();
                        widget.onRestart();
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: theme.dialogTextColor,
                        side: BorderSide(
                          color: theme.dialogTextColor.withAlpha(100),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16.0,
                          vertical: 10.0,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.replay, size: 16.0),
                          const SizedBox(width: 8.0),
                          Text(localization.translate('restart')),
                        ],
                      ),
                    ),

                    const SizedBox(width: 12.0),

                    // Continue Button
                    ElevatedButton(
                      onPressed: () {
                        _autoCloseTimer?.cancel();
                        widget.onResume();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16.0,
                          vertical: 10.0,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        elevation: 0,
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.play_arrow, size: 16.0),
                          const SizedBox(width: 8.0),
                          Text(localization.translate('continue_playback')),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Replay Dialog (for completed videos >95%)
class ReplayDialog extends StatelessWidget {
  final PlayerController controller; // Added
  final Duration position;
  final Duration duration;
  final VoidCallback onReplay;
  final VoidCallback onDismiss;
  final bool hasNextEpisode;
  final VoidCallback? onPlayNext;

  const ReplayDialog({
    super.key,
    required this.controller, // Added
    required this.position,
    required this.duration,
    required this.onReplay,
    required this.onDismiss,
    this.hasNextEpisode = false,
    this.onPlayNext,
  });

  @override
  Widget build(BuildContext context) {
    final theme = controller.config.theme;
    final localization = controller.localization;

    return Center(
      child: BlurPanel(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Container(
            padding: const EdgeInsets.all(24.0),
            decoration: BoxDecoration(
              color: theme.dialogBackgroundColor.withAlpha(240),
              borderRadius: BorderRadius.circular(16.0),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(128),
                  blurRadius: 12.0,
                  spreadRadius: 2.0,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Icon
                Icon(Icons.check_circle, color: theme.primaryColor, size: 42.0),

                const SizedBox(height: 16.0),

                // Title
                Text(
                  localization.translate('watched_complete'),
                  style: TextStyle(
                    color: theme.dialogTextColor,
                    fontSize: 18.0,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 8.0),

                // Description
                Text(
                  '${localization.translate('you_watched_to')} ${Util.formatDuration(position)} / ${Util.formatDuration(duration)}',
                  style: TextStyle(
                    color: theme.dialogTextColor.withAlpha(160),
                    fontSize: 13.0,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 20.0),

                // Buttons
                if (hasNextEpisode && onPlayNext != null)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Primary Action
                      ElevatedButton(
                        onPressed: onPlayNext,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24.0,
                            vertical: 12.0,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30.0),
                          ),
                          elevation: 0,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.skip_next, size: 20.0),
                            const SizedBox(width: 8.0),
                            Flexible(
                              child: Text(
                                localization.translate('play_next_episode'),
                                style: const TextStyle(
                                  fontSize: 15.0,
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16.0),
                      // Secondary Actions
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton.icon(
                            onPressed: onReplay,
                            style: TextButton.styleFrom(
                              foregroundColor: theme.dialogTextColor.withAlpha(
                                150,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12.0,
                              ),
                            ),
                            icon: const Icon(Icons.replay, size: 16.0),
                            label: Text(
                              localization.translate('replay'),
                              style: const TextStyle(fontSize: 13.0),
                            ),
                          ),
                          const SizedBox(width: 12.0),
                          TextButton.icon(
                            onPressed: onDismiss,
                            style: TextButton.styleFrom(
                              foregroundColor: theme.dialogTextColor.withAlpha(
                                150,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12.0,
                              ),
                            ),
                            icon: const Icon(Icons.close, size: 16.0),
                            label: Text(
                              localization.translate('cancel'),
                              style: const TextStyle(fontSize: 13.0),
                            ),
                          ),
                        ],
                      ),
                    ],
                  )
                else
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OutlinedButton(
                        onPressed: onDismiss,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: theme.dialogTextColor,
                          side: BorderSide(
                            color: theme.dialogTextColor.withAlpha(100),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16.0,
                            vertical: 10.0,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8.0),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.close, size: 16.0),
                            const SizedBox(width: 8.0),
                            Text(localization.translate('cancel')),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12.0),
                      ElevatedButton(
                        onPressed: onReplay,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16.0,
                            vertical: 10.0,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8.0),
                          ),
                          elevation: 0,
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.replay, size: 16.0),
                            const SizedBox(width: 8.0),
                            Text(localization.translate('replay')),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Inline Resume Prompt
class InlineResumePrompt extends StatefulWidget {
  final PlayerController controller; // Added
  final Duration position;
  final Duration duration;
  final VoidCallback onResume;
  final VoidCallback onRestart;
  final VoidCallback onDismiss;
  final bool autoDismiss;
  final Duration autoDismissDelay;

  const InlineResumePrompt({
    super.key,
    required this.controller, // Added
    required this.position,
    required this.duration,
    required this.onResume,
    required this.onRestart,
    required this.onDismiss,
    this.autoDismiss = true,
    this.autoDismissDelay = const Duration(seconds: 5),
  });

  @override
  State<InlineResumePrompt> createState() => _InlineResumePromptState();
}

class _InlineResumePromptState extends State<InlineResumePrompt> {
  late Timer _dismissTimer;

  @override
  void initState() {
    super.initState();

    if (widget.autoDismiss) {
      _dismissTimer = Timer(widget.autoDismissDelay, () {
        if (mounted) {
          widget.onDismiss();
        }
      });
    }
  }

  @override
  void dispose() {
    _dismissTimer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: widget.controller.config.theme.backgroundColor.withAlpha(
          222,
        ), // ~87%
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(
          color: widget.controller.config.theme.textColor.withAlpha(30),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.history,
                color: widget.controller.config.theme.iconColor.withAlpha(179),
                size: 16.0,
              ),
              const SizedBox(width: 8.0),
              Expanded(
                child: Text(
                  '${widget.controller.localization.translate('last_watched_at')} ${Util.formatDuration(widget.position)}',
                  style: TextStyle(
                    color: widget.controller.config.theme.textColor,
                    fontSize: 14.0,
                  ),
                ),
              ),
              // IconButton for an accessible ≥48dp tap target + semantics,
              // instead of a bare 16px GestureDetector.
              IconButton(
                onPressed: widget.onDismiss,
                tooltip: widget.controller.localization.translate('close'),
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  Icons.close,
                  color: widget.controller.config.theme.iconColorDisabled,
                  size: 16.0,
                ),
              ),
            ],
          ),

          const SizedBox(height: 8.0),

          // Progress Bar
          Container(
            height: 2.0,
            decoration: BoxDecoration(
              color: Colors.white12,
              borderRadius: BorderRadius.circular(1.0),
            ),
            child: Stack(
              children: [
                Container(
                  width: _getProgressWidth(),
                  decoration: BoxDecoration(
                    color: widget.controller.config.theme.primaryColor,
                    borderRadius: BorderRadius.circular(1.0),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12.0),

          Row(
            children: [
              // Continue Playback Button
              ElevatedButton(
                onPressed: () {
                  _dismissTimer.cancel();
                  widget.onResume();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 8.0,
                  ),
                  minimumSize: const Size(0, 32),
                ),
                child: Text(
                  widget.controller.localization.translate('continue_playback'),
                  style: const TextStyle(fontSize: 12.0),
                ),
              ),

              const SizedBox(width: 8.0),

              // Restart Button
              OutlinedButton(
                onPressed: () {
                  _dismissTimer.cancel();
                  widget.onRestart();
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: BorderSide(color: Colors.white30),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 8.0,
                  ),
                  minimumSize: const Size(0, 32),
                ),
                child: Text(
                  widget.controller.localization.translate('restart'),
                  style: const TextStyle(fontSize: 12.0),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  double _getProgressWidth() {
    final totalWidth = MediaQuery.of(context).size.width - 56; // 减去边距和内边距
    final progress = widget.duration.inMilliseconds > 0
        ? widget.position.inMilliseconds / widget.duration.inMilliseconds
        : 0.0;

    return progress * totalWidth;
  }
}

/// 自动恢复提示
class AutoResumeIndicator extends StatefulWidget {
  final PlayerController controller; // Added
  final Duration countdown;
  final VoidCallback onCancel;

  const AutoResumeIndicator({
    super.key,
    required this.controller,
    required this.countdown,
    required this.onCancel,
  });

  @override
  State<AutoResumeIndicator> createState() => _AutoResumeIndicatorState();
}

class _AutoResumeIndicatorState extends State<AutoResumeIndicator> {
  late int _remainingSeconds;
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _remainingSeconds = widget.countdown.inSeconds;
    _startTimer();
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _remainingSeconds--;
        });

        if (_remainingSeconds <= 0) {
          timer.cancel();
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: widget.controller.config.theme.controlsBackground,
        borderRadius: BorderRadius.circular(20.0),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Countdown Circle
          Stack(
            children: [
              Container(
                width: 24.0,
                height: 24.0,
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: widget.controller.config.theme.bufferedColor,
                    width: 2.0,
                  ),
                ),
              ),
              Positioned.fill(
                child: CircularProgressIndicator(
                  value: _remainingSeconds / widget.countdown.inSeconds,
                  strokeWidth: 2.0,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    widget.controller.config.theme.primaryColor,
                  ),
                  backgroundColor: Colors.transparent,
                ),
              ),
              Positioned.fill(
                child: Center(
                  child: Text(
                    '$_remainingSeconds',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10.0,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(width: 8.0),

          Text(
            widget.controller.localization.translate('auto_resume_playback'),
            style: const TextStyle(color: Colors.white, fontSize: 12.0),
          ),

          const SizedBox(width: 8.0),

          IconButton(
            onPressed: widget.onCancel,
            tooltip: widget.controller.localization.translate('close'),
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, color: Colors.white70, size: 16.0),
          ),
        ],
      ),
    );
  }
}
