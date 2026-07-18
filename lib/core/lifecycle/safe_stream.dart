import 'dart:async';
import 'lifecycle_token.dart';

/// Safe emit to StreamController with lifecycle check.
///
/// Usage:
/// ```dart
/// final token = lifecycleToken;
/// await someAsync();
/// safeEmit(_controller, event, token);
/// ```
void safeEmit<T>(
  StreamController<T> controller,
  T event,
  LifecycleToken token,
) {
  if (token.isAlive && !controller.isClosed) {
    controller.add(event);
  }
}

/// Safe emit with optional component name for debugging.
///
/// Can be extended to add Sentry breadcrumbs when operations are skipped.
void safeEmitWithBreadcrumb<T>(
  StreamController<T> controller,
  T event,
  LifecycleToken token, {
  String? component,
}) {
  if (!token.isAlive) {
    // Optional: Add Sentry breadcrumb
    // Sentry.addBreadcrumb(Breadcrumb(
    //   message: 'Skipped emit after lifecycle end',
    //   category: 'lifecycle',
    //   level: SentryLevel.info,
    //   data: {
    //     'component': component,
    //     'event_type': T.toString(),
    //   },
    // ));
    return;
  }

  if (!controller.isClosed) {
    controller.add(event);
  }
}
