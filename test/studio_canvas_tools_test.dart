import 'package:after_frame/src/features/motion_canvas/controllers/motion_canvas_controller.dart';
import 'package:after_frame/src/features/motion_canvas/widgets/studio_canvas.dart';
import 'package:after_frame/src/localization/app_localizations.dart';
import 'package:after_frame/src/models/media_asset.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const assets = [
    MediaAsset(
      uri: 'content://video/one',
      name: 'one.mp4',
      durationMs: 6000,
      width: 1080,
      height: 1920,
      rotation: 0,
    ),
    MediaAsset(
      uri: 'content://video/two',
      name: 'two.mp4',
      durationMs: 5000,
      width: 1920,
      height: 1080,
      rotation: 0,
    ),
  ];

  testWidgets('collage follows Live frame controls without legacy tool dock', (
    tester,
  ) async {
    final controller = MotionCanvasController(assets: assets);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: AppLanguageScope(
          controller: AppLanguageController(AppLanguage.english),
          child: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: StudioCanvasTools(
                  controller: controller,
                  onEditClip: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('COVER MOMENT'), findsOneWidget);
    expect(find.text('MOMENT TIMELINE'), findsOneWidget);
    expect(find.text('More Settings'), findsOneWidget);
    expect(find.text('Layout'), findsNothing);
    expect(find.text('Style'), findsNothing);
    expect(find.text('Transition'), findsNothing);
    expect(find.text('Music'), findsNothing);
  });
}
