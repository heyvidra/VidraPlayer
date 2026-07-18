import 'dart:async';

/// ===============================
/// 1️⃣ Debounce - Only execute the last call
/// ===============================
class Debounce {
  final Duration delay;
  Timer? _timer;
  bool _isDisposed = false;

  Debounce(this.delay);

  void call(void Function() action) {
    if (_isDisposed) return;
    _timer?.cancel();
    _timer = Timer(delay, () {
      if (_isDisposed) return;
      action();
    });
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    _isDisposed = true;
    cancel();
  }
}

/// ===============================
/// 2️⃣ Throttle - Execute at most once per interval
/// ===============================
class Throttle {
  final Duration interval;
  Timer? _timer;
  bool _ready = true;
  bool _isDisposed = false;

  Throttle(this.interval);

  void call(void Function() action) {
    if (_isDisposed || !_ready) return;

    _ready = false;
    action();

    _timer = Timer(interval, () {
      if (_isDisposed) return;
      _ready = true;
    });
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    _ready = true;
  }

  void dispose() {
    _isDisposed = true;
    cancel();
  }
}

/// =================================================
/// 3️⃣ LeadingDebounce - Execute first call immediately + last call
/// =================================================
class LeadingDebounce {
  final Duration delay;

  Timer? _timer;
  bool _hasPendingTrailing = false;
  bool _leadingExecuted = false;
  bool _isDisposed = false;

  LeadingDebounce(this.delay);

  void call({
    required void Function() leading,
    required void Function() trailing,
  }) {
    if (_isDisposed) return;

    // First time window entered: execute leading
    if (!_leadingExecuted) {
      _leadingExecuted = true;
      leading();
    } else {
      // Mark trailing needed only if there are consecutive triggers
      _hasPendingTrailing = true;
    }

    _timer?.cancel();
    _timer = Timer(delay, () {
      if (_isDisposed) return;

      if (_hasPendingTrailing) {
        trailing();
      }

      // reset window
      _leadingExecuted = false;
      _hasPendingTrailing = false;
    });
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    _leadingExecuted = false;
    _hasPendingTrailing = false;
  }

  void dispose() {
    _isDisposed = true;
    cancel();
  }
}

/// =====================================
/// 4️⃣ Latest - Serialize async tasks, keep only the latest
/// =====================================
///
/// Single-flight: at most one task runs at a time. If newer tasks arrive while
/// one is in flight, only the MOST RECENT is kept and run next; older queued
/// tasks are dropped. This prevents an older write's side effects (repository
/// save, state mutation) from landing after a newer one — the old `run`
/// awaited-then-checked-token approach let both writes happen and only gated a
/// return value, so a stale result could still clobber a fresh one.
class Latest {
  Future<void> Function()? _pending;
  bool _running = false;
  bool _isDisposed = false;

  void run(Future<void> Function() task) {
    if (_isDisposed) return;
    // Supersede any task still waiting to run.
    _pending = task;
    if (!_running) _drain();
  }

  Future<void> _drain() async {
    _running = true;
    while (!_isDisposed && _pending != null) {
      final task = _pending!;
      _pending = null;
      try {
        await task();
      } catch (_) {
        // Swallow: a failed settings write shouldn't wedge the queue.
      }
    }
    _running = false;
  }

  void reset() {
    _pending = null;
  }

  void dispose() {
    _isDisposed = true;
    _pending = null;
  }
}
