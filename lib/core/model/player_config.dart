import 'package:flutter/material.dart';

import 'player_behavior.dart';
import 'player_features.dart';
import 'player_locale.dart';
import 'player_ui_theme.dart';

/// Player Configuration
@immutable
class PlayerConfig {
  final int initialEpisodeIndex;
  final bool? episodesSort; // true: ascending, false: descending
  final PlayerUITheme theme;
  final PlayerFeatures features;
  final PlayerBehavior behavior;
  final Widget? leading;
  final VidraLocale? locale;

  const PlayerConfig({
    this.initialEpisodeIndex = 0,
    this.episodesSort = true,
    this.theme = const PlayerUITheme.dark(),
    this.features = const PlayerFeatures.all(),
    this.behavior = const PlayerBehavior(),
    this.leading,
    this.locale,
  });

  PlayerConfig copyWith({
    int? initialEpisodeIndex,
    bool? episodesSort,
    PlayerUITheme? theme,
    PlayerFeatures? features,
    PlayerBehavior? behavior,
    Widget? leading,
    VidraLocale? locale,
  }) {
    return PlayerConfig(
      initialEpisodeIndex: initialEpisodeIndex ?? this.initialEpisodeIndex,
      episodesSort: episodesSort ?? this.episodesSort,
      theme: theme ?? this.theme,
      features: features ?? this.features,
      behavior: behavior ?? this.behavior,
      leading: leading ?? this.leading,
      locale: locale ?? this.locale,
    );
  }

  // Note: [theme]/[leading] compare by identity — enough to detect "a new
  // object was supplied", which is what config-change guards need without
  // deep-comparing every theme token.
  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is PlayerConfig &&
            runtimeType == other.runtimeType &&
            initialEpisodeIndex == other.initialEpisodeIndex &&
            episodesSort == other.episodesSort &&
            identical(theme, other.theme) &&
            features == other.features &&
            behavior == other.behavior &&
            identical(leading, other.leading) &&
            locale == other.locale;
  }

  @override
  int get hashCode => Object.hashAll([
        initialEpisodeIndex,
        episodesSort,
        identityHashCode(theme),
        features,
        behavior,
        identityHashCode(leading),
        locale,
      ]);
}
