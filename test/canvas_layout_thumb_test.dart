import 'package:after_frame/src/features/motion_canvas/widgets/canvas_layout_thumb.dart';
import 'package:after_frame/src/models/live_rules.dart';
import 'package:after_frame/src/models/media_asset.dart';
import 'package:after_frame/src/services/media_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const portrait = MediaAsset(
    uri: 'content://video/portrait',
    name: 'portrait.mp4',
    durationMs: 5000,
    width: 1080,
    height: 1920,
    rotation: 0,
  );
  const landscape = MediaAsset(
    uri: 'content://video/landscape',
    name: 'landscape.mp4',
    durationMs: 6000,
    width: 1920,
    height: 1080,
    rotation: 0,
  );
  const square = MediaAsset(
    uri: 'content://video/square',
    name: 'square.mp4',
    durationMs: 7000,
    width: 1080,
    height: 1080,
    rotation: 0,
  );

  Future<void> pumpThumb(WidgetTester tester, List<MediaAsset> assets) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: CanvasLayoutThumb(
                assets: assets,
                engine: const MediaEngine(),
              ),
            ),
          ),
        ),
      );

  testWidgets('the miniature shows one cell per chosen source', (tester) async {
    await pumpThumb(tester, const [portrait]);
    expect(tester.widgetList(find.byType(AnimatedPositioned)), hasLength(1));

    await pumpThumb(tester, const [portrait, landscape]);
    expect(tester.widgetList(find.byType(AnimatedPositioned)), hasLength(2));

    await pumpThumb(tester, const [portrait, landscape, square]);
    expect(
      tester.widgetList(find.byType(AnimatedPositioned)),
      hasLength(maxLiveSources),
    );
  });

  testWidgets('cells stay inside the miniature canvas', (tester) async {
    await pumpThumb(tester, const [portrait, landscape, square]);
    final canvas = tester.getRect(find.byType(CanvasLayoutThumb));

    for (final cell in tester.widgetList<AnimatedPositioned>(
      find.byType(AnimatedPositioned),
    )) {
      expect(cell.left, greaterThanOrEqualTo(0));
      expect(cell.top, greaterThanOrEqualTo(0));
      expect(cell.left! + cell.width!, lessThanOrEqualTo(canvas.width + .01));
      expect(cell.top! + cell.height!, lessThanOrEqualTo(canvas.height + .01));
    }
  });
}
