import 'package:after_frame/src/localization/app_localizations.dart';
import 'package:after_frame/src/models/live_rules.dart';
import 'package:after_frame/src/screens/video_picker_screen.dart';
import 'package:after_frame/src/services/media_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const channel = MethodChannel('com.afterframe/media_engine');

  Map<String, Object?> video(int index) => {
    'uri': 'content://video/$index',
    'name': 'clip$index.mp4',
    'durationMs': 5000,
    'width': 1080,
    'height': 1920,
    'rotation': 0,
  };

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'requestVideoAccess':
              return true;
            case 'listVideos':
              return [for (var index = 0; index < 9; index++) video(index)];
            case 'videoThumbnail':
              return '';
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> pumpPicker(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: AppLanguageScope(
          controller: AppLanguageController(AppLanguage.english),
          child: const VideoPickerScreen(engine: MediaEngine()),
        ),
      ),
    );
    // Thumbnails resolve to an endless placeholder spinner, so the frames are
    // advanced by hand instead of settled.
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> pick(WidgetTester tester, int index) async {
    await tester.tap(
      find.descendant(
        of: find.byType(GridView),
        matching: find.byKey(ValueKey('content://video/$index')),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('the announcement bar stays docked and leaves the library usable', (
    tester,
  ) async {
    await pumpPicker(tester);
    final screen = tester.getSize(find.byType(Scaffold));

    await pick(tester, 0);

    final bar = tester.getRect(find.text('Enter Studio'));
    expect(
      bar.center.dy,
      greaterThan(screen.height * .8),
      reason: 'a bar that leaves the bottom would cover the library',
    );
    expect(find.byType(GridView), findsOneWidget);
    expect(find.text('Choose Studio Material'), findsOneWidget);
  });

  testWidgets('every source can still be picked after the first one', (
    tester,
  ) async {
    await pumpPicker(tester);

    await pick(tester, 0);
    expect(find.text('Live Frame · original framing'), findsOneWidget);
    expect(find.text('room for 2 more'), findsOneWidget);

    await pick(tester, 1);
    expect(find.text('2 videos selected'), findsOneWidget);
    expect(find.text('Live Collage · 2 frames'), findsOneWidget);

    await pick(tester, 2);
    expect(find.text('Live Collage · $maxLiveSources frames'), findsOneWidget);
    expect(find.textContaining('room for'), findsNothing);
  });

  testWidgets('picking beyond the limit keeps the selection intact', (
    tester,
  ) async {
    await pumpPicker(tester);

    for (var index = 0; index < maxLiveSources; index++) {
      await pick(tester, index);
    }
    await pick(tester, maxLiveSources);

    expect(find.text('A moment holds up to 3 clips'), findsOneWidget);
    expect(
      find.text('$maxLiveSources videos selected'),
      findsOneWidget,
      reason: 'an over-limit tap must not drop or replace chosen sources',
    );
  });

  testWidgets('deselecting the last source retires the bar', (tester) async {
    await pumpPicker(tester);

    await pick(tester, 0);
    expect(find.text('Enter Studio'), findsOneWidget);

    await pick(tester, 0);
    expect(find.text('Enter Studio'), findsNothing);
    expect(find.byType(GridView), findsOneWidget);
  });
}
