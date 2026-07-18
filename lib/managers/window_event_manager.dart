import 'dart:async';
import 'package:flutter/material.dart';

import '../core/lifecycle/lifecycle_token.dart';
import '../core/lifecycle/safe_stream.dart';

/// Window events
@immutable
class WindowEvent {
  final WindowEventType type;
  final DateTime timestamp;
  final dynamic data;

  WindowEvent({required this.type, DateTime? timestamp, this.data})
    : timestamp = timestamp ?? DateTime.now();
}

enum WindowEventType {
  focusGained,
  focusLost,
  minimized,
  restored,
  maximized,
  fullscreenEntered,
  fullscreenExited,
  pictureInPictureEntered,
  pictureInPictureExited,
  moved,
  resized,
  closed,
  visibilityChanged,
}

/// Window event manager
/// Refactored to only observe lifecycle events.
/// Actual window operations are now delegated via WindowDelegate in PlayerController.
class WindowEventManager with LifecycleTokenProvider {
  // ===============================================================
  // Dependencies & State
  // ===============================================================

  final StreamController<WindowEvent> _eventController =
      StreamController<WindowEvent>.broadcast();

  bool _isDisposed = false;

  WidgetsBindingObserver? _observer;

  // ===============================================================
  // Construction
  // ===============================================================

  WindowEventManager() {
    _observer = _AppLifecycleObserver(this);
    WidgetsBinding.instance.addObserver(_observer!);
  }

  // ===============================================================
  // Stream Accessors
  // ===============================================================

  Stream<WindowEvent> get eventStream => _eventController.stream;

  // ===============================================================
  // Disposal
  // ===============================================================

  void dispose() {
    if (_isDisposed) return;
    invalidateLifecycle();
    _isDisposed = true;
    _eventController.close();
    if (_observer != null) {
      WidgetsBinding.instance.removeObserver(_observer!);
      _observer = null;
    }
  }

  // Helper to safely emit events
  void _safeEmit(WindowEvent event) {
    final token = lifecycleToken;
    safeEmit(_eventController, event, token);
  }
}

class _AppLifecycleObserver extends WidgetsBindingObserver {
  final WindowEventManager _manager;

  _AppLifecycleObserver(this._manager);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_manager._isDisposed) return;

    switch (state) {
      case AppLifecycleState.resumed:
        _manager._safeEmit(WindowEvent(type: WindowEventType.focusGained));
        _manager._safeEmit(WindowEvent(type: WindowEventType.restored));
        _manager._safeEmit(
          WindowEvent(type: WindowEventType.visibilityChanged, data: true),
        );
        break;
      case AppLifecycleState.inactive:
        _manager._safeEmit(WindowEvent(type: WindowEventType.focusLost));
        break;
      case AppLifecycleState.paused:
        _manager._safeEmit(WindowEvent(type: WindowEventType.minimized));
        break;
      case AppLifecycleState.hidden:
        _manager._safeEmit(
          WindowEvent(type: WindowEventType.visibilityChanged, data: false),
        );
        break;
      case AppLifecycleState.detached:
        _manager._safeEmit(WindowEvent(type: WindowEventType.closed));
        break;
    }
  }
}
