import 'dart:async';
import 'package:flutter/services.dart';
import 'dart:collection';
import 'dart:io';
import '../utils/log.dart';

/// Manages video thumbnail generation and caching.
class ThumbnailManager {
  static const MethodChannel _channel = MethodChannel('vidra_player');

  final String url;
  final int maxCacheSize;

  // LRU Cache: position (seconds) -> thumbnail data
  final LinkedHashMap<int, Uint8List> _cache = LinkedHashMap<int, Uint8List>();

  // Native-fetch rate limiting (leading + trailing). A plain leading-only
  // throttle silently drops the last call of a scrub burst — the exact frame
  // the user settled on — and its awaiting Future never completes, leaving the
  // preview stuck on a spinner. Here every request completes: the leading one
  // runs now, the trailing (latest superseding) one runs when the window
  // elapses, and any request superseded before it runs is completed too.
  static const _kFetchInterval = Duration(milliseconds: 150);
  Timer? _fetchTimer;
  bool _fetchReady = true;
  double? _pendingSeconds;
  Completer<Uint8List?>? _pendingCompleter;

  bool _isDisposed = false;
  String? _preparedUrl;

  ThumbnailManager({required this.url, this.maxCacheSize = 50});

  Future<void> prepare() async {
    if (!Platform.isMacOS) return;
    if (_isDisposed || _preparedUrl == url) return;
    try {
      await _channel.invokeMethod('prepareThumbnailGenerator', {'url': url});
      _preparedUrl = url;
    } catch (e) {
      logger.e("[ThumbnailManager] Error preparing generator: $e");
    }
  }

  Future<Uint8List?> getThumbnail(double seconds) async {
    if (!Platform.isMacOS) return null;
    if (_isDisposed) return null;

    final int key = seconds.round();

    // Check cache
    if (_cache.containsKey(key)) {
      // Move to end (most recently used)
      final data = _cache.remove(key)!;
      _cache[key] = data;
      return data;
    }

    // Prepare if not already prepared
    if (_preparedUrl != url) {
      await prepare();
    }

    // Leading edge: run immediately, then open the throttle window.
    if (_fetchReady) {
      _fetchReady = false;
      final data = await _fetchNative(seconds, key);
      _startFetchWindow();
      return data;
    }

    // Inside the window: this call supersedes any earlier pending one. Complete
    // the superseded request now (with the nearest cached frame) so its awaiter
    // never hangs, then become the new trailing request.
    _pendingCompleter?.complete(_nearestCached(key));
    final completer = Completer<Uint8List?>();
    _pendingSeconds = seconds;
    _pendingCompleter = completer;
    return completer.future;
  }

  Future<Uint8List?> _fetchNative(double seconds, int key) async {
    if (_isDisposed) return null;
    try {
      final Uint8List? data = await _channel.invokeMethod('getThumbnail', {
        'url': url,
        'time': seconds,
      });
      if (data != null) _addToCache(key, data);
      return data;
    } catch (e) {
      logger.e("[ThumbnailManager] Error getting thumbnail at $seconds: $e");
      return null;
    }
  }

  void _startFetchWindow() {
    _fetchTimer = Timer(_kFetchInterval, () async {
      if (_isDisposed) return;
      final seconds = _pendingSeconds;
      final completer = _pendingCompleter;
      _pendingSeconds = null;
      _pendingCompleter = null;
      if (seconds != null && completer != null) {
        // Trailing edge: fetch the last requested position and reopen a window.
        final data = await _fetchNative(seconds, seconds.round());
        if (!completer.isCompleted) completer.complete(data);
        if (!_isDisposed) _startFetchWindow();
      } else {
        _fetchReady = true;
      }
    });
  }

  /// Nearest cached frame within ±2s of [key], or null. Used to satisfy a
  /// superseded request without a native round-trip.
  Uint8List? _nearestCached(int key) {
    for (var delta = 0; delta <= 2; delta++) {
      final hit = _cache[key - delta] ?? _cache[key + delta];
      if (hit != null) return hit;
    }
    return null;
  }

  void _addToCache(int key, Uint8List data) {
    if (_cache.length >= maxCacheSize) {
      // Remove least recently used (first item in LinkedHashMap)
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = data;
  }

  void dispose() {
    _isDisposed = true;
    _cache.clear();
    _fetchTimer?.cancel();
    _fetchTimer = null;
    // Don't strand a still-awaiting preview on teardown.
    if (_pendingCompleter?.isCompleted == false) {
      _pendingCompleter!.complete(null);
    }
    _pendingCompleter = null;
    _pendingSeconds = null;
    // Only release the native generator if this manager actually prepared one
    // — otherwise a throwaway/never-used manager (or a non-macOS platform)
    // would tear down a generator owned by a live manager. Pass the url so the
    // native side removes only THIS generator: with two live controllers
    // (grid preview, main + mini player) an id-less dispose would tear down the
    // other controller's active generator.
    if (_preparedUrl != null) {
      _channel.invokeMethod('disposeThumbnailGenerator', {'url': _preparedUrl});
      _preparedUrl = null;
    }
  }
}
