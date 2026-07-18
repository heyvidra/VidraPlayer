/// Immutable token representing a lifecycle scope.
/// Once invalidated, it remains dead forever.
///
/// Usage:
/// ```dart
/// final token = lifecycleToken;  // Capture before async
/// await someAsync();
/// if (!token.isAlive) return;    // Safe check after async
/// ```
class LifecycleToken {
  final int _generation;
  final _LifecycleState _state;

  LifecycleToken._(this._generation, this._state);

  /// Whether this token is still alive.
  /// Safe to check across async boundaries.
  bool get isAlive => _state._currentGeneration == _generation;

  /// Throws if token is dead (for critical paths).
  void ensureAlive() {
    if (!isAlive) {
      throw StateError('Operation attempted on disposed lifecycle');
    }
  }
}

/// Internal state holder for lifecycle tokens.
class _LifecycleState {
  int _currentGeneration = 0;

  void invalidate() {
    _currentGeneration++;
  }
}

/// Mixin for classes that need lifecycle token management.
///
/// Usage:
/// ```dart
/// class MyManager with LifecycleTokenProvider {
///   Future<void> doAsync() async {
///     final token = lifecycleToken;
///     await someWork();
///     if (!token.isAlive) return;
///     // safe to mutate state
///   }
///
///   void dispose() {
///     invalidateLifecycle();
///     // ... rest of cleanup
///   }
/// }
/// ```
mixin LifecycleTokenProvider {
  final _LifecycleState _lifecycleState = _LifecycleState();

  /// Get current lifecycle token.
  /// Capture this before async operations.
  LifecycleToken get lifecycleToken =>
      LifecycleToken._(_lifecycleState._currentGeneration, _lifecycleState);

  /// Invalidate all existing tokens.
  /// Call this in dispose().
  void invalidateLifecycle() {
    _lifecycleState.invalidate();
  }
}
