import 'package:after_frame/src/localization/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Chinese and English expose the same resource keys', () {
    expect(
      AppLocalizations.keysFor(AppLanguage.chinese),
      AppLocalizations.keysFor(AppLanguage.english),
    );
  });

  test('Chinese and English resources stay language-consistent', () {
    const zh = AppLocalizations(AppLanguage.chinese);
    const en = AppLocalizations(AppLanguage.english);

    expect(zh.text('studioSubtitle'), '创造你的动态瞬间');
    expect(en.text('studioSubtitle'), 'Create your living moment');
    expect(zh.text('savedToAlbum'), contains('AfterFrame'));
    expect(en.text('savedToAlbum'), contains('AfterFrame'));
  });

  test('localized strings replace dynamic values', () {
    const zh = AppLocalizations(AppLanguage.chinese);
    const en = AppLocalizations(AppLanguage.english);

    expect(zh.text('workCount', {'count': 3}), '3 个动态记忆');
    expect(en.text('workCount', {'count': 3}), '3 living moments');
  });
}
