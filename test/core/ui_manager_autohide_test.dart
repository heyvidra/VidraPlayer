import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vidra_player/core/model/player_behavior.dart';
import 'package:vidra_player/managers/ui_manager.dart';

/// Regression: auto-advance + intro-skip left the toolbar stuck visible.
///
/// The auto-hide timer only (re)arms when playback state *changes*. Any path
/// that shows controls persistently cancels the timer, and a following
/// "playing" report is NOT a change (isPlaying was already true) — so the
/// timer was never re-armed and the toolbar never hid.
void main() {
  const behavior = PlayerBehavior(autoHideDelay: Duration(seconds: 3));

  test('redundant isPlaying:true re-arms auto-hide after a persistent show',
      () {
    fakeAsync((async) {
      final ui = UIStateManager(behavior: behavior);
      addTearDown(ui.dispose);

      // Playing + controls visible with a live auto-hide timer.
      ui.updatePlaybackState(isInitialized: true, isPlaying: true);
      ui.showControlsTemporarily();
      async.elapse(const Duration(milliseconds: 100)); // flush 50ms debounce
      expect(ui.currentVisibility.showControls, isTrue);

      // A persistent show cancels the auto-hide timer.
      ui.showControlsPersistently();
      expect(ui.currentVisibility.showControls, isTrue);

      // A "playing" report that is NOT a state change (already playing).
      // Old code: ignored -> timer stays cancelled -> toolbar stuck.
      // Fixed code: backstop re-arms the timer.
      ui.updatePlaybackState(isPlaying: true);

      async.elapse(const Duration(seconds: 4));
      expect(ui.currentVisibility.showControls, isFalse,
          reason: 'toolbar should auto-hide after autoHideDelay');
    });
  });

  test('does not hide while paused', () {
    fakeAsync((async) {
      final ui = UIStateManager(behavior: behavior);
      addTearDown(ui.dispose);

      ui.updatePlaybackState(isInitialized: true, isPlaying: false);
      ui.showControlsPersistently();
      ui.updatePlaybackState(isPlaying: false);

      async.elapse(const Duration(seconds: 4));
      expect(ui.currentVisibility.showControls, isTrue,
          reason: 'paused controls must stay visible');
    });
  });
}
