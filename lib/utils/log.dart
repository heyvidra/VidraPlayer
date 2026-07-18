import 'package:logger/logger.dart';

/// Internal logger for VidraPlayer.
///
/// This logger is ONLY active in debug builds. In release builds,
/// it becomes a no-op logger with zero overhead.
Logger get logger {
  // Only create logger in debug mode
  Logger? instance;
  assert(() {
    instance = Logger(
      printer: PrettyPrinter(
        dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
      ),
    );
    return true;
  }());
  return instance ?? _noOpLogger;
}

final _noOpLogger = Logger(
  printer: PrettyPrinter(),
  level: Level.off, // No logging in release
);

Logger get loggerNoStack {
  Logger? instance;
  assert(() {
    instance = Logger(printer: PrettyPrinter(methodCount: 0));
    return true;
  }());
  return instance ?? _noOpLogger;
}
