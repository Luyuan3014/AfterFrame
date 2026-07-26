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
}

/// Chooses a full-bleed arrangement with the least destructive cover crop.
/// Every plan fills the portrait 9:16 output; preview and Media3 export share
/// these exact normalized cells.
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
          _cropCost(ratios, next.slots) < _cropCost(ratios, best.slots)
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

  double _cropCost(List<double> sources, List<CanvasSlot> slots) {
    var cost = 0.0;
    for (var index = 0; index < sources.length; index++) {
      final source = sources[index];
      final target = aspectRatio * slots[index].aspectRatio;
      final area = slots[index].width * slots[index].height;
      final retained = source < target ? source / target : target / source;
      cost += (1 - retained.clamp(0, 1)) * area;
    }
    return cost;
  }
}
