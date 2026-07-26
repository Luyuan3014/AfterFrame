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

  test('collage uses the same advanced settings model as Live frame', () {
    final controller = MotionCanvasController(
      assets: const [landscape, portrait, square],
    );
    addTearDown(controller.dispose);

    controller.toggleAudio();
    controller.toggleLoop();
    controller.toggleEnhancement();
    controller.setPlaybackSpeed(1.5);

    expect(controller.audioEnabled, isFalse);
    expect(controller.loopEnabled, isFalse);
    expect(controller.enhancementEnabled, isTrue);
    expect(controller.playbackSpeed, 1.5);
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
    'adaptive layout minimizes cover crop and fills the portrait canvas',
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

  test('two landscape clips use full-width stacked cells', () {
    final controller = MotionCanvasController(
      assets: const [landscape, landscape],
    );
    addTearDown(controller.dispose);

    expect(controller.canvasPlan.kind, AdaptiveLayoutKind.splitHorizontal);
    for (final slot in controller.contentSlots) {
      expect(slot.width, 1);
      expect(slot.height, closeTo(.496, .001));
    }
  });

  test('render slots cover the complete canvas without outer gutters', () {
    final controller = MotionCanvasController(
      assets: const [landscape, portrait, square],
    );
    addTearDown(controller.dispose);

    final slots = controller.contentSlots;
    expect(slots, hasLength(3));
    expect(slots.any((slot) => slot.x == 0 && slot.y == 0), isTrue);
    expect(
      slots.any(
        (slot) =>
            (slot.x + slot.width - 1).abs() < .001 ||
            (slot.y + slot.height - 1).abs() < .001,
      ),
      isTrue,
    );
  });
}
