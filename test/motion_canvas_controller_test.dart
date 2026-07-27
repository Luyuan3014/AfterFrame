import 'package:after_frame/src/features/motion_canvas/controllers/motion_canvas_controller.dart';
import 'package:after_frame/src/features/motion_canvas/models/motion_canvas_layout.dart';
import 'package:after_frame/src/models/live_rules.dart';
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

  test('a canvas starts from the shared Live playback defaults', () {
    final controller = MotionCanvasController(
      assets: const [landscape, portrait, square],
    );
    addTearDown(controller.dispose);

    expect(controller.audioEnabled, LiveDefaults.audioEnabled);
    expect(controller.loopEnabled, LiveDefaults.loopEnabled);
    expect(controller.enhancementEnabled, LiveDefaults.enhancementEnabled);
    expect(controller.playbackSpeed, LiveDefaults.playbackSpeed);
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
    expect(controller.loopEnabled, isTrue);
    expect(controller.enhancementEnabled, isFalse);
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
    'adaptive canvas preserves source framing without forced 9:16 crop',
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
      // Stacked landscapes derive a near-square canvas, not a skinny 9:16 card.
      expect(widePlan.canvas.aspectRatio, greaterThan(.8));
      expect(widePlan.canvas.aspectRatio, lessThan(1.1));
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
        // Full native pixels when the arrangement fits the export bound.
        expect(frame.retainedSourceFraction, closeTo(1, .001));
        expect(
          frame.rect.width / frame.rect.height,
          closeTo(source.width / source.height, .01),
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
      expect(frame.rect.width, landscape.width);
      expect(frame.rect.height, landscape.height);
      expect(frame.retainedSourceFraction, closeTo(1, .001));
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

  test('720p landscape pair keeps a fixed opaque gutter between panels', () {
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
    final gutter =
        plan.frames.last.rect.y -
        (plan.frames.first.rect.y + plan.frames.first.rect.height);
    // Fixed 2px gutter is filled by an opaque export overlay so Media3's
    // alpha-blended video edges cannot shimmer.
    expect(gutter, 2);
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
  });

  test('removing a source re-plans the canvas and stays undoable', () {
    final controller = MotionCanvasController(
      assets: const [landscape, portrait, square],
    );
    addTearDown(controller.dispose);

    final removed = controller.removeClip(1);

    expect(removed?.asset.uri, portrait.uri);
    expect(controller.clips, hasLength(2));
    expect(controller.frames, hasLength(2));
    expect(controller.durationMs, 6000);

    controller.restoreClip(1, removed!);

    expect(controller.assets.map((asset) => asset.uri), [
      landscape.uri,
      portrait.uri,
      square.uri,
    ]);
    expect(controller.durationMs, 4600);
  });

  test('the last remaining source cannot be removed', () {
    final controller = MotionCanvasController(assets: const [landscape]);
    addTearDown(controller.dispose);

    expect(controller.canRemoveClip, isFalse);
    expect(controller.removeClip(0), isNull);
    expect(controller.clips, hasLength(1));
  });

  test('thumbnails are addressed by clip id across reorders', () {
    final controller = MotionCanvasController(
      assets: const [landscape, portrait],
    );
    addTearDown(controller.dispose);
    final portraitId = controller.clips.last.id;

    controller.reorder(1, 0);
    controller.setThumbnail(portraitId, 'portrait.jpg');

    expect(controller.clips.first.id, portraitId);
    expect(controller.clips.first.thumbnailPath, 'portrait.jpg');
    expect(controller.clips.last.thumbnailPath, isNull);
  });

  test('manual Smart Crop focus is stored for later headroom', () {
    final controller = MotionCanvasController(
      assets: const [landscape, portrait, square],
    );
    addTearDown(controller.dispose);

    // Full-source frames leave no pan headroom; focus is still recorded so a
    // later export-bound shrink can re-center on the user's choice.
    controller.moveCropFocus(0, 10, -10);
    expect(controller.activeClip.focus.x, 1);
    expect(controller.activeClip.focus.y, 0);
    expect(controller.frames.first.crop.leftPixels, 0);
    expect(controller.frames.first.crop.topPixels, 0);
    expect(controller.frames.first.retainedSourceFraction, closeTo(1, .001));
    controller.resetSmartCrop(0);
    expect(controller.activeClip.focus.x, .5);
    expect(controller.activeClip.focus.confidence, lessThan(1));
  });
}
