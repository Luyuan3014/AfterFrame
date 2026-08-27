import 'package:after_frame/src/localization/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Chinese and English expose the same resource keys', () {
    expect(
      AppLocalizations.keysFor(AppLanguage.chinese),
      AppLocalizations.keysFor(AppLanguage.english),
    );
  });

  test('localized resource placeholders stay complete', () {
    expect(
      AppLocalizations.placeholdersFor(AppLanguage.chinese),
      AppLocalizations.placeholdersFor(AppLanguage.english),
    );
  });

  test('Chinese and English resources stay language-consistent', () {
    const zh = AppLocalizations(AppLanguage.chinese);
    const en = AppLocalizations(AppLanguage.english);

    expect(zh.text('enterStudio'), '进入 Studio');
    expect(en.text('enterStudio'), 'Enter Studio');
    expect(zh.text('importVideo'), '导入视频');
    expect(en.text('importVideo'), 'Import video');
    expect(zh.text('navWorks'), '作品');
    expect(en.text('navWorks'), 'Works');
    expect(zh.text('savedToAlbum'), contains('AfterFrame'));
    expect(en.text('savedToAlbum'), contains('AfterFrame'));
  });

  test('localized strings replace dynamic values', () {
    const zh = AppLocalizations(AppLanguage.chinese);
    const en = AppLocalizations(AppLanguage.english);

    expect(zh.text('workCount', {'count': 3}), '3 个动态记忆');
    expect(en.text('workCount', {'count': 3}), '3 living moments');
  });

  test('the composition summary is derived from the source count', () {
    const zh = AppLocalizations(AppLanguage.chinese);
    const en = AppLocalizations(AppLanguage.english);

    expect(zh.text('canvasSummary', {'count': 3}), 'Live 拼图 · 3 格');
    expect(en.text('canvasSummary', {'count': 3}), 'Live Collage · 3 frames');
    expect(zh.text('singleFrameSummary'), contains('单帧'));
    expect(en.text('singleFrameSummary'), contains('Frame'));
    expect(zh.text('addSource'), '添加素材');
    expect(en.text('liveBadge'), 'LIVE');
    expect(zh.text('addSourceHint', {'count': 2}), contains('2'));
  });
}
