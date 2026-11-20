import 'package:flutter_test/flutter_test.dart';
import 'package:vidra_player/core/localization/localization.dart';
import 'package:vidra_player/core/model/player_locale.dart';
import 'package:vidra_player/core/player_exceptions.dart';

void main() {
  test('a known error code is said in the UI language, without the URL', () {
    final error = NetworkException(
      'Video source unavailable',
      url: Uri.parse('https://cdn.example/secret/path.m3u8'),
      code: 'SERVICE_UNAVAILABLE',
    );
    final zh = VidraLocalization(
      VidraLocale.zhCN,
    ).errorMessage(error.code, error.message);
    expect(zh, '片源没有响应');
    final en = VidraLocalization(
      VidraLocale.en,
    ).errorMessage(error.code, error.message);
    expect(en, isNot(contains('cdn.example')));
    expect(en, isNot(error.message));
  });

  test('an unknown code keeps the message as thrown', () {
    final error = PlayerException('something odd', code: 'NEVER_HEARD_OF_IT');
    expect(
      VidraLocalization(
        VidraLocale.zhCN,
      ).errorMessage(error.code, error.message),
      'something odd',
    );
  });
}
