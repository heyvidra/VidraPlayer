import 'package:flutter/foundation.dart';

/// Player Language Configuration
@immutable
class VidraLocale {
  final String languageCode;
  final Map<String, String>? customTranslations;

  const VidraLocale._(this.languageCode) : customTranslations = null;

  /// English
  static const VidraLocale en = VidraLocale._('en');

  /// Simplified Chinese
  static const VidraLocale zhCN = VidraLocale._('zh_CN');

  /// Traditional Chinese
  static const VidraLocale zhTW = VidraLocale._('zh_TW');

  /// Custom Language
  ///
  /// [languageCode] Language Code
  /// [customTranslations] Custom Translation Map, key is translation key, value is translated text
  const VidraLocale.custom(this.languageCode, this.customTranslations);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VidraLocale &&
          runtimeType == other.runtimeType &&
          languageCode == other.languageCode;

  @override
  int get hashCode => languageCode.hashCode;
}
