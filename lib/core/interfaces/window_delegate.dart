/// Abstract delegate for handling window operations.
/// The host application should implement this to handle window resizing,
/// fullscreen, and other window-level events.
abstract class WindowDelegate {
  /// Enter fullscreen mode
  Future<void> enterFullscreen();

  /// Exit fullscreen mode
  Future<void> exitFullscreen();

  /// Toggle fullscreen mode
  Future<void> toggleFullscreen();

  /// Minimize the window
  Future<void> minimize();

  /// Maximize the window
  Future<void> maximize();

  /// Restore the window from minimized/maximized state
  Future<void> restore();

  /// Close the window
  Future<void> close();

  /// Set window title
  Future<void> setTitle(String title);

  /// Enter picture-in-picture mode
  Future<void> enterPip();

  /// Exit picture-in-picture mode
  Future<void> exitPip();
}
