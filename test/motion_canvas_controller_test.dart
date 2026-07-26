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

  test(
    'adaptive layout maximizes no-crop occupancy of the portrait canvas',
    () {
      const layout = MotionCanvasLayout();
      final widePlan = layout.planFor(const [16 / 9, 16 / 9]);
      final mixedPlan = layout.planFor(const [9 / 16, 16 / 9, 1]);

      expect(widePlan.kind, AdaptiveLayoutKind.splitHorizontal);
      expect(mixedPlan.slots, hasLength(3));
      expect(mixedPlan.slots.first.x, 0);
      expect(
        mixedPlan.slots.last.y + mixedPlan.slots.last.height,
        closeTo(1, .001),
      );
    },
  );

  test('two landscape clips fill width and preserve every source pixel', () {
    final controller = MotionCanvasController(
      assets: const [landscape, landscape],
    );
    addTearDown(controller.dispose);

    expect(controller.canvasPlan.kind, AdaptiveLayoutKind.splitHorizontal);
    for (final slot in controller.contentSlots) {
      expect(slot.width, 1);
      final physicalAspect =
          slot.width *
          controller.layout.canvasWidth /
          (slot.height * controller.layout.canvasHeight);
      expect(physicalAspect, closeTo(landscape.aspectRatio, .0001));
    }
  });

  test('manual positioning keeps aspect ratio and can be reset', () {
    final controller = MotionCanvasController(assets: const [landscape]);
    addTearDown(controller.dispose);
    final centered = controller.contentSlots.single;

    controller.moveClipFocus(0, -.8, .9);
    expect(controller.activeClip.focus.x, 0);
    expect(controller.activeClip.focus.y, 1);
    final moved = controller.contentSlots.single;
    expect(moved.y, greaterThan(centered.y));
    expect(moved.aspectRatio, closeTo(centered.aspectRatio, .0001));
    controller.resetClipFocus(0);
    expect(controller.activeClip.focus.x, .5);
    expect(controller.activeClip.focus.y, .5);
  });
}
