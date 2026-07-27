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
    'adaptive canvas chooses a balanced frame family without source scaling',
    () {
      const layout = MotionCanvasLayout();
      final widePlan = layout.planFor(const [
        CanvasSourceGeometry(width: 1920, height: 1080),
        CanvasSourceGeometry(width: 1920, height: 1080),
      ]);
      final mixedPlan = layout.planFor(const [
        CanvasSourceGeometry(width: 1080, height: 1920),
        CanvasSourceGeometry(width: 1920, height: 1080),
        CanvasSourceGeometry(width: 1080, height: 1080),
      ]);

      expect(widePlan.kind, AdaptiveLayoutKind.verticalTimeFlow);
      expect(mixedPlan.frames, hasLength(3));
      for (var index = 0; index < mixedPlan.frames.length; index++) {
        final frame = mixedPlan.frames[index];
        final source = const [
          CanvasSourceGeometry(width: 1080, height: 1920),
          CanvasSourceGeometry(width: 1920, height: 1080),
          CanvasSourceGeometry(width: 1080, height: 1080),
        ][index];
        expect(frame.crop.width * source.width, closeTo(frame.rect.width, .01));
        expect(
          frame.crop.height * source.height,
          closeTo(frame.rect.height, .01),
        );
      }
    },
  );

  test('two landscape clips use full-width stacked cells', () {
    final controller = MotionCanvasController(
      assets: const [landscape, landscape],
    );
    addTearDown(controller.dispose);

    expect(controller.canvasPlan.kind, AdaptiveLayoutKind.verticalTimeFlow);
    for (final frame in controller.frames) {
      expect(frame.rect.width, controller.canvasPlan.canvas.width);
      expect(frame.rect.height, lessThanOrEqualTo(1080));
      expect(
        frame.crop.width * landscape.width,
        closeTo(frame.rect.width, .01),
      );
      expect(
        frame.crop.height * landscape.height,
        closeTo(frame.rect.height, .01),
      );
    }
  });

  test('720p landscape pair never selects decorative Film Strip gutters', () {
    const hdLandscape = MediaAsset(
      uri: 'content://video/hd-landscape',
      name: 'hd-landscape.mp4',
      durationMs: 5000,
      width: 1280,
      height: 720,
      rotation: 0,
    );
    final controller = MotionCanvasController(
      assets: const [hdLandscape, hdLandscape],
    );
    addTearDown(controller.dispose);

    final plan = controller.canvasPlan;
    expect(plan.kind, AdaptiveLayoutKind.verticalTimeFlow);
    expect(plan.frames.first.rect.y, 0);
    expect(
      plan.frames.last.rect.y + plan.frames.last.rect.height,
      plan.canvas.height,
    );
    final uncoveredPixels =
        plan.canvas.width * plan.canvas.height -
        plan.frames.fold<double>(
          0,
          (sum, frame) => sum + frame.rect.width * frame.rect.height,
        );
    expect(
      uncoveredPixels / (plan.canvas.width * plan.canvas.height),
      lessThan(.01),
    );
    expect(
      plan.frames.last.rect.y -
          (plan.frames.first.rect.y + plan.frames.first.rect.height),
      lessThanOrEqualTo(4),
    );
  });

  test('manual Smart Crop focus is clamped and changes the crop window', () {
    final controller = MotionCanvasController(
      assets: const [landscape, portrait, square],
    );
    addTearDown(controller.dispose);

    final before = controller.frames.first.crop.left;
    controller.moveCropFocus(0, 10, -10);
    expect(controller.activeClip.focus.x, 1);
    expect(controller.activeClip.focus.y, 0);
    expect(controller.frames.first.crop.left, greaterThanOrEqualTo(before));
    expect(controller.frames.first.crop.leftPixels, isA<int>());
    controller.resetSmartCrop(0);
    expect(controller.activeClip.focus.x, .5);
    expect(controller.activeClip.focus.confidence, lessThan(1));
  });
}
