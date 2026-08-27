import 'package:after_frame/src/app.dart';
import 'package:after_frame/src/localization/app_localizations.dart';
import 'package:after_frame/src/screens/home/memory_glow_background.dart';
import 'package:after_frame/src/screens/home/recent_creations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.afterframe/media_engine');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          return switch (call.method) {
            'listExports' => <Object?>[],
            'getTemporaryCacheUsage' => <String, Object?>{
              'bytes': 0,
              'files': 0,
            },
            'getUpdateState' => <String, Object?>{
              'status': 'idle',
              'currentVersionName': '1.0.0',
              'currentVersionCode': 15,
              'abi': 'arm64-v8a',
            },
            _ => null,
          };
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> pumpHome(
    WidgetTester tester, {
    Size logical = const Size(390, 844),
    double dpr = 3,
    FakeViewPadding padding = const FakeViewPadding(top: 47, bottom: 34),
  }) async {
    tester.view.physicalSize = Size(logical.width * dpr, logical.height * dpr);
    tester.view.devicePixelRatio = dpr;
    tester.view.padding = padding;
    tester.view.viewPadding = padding;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    await tester.pumpWidget(const AfterFrameApp());
    await tester.pumpAndSettle();
  }

  testWidgets(
    'create page has a single import action and no duplicate studio entry',
    (tester) async {
      await pumpHome(tester);

      expect(find.byKey(const Key('create-hero')), findsOneWidget);
      expect(find.text('导入视频'), findsOneWidget);
      expect(find.text('开始创作'), findsOneWidget);
      expect(find.text('从视频中发现值得留下的瞬间'), findsOneWidget);
      expect(find.text('AfterFrame Studio'), findsNothing);
      expect(find.text('创作方式'), findsNothing);
      expect(find.text('余帧提示'), findsNothing);
      expect(find.text('最近创作'), findsNothing);
      expect(find.text('视频'), findsWidgets);
      expect(find.text('Live 图'), findsOneWidget);
      expect(find.text('拼图'), findsOneWidget);
      expect(find.text('选择片段'), findsOneWidget);
      expect(find.text('让瞬间流动'), findsOneWidget);
      expect(find.text('组合新的记忆'), findsOneWidget);
      expect(find.text('作品'), findsOneWidget);
    },
  );

  testWidgets('ambience reaches the display cutout while text stays clear', (
    tester,
  ) async {
    const dpr = 3.0;
    const cutout = 47.0; // FakeViewPadding is expressed in physical pixels.
    await pumpHome(
      tester,
      dpr: dpr,
      padding: const FakeViewPadding(top: cutout, bottom: 34),
    );

    // The glow has to bleed under the status bar, otherwise the aperture rings
    // are sliced off by a hard seam along the cutout.
    expect(tester.getTopLeft(find.byType(MemoryGlowBackground)), Offset.zero);
    // Content still keeps clear of the cutout.
    expect(
      tester.getTopLeft(find.text('AFTERFRAME')).dy,
      greaterThan(cutout / dpr),
    );
  });

  testWidgets('the import button hugs its label instead of the card', (
    tester,
  ) async {
    await pumpHome(tester);

    final button = tester.getSize(find.byKey(const Key('import-video-button')));
    final card = tester.getSize(find.byKey(const Key('create-hero')));
    expect(button.width, lessThan(card.width * .6));
  });

  testWidgets('create page fits a compact phone and a tall display', (
    tester,
  ) async {
    await pumpHome(tester, logical: const Size(320, 568), dpr: 2);
    expect(find.byKey(const Key('create-hero')), findsOneWidget);

    await pumpHome(tester, logical: const Size(430, 932), dpr: 3);
    expect(find.text('导入视频'), findsOneWidget);
  });

  test('relative creation time stays compact', () {
    const zh = AppLocalizations(AppLanguage.chinese);
    const en = AppLocalizations(AppLanguage.english);
    final now = DateTime(2026, 8, 27, 15);

    expect(formatWorkRelativeTime(now, zh, now: now), '刚刚');
    expect(
      formatWorkRelativeTime(
        now.subtract(const Duration(minutes: 12)),
        zh,
        now: now,
      ),
      '12分钟前',
    );
    expect(
      formatWorkRelativeTime(
        now.subtract(const Duration(hours: 3)),
        en,
        now: now,
      ),
      '3h ago',
    );
    expect(
      formatWorkRelativeTime(
        now.subtract(const Duration(days: 2)),
        zh,
        now: now,
      ),
      '2天前',
    );
  });

  testWidgets('recent creations use real exports and open the works tab', (
    tester,
  ) async {
    final now = DateTime.now();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          return switch (call.method) {
            'listExports' => <Object?>[
              <String, Object?>{
                'liveUri': 'content://images/1',
                'createdAt': now
                    .subtract(const Duration(days: 2))
                    .millisecondsSinceEpoch,
                'coverPath': '/missing-cover.jpg',
                'displayName': '峨眉山',
                'sourceCount': 1,
              },
              <String, Object?>{
                'liveUri': 'content://images/2',
                'createdAt': now
                    .subtract(const Duration(days: 1))
                    .millisecondsSinceEpoch,
                'coverPath': '/missing-cover.jpg',
                'displayName': '旅行',
                'sourceCount': 2,
              },
            ],
            'getTemporaryCacheUsage' => <String, Object?>{
              'bytes': 0,
              'files': 0,
            },
            'getUpdateState' => <String, Object?>{
              'status': 'idle',
              'currentVersionName': '1.0.0',
              'currentVersionCode': 15,
              'abi': 'arm64-v8a',
            },
            _ => null,
          };
        });

    await pumpHome(tester);

    expect(find.byKey(const Key('recent-creations')), findsOneWidget);
    expect(find.text('最近创作'), findsOneWidget);
    expect(find.text('峨眉山'), findsOneWidget);
    expect(find.text('旅行'), findsOneWidget);
    expect(find.text('Live'), findsOneWidget);
    expect(find.text('拼图'), findsWidgets);
    expect(find.text('2天前'), findsOneWidget);

    await tester.tap(find.byKey(const Key('view-all-creations')));
    await tester.pumpAndSettle();
    expect(find.text('我的作品'), findsOneWidget);
  });

  testWidgets('import card still opens the media library', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          return switch (call.method) {
            'listExports' => <Object?>[],
            'requestVideoAccess' => true,
            'listVideos' => <Object?>[],
            'getTemporaryCacheUsage' => <String, Object?>{
              'bytes': 0,
              'files': 0,
            },
            'getUpdateState' => <String, Object?>{
              'status': 'idle',
              'currentVersionName': '1.0.0',
              'currentVersionCode': 15,
              'abi': 'arm64-v8a',
            },
            _ => null,
          };
        });

    await pumpHome(tester);
    await tester.tap(find.byKey(const Key('create-hero')));
    await tester.pumpAndSettle();
    expect(find.text('选择创作素材'), findsOneWidget);
  });
}
