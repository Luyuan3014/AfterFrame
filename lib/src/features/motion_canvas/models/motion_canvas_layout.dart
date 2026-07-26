import 'dart:math' as math;

enum MotionTemplate { travelDiary, sunsetStory, filmStrip, minimalMemory }

enum MotionTransition { softBlurBlend, softFade, lightLeak, blur, filmGrain }

enum MotionStyle { cinematic, film, clean, dusk }

enum MotionTool { layout, style, transition, music, export }

enum MotionExportFormat { motionPhoto, mp4 }

enum AdaptiveLayoutKind {
  single,
  splitVertical,
  splitHorizontal,
  heroLeft,
  heroTop,
}

/// A normalized video slot. Coordinates are in the 0...1 canvas space and
/// are shared verbatim with the Android Media3 compositor.
class CanvasSlot {
  const CanvasSlot(this.x, this.y, this.width, this.height);

  final double x;
  final double y;
  final double width;
  final double height;

  double get aspectRatio => width / height;

  List<double> get encoded => [x, y, width, height];
}

class AdaptiveCanvasPlan {
  const AdaptiveCanvasPlan({required this.kind, required this.slots});

  final AdaptiveLayoutKind kind;
  final List<CanvasSlot> slots;

  /// Fits every source inside its layout cell without dropping source pixels.
  /// [focuses] position the intact video in any remaining free space.
  List<CanvasSlot> fittedContentSlots({
    required double canvasAspectRatio,
    required List<double> sourceAspectRatios,
    required List<({double x, double y})> focuses,
  }) => [
    for (var index = 0; index < slots.length; index++)
      _fitContent(
        slots[index],
        canvasAspectRatio,
        sourceAspectRatios[index],
        focuses[index],
      ),
  ];

  static CanvasSlot _fitContent(
    CanvasSlot cell,
    double canvasAspectRatio,
    double sourceAspectRatio,
    ({double x, double y}) focus,
  ) {
    final safeAspect = sourceAspectRatio.isFinite && sourceAspectRatio > 0
        ? sourceAspectRatio
        : 9 / 16;
    final heightAtFullWidth = cell.width * canvasAspectRatio / safeAspect;
    if (heightAtFullWidth <= cell.height) {
      final freeY = cell.height - heightAtFullWidth;
      return CanvasSlot(
        cell.x,
        cell.y + freeY * focus.y.clamp(0, 1),
        cell.width,
        heightAtFullWidth,
      );
    }
    final widthAtFullHeight = cell.height * safeAspect / canvasAspectRatio;
    final freeX = cell.width - widthAtFullHeight;
    return CanvasSlot(
      cell.x + freeX * focus.x.clamp(0, 1),
      cell.y,
      widthAtFullHeight,
      cell.height,
    );
  }
}

/// Chooses the arrangement with the largest no-crop occupied area for the
/// imported media. The output canvas is always portrait 9:16.
class MotionCanvasLayout {
  const MotionCanvasLayout({
    this.canvasWidth = 1080,
    this.canvasHeight = 1920,
    this.cornerRadius = 22,
    this.gap = .008,
  });

  final int canvasWidth;
  final int canvasHeight;
  final double cornerRadius;
  final double gap;

  double get aspectRatio => canvasWidth / canvasHeight;

  AdaptiveCanvasPlan planFor(List<double> sourceAspectRatios) {
    final ratios = sourceAspectRatios
        .take(3)
        .map((value) {
          if (!value.isFinite || value <= 0) return 9 / 16;
          return value.clamp(.2, 5).toDouble();
        })
        .toList(growable: false);
    if (ratios.length <= 1) {
      return const AdaptiveCanvasPlan(
        kind: AdaptiveLayoutKind.single,
        slots: [CanvasSlot(0, 0, 1, 1)],
      );
    }

    final candidates = ratios.length == 2 ? _twoUp() : _threeUp();
    return candidates.reduce(
      (best, next) =>
          _unusedAreaCost(ratios, next.slots) <
              _unusedAreaCost(ratios, best.slots)
          ? next
          : best,
    );
  }

  List<AdaptiveCanvasPlan> _twoUp() {
    final halfGap = gap / 2;
    return [
      AdaptiveCanvasPlan(
        kind: AdaptiveLayoutKind.splitVertical,
        slots: [
          CanvasSlot(0, 0, .5 - halfGap, 1),
          CanvasSlot(.5 + halfGap, 0, .5 - halfGap, 1),
        ],
      ),
      AdaptiveCanvasPlan(
        kind: AdaptiveLayoutKind.splitHorizontal,
        slots: [
          CanvasSlot(0, 0, 1, .5 - halfGap),
          CanvasSlot(0, .5 + halfGap, 1, .5 - halfGap),
        ],
      ),
    ];
  }

  List<AdaptiveCanvasPlan> _threeUp() {
    const heroShare = .62;
    const topShare = .58;
    final halfGap = gap / 2;
    return [
      AdaptiveCanvasPlan(
        kind: AdaptiveLayoutKind.heroLeft,
        slots: [
          CanvasSlot(0, 0, heroShare - halfGap, 1),
          CanvasSlot(
            heroShare + halfGap,
            0,
            1 - heroShare - halfGap,
            .5 - halfGap,
          ),
          CanvasSlot(
            heroShare + halfGap,
            .5 + halfGap,
            1 - heroShare - halfGap,
            .5 - halfGap,
          ),
        ],
      ),
      AdaptiveCanvasPlan(
        kind: AdaptiveLayoutKind.heroTop,
        slots: [
          CanvasSlot(0, 0, 1, topShare - halfGap),
          CanvasSlot(
            0,
            topShare + halfGap,
            .5 - halfGap,
            1 - topShare - halfGap,
          ),
          CanvasSlot(
            .5 + halfGap,
            topShare + halfGap,
            .5 - halfGap,
            1 - topShare - halfGap,
          ),
        ],
      ),
    ];
  }

  double _unusedAreaCost(List<double> sources, List<CanvasSlot> slots) {
    var cost = 0.0;
    for (var index = 0; index < sources.length; index++) {
      final source = sources[index];
      final target = aspectRatio * slots[index].aspectRatio;
      final occupied = math.min(source / target, target / source).clamp(0, 1);
      final area = slots[index].width * slots[index].height;
      cost += (1 - occupied) * math.sqrt(area);
    }
    return cost;
  }
}

extension MotionTemplateCopy on MotionTemplate {
  String title(bool zh) => switch (this) {
    MotionTemplate.travelDiary => zh ? '旅行日记' : 'Travel Diary',
    MotionTemplate.sunsetStory => zh ? '落日故事' : 'Sunset Story',
    MotionTemplate.filmStrip => zh ? '胶片叙事' : 'Film Strip',
    MotionTemplate.minimalMemory => zh ? '极简记忆' : 'Minimal Memory',
  };

  String subtitle(bool zh) => switch (this) {
    MotionTemplate.travelDiary =>
      zh ? '景色 · 人物 · 细节' : 'Place · People · Detail',
    MotionTemplate.sunsetStory =>
      zh ? '光线 · 环境 · 剪影' : 'Light · Place · Silhouette',
    MotionTemplate.filmStrip => zh ? '颗粒 · 暖调 · 连续' : 'Grain · Warmth · Rhythm',
    MotionTemplate.minimalMemory =>
      zh ? '留白 · 呼吸 · 克制' : 'Space · Breath · Restraint',
  };
}
