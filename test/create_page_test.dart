import 'package:after_frame/src/app.dart';
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

  testWidgets(
    'create page has a single import action and no duplicate studio entry',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const AfterFrameApp());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('create-hero')), findsOneWidget);
      expect(find.text('导入素材'), findsOneWidget);
      expect(find.text('AfterFrame Studio'), findsNothing);
      expect(find.text('创作方式'), findsNothing);
      expect(find.text('余帧提示'), findsNothing);
      expect(find.text('视频'), findsWidgets);
      expect(find.text('Live 图'), findsOneWidget);
      expect(find.text('拼图'), findsOneWidget);
    },
  );
}
