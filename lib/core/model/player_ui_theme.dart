import 'package:flutter/material.dart';

@immutable
class PlayerUITheme {
  final Color primaryColor;
  final Color backgroundColor;
  final Color controlsBackground;
  final Color textColor;
  final Color iconColor;
  final Color iconColorDisabled;
  final Color progressBarColor;
  final Color bufferedColor;
  final Color hoverColor;
  final Color dialogBackgroundColor;
  final Color dialogTextColor;
  final BorderRadius borderRadius;
  final double controlsOpacity;
  final Duration animationDuration;

  const PlayerUITheme({
    required this.primaryColor,
    required this.backgroundColor,
    required this.controlsBackground,
    required this.textColor,
    required this.iconColor,
    required this.iconColorDisabled,
    required this.progressBarColor,
    required this.bufferedColor,
    required this.hoverColor,
    required this.dialogBackgroundColor,
    required this.dialogTextColor,
    required this.borderRadius,
    required this.controlsOpacity,
    required this.animationDuration,
  });

  // =========================
  // Controller Gradients (Unified Access)
  // =========================

  /// Top Controller Gradient (Back / Title)
  LinearGradient get topControlsGradient {
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        controlsBackground.withAlpha(153),
        controlsBackground.withAlpha(51),
        Colors.transparent,
      ],
    );
  }

  /// Bottom Controller Gradient (Progress Bar / Buttons)
  LinearGradient get bottomControlsGradient {
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Colors.transparent,
        controlsBackground.withAlpha(102),
        controlsBackground.withAlpha(192),
      ],
    );
  }

  // =========================
  // Theme Definitions
  // =========================

  /// Default General Theme
  const PlayerUITheme.defaultTheme()
    : primaryColor = Colors.redAccent,
      backgroundColor = Colors.black,
      controlsBackground = const Color(0xCC000000),
      textColor = Colors.white,
      iconColor = Colors.white,
      iconColorDisabled = Colors.white60,
      progressBarColor = Colors.redAccent,
      bufferedColor = Colors.white30,
      hoverColor = Colors.white10,
      dialogBackgroundColor = const Color(0xFF1E1F24),
      dialogTextColor = Colors.white,
      borderRadius = BorderRadius.zero,
      controlsOpacity = 0.85,
      animationDuration = const Duration(milliseconds: 200);

  /// Dark Immersive Theme
  const PlayerUITheme.dark()
    : primaryColor = const Color(0xFFE53935),
      backgroundColor = Colors.black,
      controlsBackground = const Color(0xE6000000),
      textColor = Colors.white,
      iconColor = Colors.white,
      iconColorDisabled = Colors.white54,
      progressBarColor = const Color(0xFFE53935),
      bufferedColor = Colors.white24,
      hoverColor = Colors.white10,
      dialogBackgroundColor = const Color(0xFF1C1C1E),
      dialogTextColor = Colors.white,
      borderRadius = BorderRadius.zero,
      controlsOpacity = 0.9,
      animationDuration = const Duration(milliseconds: 220);

  /// Light Player Theme (Education / Documentation)
  const PlayerUITheme.light()
    : primaryColor = const Color(0xFF1E88E5),
      backgroundColor = Colors.white,
      controlsBackground = const Color(0xE6000000),
      textColor = Colors.black87,
      iconColor = Colors.black87,
      iconColorDisabled = Colors.black45,
      progressBarColor = const Color(0xFF1E88E5),
      bufferedColor = Colors.black26,
      hoverColor = Colors.black12,
      dialogBackgroundColor = Colors.white,
      dialogTextColor = Colors.black87,
      borderRadius = BorderRadius.zero,
      controlsOpacity = 0.85,
      animationDuration = const Duration(milliseconds: 200);

  /// Netflix Style
  const PlayerUITheme.netflix()
    : primaryColor = const Color(0xFFE50914),
      backgroundColor = Colors.black,
      controlsBackground = const Color(0x59000000), // 35% black
      textColor = Colors.white,
      iconColor = Colors.white,
      iconColorDisabled = Colors.white70,
      progressBarColor = const Color(0xFFE50914),
      bufferedColor = const Color(0x33FFFFFF),
      hoverColor = Colors.white10,
      dialogBackgroundColor = const Color(0xFF141414),
      dialogTextColor = Colors.white,
      borderRadius = BorderRadius.zero,
      controlsOpacity = 1.0,
      animationDuration = const Duration(milliseconds: 250);

  /// Cinema Style
  const PlayerUITheme.cinema()
    : primaryColor = const Color(0xFFC9A84E),
      backgroundColor = const Color(0xFF0A0A0A),
      controlsBackground = const Color(0xE6000000),
      textColor = const Color(0xFFF5F1E6),
      iconColor = const Color(0xFFC9A84E),
      iconColorDisabled = const Color(0x80C9A84E),
      progressBarColor = const Color(0xFFC9A84E),
      bufferedColor = const Color(0x33F5F1E6),
      hoverColor = const Color(0x1AC9A84E),
      dialogBackgroundColor = const Color(0xFF1A1A1A),
      dialogTextColor = const Color(0xFFF5F1E6),
      borderRadius = BorderRadius.zero,
      controlsOpacity = 0.9,
      animationDuration = const Duration(milliseconds: 300);

  /// Minimalist Style
  const PlayerUITheme.minimal()
    : primaryColor = const Color(0xFF64B5F6),
      backgroundColor = Colors.black,
      controlsBackground = Colors.transparent,
      textColor = Colors.white,
      iconColor = Colors.white,
      iconColorDisabled = const Color(0x80FFFFFF),
      progressBarColor = const Color(0xFF64B5F6),
      bufferedColor = const Color(0x26FFFFFF),
      hoverColor = const Color(0x0AFFFFFF),
      dialogBackgroundColor = const Color(0xCC000000),
      dialogTextColor = Colors.white,
      borderRadius = const BorderRadius.all(Radius.circular(8)),
      controlsOpacity = 0.65,
      animationDuration = const Duration(milliseconds: 150);

  /// YouTube Style
  const PlayerUITheme.youtube()
    : primaryColor = const Color(0xFFFF0000),
      backgroundColor = Colors.black,
      controlsBackground = const Color(0xB3000000), // 70% black
      textColor = Colors.white,
      iconColor = Colors.white,
      iconColorDisabled = Colors.white54,
      progressBarColor = const Color(0xFFFF0000),
      bufferedColor = const Color(0x66FFFFFF),
      hoverColor = Colors.white10,
      dialogBackgroundColor = const Color(0xFF212121),
      dialogTextColor = Colors.white,
      borderRadius = BorderRadius.zero,
      controlsOpacity = 0.9,
      animationDuration = const Duration(milliseconds: 200);
}
