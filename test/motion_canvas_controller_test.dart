import 'package:after_frame/src/features/motion_canvas/controllers/motion_canvas_controller.dart';
import 'package:after_frame/src/features/motion_canvas/models/motion_canvas_layout.dart';
import 'package:after_frame/src/models/media_asset.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const landscape = MediaAsset(
    uri: 'content://video/landscape',
    name: 'landscape.mp4',
    durationMs: 8000,
    width: 1920,
    height: 1080,
    rotation: 0,
  );
  const portrait = MediaAsset(
    uri: 'content://video/portrait',
    name: 'portrait.mp4',
    durationMs: 4600,
    width: 1080,
    height: 1920,
    rotation: 0,
  );
  const square = MediaAsset(
    uri: 'content://video/square',
    name: 'square.mp4',
    durationMs: 7200,
    width: 1080,
    height: 1080,
    rotation: 0,
  );

  test('master timeline uses the shortest synchronized clip', () {
    final controller = MotionCanvasController(
      assets: const [landscape, portrait, square],
    );
    addTearDown(controller.dispose);

    expect(controller.durationMs, 4600);
    controller.setPosition(9000);
    expect(controller.positionMs, 4600);
  });

  test('template produces subject-aware focus and remains editable', () {
    final controller = MotionCanvasController(
      assets: const [landscape, portrait, square],
    );
    addTearDown(controller.dispose);

    controller.applyTemplate(MotionTemplate.sunsetStory);

    expect(controller.clips.first.focus.y, lessThan(.4));
    expect(controller.style, MotionStyle.dusk);
    expect(controller.transition, MotionTransition.softBlurBlend);
  });

  test('clip order and independent trims are preserved', () {
    final controller = MotionCanvasController(
      assets: const [landscape, portrait, square],
    );
    addTearDown(controller.dispose);

    controller.reorder(0, 3);
    expect(controller.clips.last.asset.uri, landscape.uri);
    controller.setTrim(0, 400, 2400);
    expect(controller.clips.first.trimStartMs, 400);
    expect(controller.clips.first.trimEndMs, 2400);
    expect(controller.durationMs, 2000);
  });

  test('smart layout bounds mixed-aspect clip heights', () {
    const layout = MotionCanvasLayout();
    expect(
      layout.heightFor(landscape.aspectRatio),
      inInclusiveRange(360, 1120),
    );
    expect(layout.heightFor(portrait.aspectRatio), 1120);
    expect(layout.heightFor(square.aspectRatio), 1080);
  });
}
