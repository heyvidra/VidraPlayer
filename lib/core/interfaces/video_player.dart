import 'dart:async';

import 'package:flutter/material.dart';

import '../model/model.dart';
import '../state/states.dart';

abstract class IVideoPlayer {
  // ---------- lifecycle ----------
  Future<void> initialize(VideoSource source);
  Future<void> dispose();
  Future<void> reset();

  // ---------- playback ----------
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);
  Future<void> setPlaybackSpeed(double speed);

  // ---------- state ----------
  Duration get duration;
  Duration get position;
  bool get isPlaying;
  bool get isLive;

  //----------------------------
  VideoSize? get videoSize;

  Stream<Duration> get positionStream;
  Stream<BufferingState> get bufferingStream;
  Stream<bool> get isPlayingStream;
  Stream<bool> get isLiveStream;
  Stream<PlayerError?> get errorStream;
  Stream<List<BufferRange>> get bufferedStream;

  /// Emits `true` when the current media reaches its natural end, and `false`
  /// when a new media is opened / playback restarts. This is the REAL
  /// end-of-media signal from the underlying player — prefer it over
  /// position-vs-duration threshold heuristics, which are unreliable on
  /// keyframe-sparse HLS and live streams.
  Stream<bool> get completedStream;

  //--------------- videosize---------
  Stream<VideoSize?> get videoSizeStream;

  // ---------- rendering ----------
  Widget render({Key? key, BoxFit fit, Alignment alignment});
}
