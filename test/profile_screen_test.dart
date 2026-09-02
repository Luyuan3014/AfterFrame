import 'package:after_frame/src/app.dart';
import 'package:after_frame/src/widgets/after_frame_sheet.dart';
import 'package:flutter/material.dart' show Scrollable, SegmentedButton;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.afterframe/media_engine');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return switch (call.method) {
            'listExports' => <Object?>[],
            'getTemporaryCacheUsage' => <String, Object?>{
              'bytes': 1536,
              'files': 3,
            },
            'clearTemporaryCache' => null,
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

  testWidgets('profile entries are functional and album opens works', (
    tester,
  ) async {
    await tester.pumpWidget(const AfterFrameApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('我的').last);
    await tester.pumpAndSettle();

    expect(find.text('AfterFrame 本地工作区'), findsOneWidget);
    expect(find.text('记忆收藏家'), findsNothing);
    expect(find.text('设置'), findsNothing);
    expect(find.text('偏好设置'), findsOneWidget);
    expect(find.text('作品相册'), findsOneWidget);
    expect(find.text('导出画质'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('临时缓存'),
      260,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Live 容器'), findsOneWidget);
    expect(find.text('临时缓存'), findsOneWidget);
    expect(find.text('1.5 KB'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('隐私与数据'),
      180,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('隐私与数据'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('关于 AfterFrame'),
      180,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('关于 AfterFrame'), findsOneWidget);

    await tester.tap(find.text('隐私与数据'));
    await tester.pumpAndSettle();
    expect(find.textContaining('不上传媒体库内容'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('作品相册'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('作品相册'));
    await tester.pumpAndSettle();
    expect(find.text('我的作品'), findsOneWidget);

    await tester.tap(find.text('我的').last);
    await tester.pumpAndSettle();
    expect(
      calls.where((call) => call.method == 'getTemporaryCacheUsage'),
      hasLength(2),
    );
  });

  testWidgets('cache clear is confirmed and updates displayed usage', (
    tester,
  ) async {
    await tester.pumpWidget(const AfterFrameApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('我的').last);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('临时缓存'),
      260,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('临时缓存'));
    await tester.pumpAndSettle();
    expect(find.text('清理临时缓存？'), findsOneWidget);
    await tester.tap(find.text('清理'));
    await tester.pumpAndSettle();

    expect(
      calls.where((call) => call.method == 'clearTemporaryCache'),
      hasLength(1),
    );
    expect(find.text('0 B'), findsOneWidget);
    expect(find.text('临时缓存已清理'), findsOneWidget);
  });

  testWidgets('language uses a normal setting tile and changes in a sheet', (
    tester,
  ) async {
    await tester.pumpWidget(const AfterFrameApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('我的').last);
    await tester.pumpAndSettle();

    expect(find.byType(SegmentedButton), findsNothing);
    expect(find.text('App 语言'), findsOneWidget);
    await tester.tap(find.text('App 语言'));
    await tester.pumpAndSettle();
    expect(find.text('中文'), findsWidgets);
    expect(find.text('English'), findsOneWidget);

    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(find.text('App Language'), findsOneWidget);
    expect(
      calls.where((call) => call.method == 'setAppLanguage'),
      hasLength(1),
    );
  });

  testWidgets('about uses the unified sheet and celebrates on open', (
    tester,
  ) async {
    await tester.pumpWidget(const AfterFrameApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('我的').last);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('关于 AfterFrame'),
      260,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('关于 AfterFrame'));
    await tester.pump();

    expect(find.byType(AfterFrameSheet), findsOneWidget);
    expect(find.byType(AfterFrameConfetti), findsOneWidget);
    expect(find.text('1.0.0 · arm64-v8a'), findsOneWidget);
    expect(find.textContaining('不会上传媒体库内容'), findsOneWidget);

    await tester.pumpAndSettle();
  });
}
