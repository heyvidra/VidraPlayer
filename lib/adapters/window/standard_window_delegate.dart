import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:auto_orientation/auto_orientation.dart';
import 'package:simple_pip_mode/simple_pip.dart';
import '../../core/interfaces/window_delegate.dart';
import '../../utils/log.dart';

/// A standard window delegate that implements fullscreen and PiP
/// using Flutter's [SystemChrome], third-party libraries for mobile,
/// and native platform channels for desktop.
class StandardWindowDelegate implements WindowDelegate {
  static const MethodChannel _channel = MethodChannel('vidra_player');

  const StandardWindowDelegate();

  @override
  Future<void> enterFullscreen() async {
    // Mobile orientation change
    if (Platform.isAndroid || Platform.isIOS) {
      AutoOrientation.landscapeRightMode();
    }

    // Standard Flutter fullscreen
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    // Notify native (needed for desktop)
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      try {
        await _channel.invokeMethod('enterFullscreen');
      } catch (e) {
        logger.e("[StandardWindowDelegate] Error entering fullscreen: $e");
      }
    }
  }

  @override
  Future<void> exitFullscreen() async {
    // Mobile orientation restore
    if (Platform.isAndroid || Platform.isIOS) {
      AutoOrientation.portraitUpMode();
    }

    // Restore standard UI
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    // Notify native
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      try {
        await _channel.invokeMethod('exitFullscreen');
      } catch (e) {
        logger.e("[StandardWindowDelegate] Error exiting fullscreen: $e");
      }
    }
  }

  @override
  Future<void> toggleFullscreen() async {
    if (Platform.isAndroid || Platform.isIOS) {
      // For mobile, we can toggle based on orientation or a flag
      // but usually specific enter/exit calls are better from UIStateManager.
      // Here we provide a basic toggle as fallback.
      if (MediaQueryData.fromView(
            WidgetsBinding.instance.platformDispatcher.views.first,
          ).orientation ==
          Orientation.portrait) {
        await enterFullscreen();
      } else {
        await exitFullscreen();
      }
      return;
    }

    try {
      final bool? isFullscreen = await _channel.invokeMethod<bool>(
        'isFullscreen',
      );
      if (isFullscreen == true) {
        await exitFullscreen();
      } else {
        await enterFullscreen();
      }
    } catch (e) {
      logger.e("[StandardWindowDelegate] Error toggling fullscreen: $e");
    }
  }

  @override
  Future<void> minimize() async {
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      try {
        await _channel.invokeMethod('minimize');
      } catch (e) {
        logger.e("[StandardWindowDelegate] Error minimizing: $e");
      }
    }
  }

  @override
  Future<void> maximize() async {
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      try {
        await _channel.invokeMethod('maximize');
      } catch (e) {
        logger.e("[StandardWindowDelegate] Error maximizing: $e");
      }
    }
  }

  @override
  Future<void> restore() async {
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      try {
        await _channel.invokeMethod('restore');
      } catch (e) {
        logger.e("[StandardWindowDelegate] Error restoring: $e");
      }
    }
  }

  @override
  Future<void> close() async {
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      try {
        await _channel.invokeMethod('close');
      } catch (e) {
        logger.e("[StandardWindowDelegate] Error closing: $e");
      }
    }
  }

  @override
  Future<void> setTitle(String title) async {
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      try {
        await _channel.invokeMethod('setTitle', {'title': title});
      } catch (e) {
        logger.e("[StandardWindowDelegate] Error setting title: $e");
      }
    }
  }

  @override
  Future<void> enterPip({dynamic pipWidget}) async {
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        await SimplePip().enterPipMode();
      } catch (e) {
        logger.e("[StandardWindowDelegate] Error entering PiP: $e");
      }
    } else {
      try {
        await _channel.invokeMethod('enterPip');
      } catch (e) {
        logger.e("[StandardWindowDelegate] Error entering PiP (native): $e");
      }
    }
  }

  @override
  Future<void> exitPip() async {
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      try {
        await _channel.invokeMethod('exitPip');
      } catch (e) {
        logger.e("[StandardWindowDelegate] Error exiting PiP (native): $e");
      }
    }
  }
}
