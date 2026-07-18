import 'package:flutter/material.dart';

class ScreenHelper {
  static Size getScreenSize(BuildContext ctx) {
    final screenSize = View.of(ctx).physicalSize;
    final ratio = View.of(ctx).devicePixelRatio;
    return Size(screenSize.width / ratio, screenSize.height / ratio);
  }

  static Size getScreenSizeWithBuild(BuildContext ctx) {
    return MediaQuery.of(ctx).size;
  }

  static bool isMobilePlatform(BuildContext ctx) {
    final platform = Theme.of(ctx).platform;
    return platform == TargetPlatform.iOS || platform == TargetPlatform.android;
  }

  static bool isSmallScreen(BuildContext ctx) {
    return MediaQuery.of(ctx).size.width < 450;
  }

  static bool isMediumScreen(BuildContext ctx) {
    return MediaQuery.of(ctx).size.width < 600;
  }

  static bool isMobileLayout(BuildContext ctx) {
    return isMobilePlatform(ctx) || isSmallScreen(ctx);
  }
}
