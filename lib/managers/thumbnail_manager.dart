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

  /// Optional sprite-cache lookup, filled by the background sweep. This is
  /// what makes hover previews work off macOS at all; on macOS it is the
  /// fallback when the native generator has nothing (HLS sources it can't
  /// open, frames it fails on).
  final Uint8List? Function(double seconds)? spriteLookup;

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

  ThumbnailManager({
    required this.url,
    this.maxCacheSize = 50,
    this.spriteLookup,
  });

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
    if (_isDisposed) return null;
    // Off macOS there is no native generator: the sprite cache is the only
    // source. On macOS the native path stays primary (seek-accurate, larger)
    // and the sprite serves as its fallback further down.
    if (!Platform.isMacOS) return spriteLookup?.call(seconds);

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
      // Native came up empty (AVAssetImageGenerator fails on some HLS) —
      // a sprite tile beats an empty preview.
      return data ?? spriteLookup?.call(seconds);
    }

    // Inside the window: this call supersedes any earlier pending one. Complete
    // the superseded request now (with the nearest cached frame) so its awaiter
    // never hangs, then become the new trailing request.
    _pendingCompleter?.complete(
      _nearestCached(key) ?? spriteLookup?.call(seconds),
    );
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
        if (!completer.isCompleted) {
          completer.complete(data ?? spriteLookup?.call(seconds));
        }
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
