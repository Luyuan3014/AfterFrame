import 'dart:math' as math;

enum MotionExportFormat { motionPhoto, mp4 }

/// The editorial families considered by Adaptive Canvas. The selected family
/// changes canvas frames only; source pixels are never resized per frame.
enum AdaptiveLayoutKind {
  single,
  verticalTimeFlow,
  horizontalTimeFlow,
  pinterest,
  grid,
  filmStrip,
}

class CanvasSourceGeometry {
  const CanvasSourceGeometry({
    required this.width,
    required this.height,
    this.focusX = .5,
    this.focusY = .5,
    this.subjectConfidence = 0,
  });

  final int width;
  final int height;
  final double focusX;
  final double focusY;
  final double subjectConfidence;
}

class CanvasPixelSize {
  const CanvasPixelSize(this.width, this.height);

  final int width;
  final int height;
  double get aspectRatio => width / height;
}

class CanvasRect {
  const CanvasRect(this.x, this.y, this.width, this.height);

  final double x;
  final double y;
  final double width;
  final double height;

  double get aspectRatio => width / height;

  List<double> normalized(CanvasPixelSize canvas) => [
    x / canvas.width,
    y / canvas.height,
    width / canvas.width,
    height / canvas.height,
  ];

  List<int> get pixelEncoded => [
    x.round(),
    y.round(),
    width.round(),
    height.round(),
  ];
}

/// A source-space crop window. Coordinates are normalized to the oriented
/// source. The crop's pixel dimensions always equal its destination frame.
class SmartCropWindow {
  const SmartCropWindow({
    required this.leftPixels,
    required this.topPixels,
    required this.widthPixels,
    required this.heightPixels,
    required this.sourceWidth,
    required this.sourceHeight,
  });

  final int leftPixels;
  final int topPixels;
  final int widthPixels;
  final int heightPixels;
  final int sourceWidth;
  final int sourceHeight;

  double get left => leftPixels / sourceWidth;
  double get top => topPixels / sourceHeight;
  double get width => widthPixels / sourceWidth;
  double get height => heightPixels / sourceHeight;

  List<double> get encoded => [left, top, width, height];
  List<int> get pixelEncoded => [
    leftPixels,
    topPixels,
    widthPixels,
    heightPixels,
  ];
}

class CanvasFrame {
  const CanvasFrame({
    required this.rect,
    required this.crop,
    required this.retainedSourceFraction,
  });

  final CanvasRect rect;
  final SmartCropWindow crop;
  final double retainedSourceFraction;
}

class AdaptiveCanvasPlan {
  const AdaptiveCanvasPlan({
    required this.kind,
    required this.canvas,
    required this.frames,
  });

  final AdaptiveLayoutKind kind;
  final CanvasPixelSize canvas;
  final List<CanvasFrame> frames;
}

class _NormalizedFrame {
  const _NormalizedFrame(this.x, this.y, this.width, this.height);

  final double x;
  final double y;
  final double width;
  final double height;
}

class _Candidate {
  const _Candidate(this.kind, this.frames, [this.aestheticPenalty = 0]);

  final AdaptiveLayoutKind kind;
  final List<_NormalizedFrame> frames;
  final double aestheticPenalty;
}

/// Canvas First layout planner.
///
/// It starts with the requested canvas ratio, chooses an editorial frame
/// arrangement, and reduces the *canvas* dimensions when a frame would exceed
/// a source. A frame then takes an equally-sized source crop. Consequently the
/// invariant is exact: one source pixel maps to one output-canvas pixel before
/// the completed canvas is scaled for an on-screen preview.
class MotionCanvasLayout {
  const MotionCanvasLayout({
    this.targetCanvasWidth = 1080,
    this.targetCanvasHeight = 1920,
    this.cornerRadius = 22,
    this.gapPixels = 4,
  });

  final int targetCanvasWidth;
  final int targetCanvasHeight;
  final double cornerRadius;
  final int gapPixels;

  double get aspectRatio => targetCanvasWidth / targetCanvasHeight;

  AdaptiveCanvasPlan planFor(List<CanvasSourceGeometry> sources) {
    final safeSources = sources.take(3).map(_sanitize).toList(growable: true);
    if (safeSources.isEmpty) {
      safeSources.add(const CanvasSourceGeometry(width: 1080, height: 1920));
    }
    final candidates = _candidates(safeSources.length);
    AdaptiveCanvasPlan? best;
    var bestScore = double.infinity;
    for (final candidate in candidates) {
      final plan = _materialize(candidate, safeSources);
      final score = _score(candidate, plan);
      if (score < bestScore) {
        best = plan;
        bestScore = score;
      }
    }
    return best!;
  }

  CanvasSourceGeometry _sanitize(CanvasSourceGeometry source) =>
      CanvasSourceGeometry(
        width: math.max(2, source.width),
        height: math.max(2, source.height),
        focusX: source.focusX.isFinite ? source.focusX.clamp(0, 1) : .5,
        focusY: source.focusY.isFinite ? source.focusY.clamp(0, 1) : .5,
        subjectConfidence: source.subjectConfidence.isFinite
            ? source.subjectConfidence.clamp(0, 1)
            : 0,
      );

  List<_Candidate> _candidates(int count) {
    if (count == 1) {
      return const [
        _Candidate(AdaptiveLayoutKind.single, [_NormalizedFrame(0, 0, 1, 1)]),
      ];
    }
    final gx = gapPixels / targetCanvasWidth;
    final gy = gapPixels / targetCanvasHeight;
    if (count == 2) {
      return [
        _Candidate(AdaptiveLayoutKind.verticalTimeFlow, [
          _NormalizedFrame(0, 0, 1, .5 - gy / 2),
          _NormalizedFrame(0, .5 + gy / 2, 1, .5 - gy / 2),
        ]),
        _Candidate(AdaptiveLayoutKind.horizontalTimeFlow, [
          _NormalizedFrame(0, 0, .5 - gx / 2, 1),
          _NormalizedFrame(.5 + gx / 2, 0, .5 - gx / 2, 1),
        ]),
      ];
    }
    return [
      _Candidate(AdaptiveLayoutKind.verticalTimeFlow, [
        _NormalizedFrame(0, 0, 1, 1 / 3 - gy * 2 / 3),
        _NormalizedFrame(0, 1 / 3 + gy / 3, 1, 1 / 3 - gy * 2 / 3),
        _NormalizedFrame(0, 2 / 3 + gy * 2 / 3, 1, 1 / 3 - gy * 2 / 3),
      ]),
      _Candidate(AdaptiveLayoutKind.horizontalTimeFlow, [
        _NormalizedFrame(0, 0, 1 / 3 - gx * 2 / 3, 1),
        _NormalizedFrame(1 / 3 + gx / 3, 0, 1 / 3 - gx * 2 / 3, 1),
        _NormalizedFrame(2 / 3 + gx * 2 / 3, 0, 1 / 3 - gx * 2 / 3, 1),
      ]),
      _Candidate(AdaptiveLayoutKind.pinterest, [
        _NormalizedFrame(0, 0, .62 - gx / 2, 1),
        _NormalizedFrame(.62 + gx / 2, 0, .38 - gx / 2, .5 - gy / 2),
        _NormalizedFrame(.62 + gx / 2, .5 + gy / 2, .38 - gx / 2, .5 - gy / 2),
      ], .012),
      _Candidate(AdaptiveLayoutKind.grid, [
        _NormalizedFrame(0, 0, .5 - gx / 2, .5 - gy / 2),
        _NormalizedFrame(.5 + gx / 2, 0, .5 - gx / 2, .5 - gy / 2),
        _NormalizedFrame(0, .5 + gy / 2, 1, .5 - gy / 2),
      ], .008),
    ];
  }

  AdaptiveCanvasPlan _materialize(
    _Candidate candidate,
    List<CanvasSourceGeometry> sources,
  ) {
    var canvasScale = 1.0;
    for (var index = 0; index < sources.length; index++) {
      final frame = candidate.frames[index];
      final source = sources[index];
      canvasScale = math.min(
        canvasScale,
        math.min(
          source.width / (targetCanvasWidth * frame.width),
          source.height / (targetCanvasHeight * frame.height),
        ),
      );
    }
    final canvas = CanvasPixelSize(
      _even(math.max(2, (targetCanvasWidth * canvasScale).floor())),
      _even(math.max(2, (targetCanvasHeight * canvasScale).floor())),
    );
    final frames = <CanvasFrame>[];
    for (var index = 0; index < sources.length; index++) {
      final normalized = candidate.frames[index];
      final source = sources[index];
      final left = normalized.x == 0
          ? 0
          : _even((normalized.x * canvas.width).round());
      final top = normalized.y == 0
          ? 0
          : _even((normalized.y * canvas.height).round());
      final width = _even(
        math.max(
          2,
          math.min(
            source.width,
            normalized.x + normalized.width >= .999999
                ? canvas.width - left
                : (normalized.width * canvas.width).floor(),
          ),
        ),
      );
      final height = _even(
        math.max(
          2,
          math.min(
            source.height,
            normalized.y + normalized.height >= .999999
                ? canvas.height - top
                : (normalized.height * canvas.height).floor(),
          ),
        ),
      );
      final cropLeftPixels =
          ((source.focusX * source.width - width / 2).round())
              .clamp(0, math.max(0, source.width - width))
              .toInt();
      final cropTopPixels =
          ((source.focusY * source.height - height / 2).round())
              .clamp(0, math.max(0, source.height - height))
              .toInt();
      frames.add(
        CanvasFrame(
          rect: CanvasRect(
            left.toDouble(),
            top.toDouble(),
            width.toDouble(),
            height.toDouble(),
          ),
          crop: SmartCropWindow(
            leftPixels: cropLeftPixels,
            topPixels: cropTopPixels,
            widthPixels: width,
            heightPixels: height,
            sourceWidth: source.width,
            sourceHeight: source.height,
          ),
          retainedSourceFraction:
              (width * height) / (source.width * source.height),
        ),
      );
    }
    return AdaptiveCanvasPlan(
      kind: candidate.kind,
      canvas: canvas,
      frames: frames,
    );
  }

  double _score(_Candidate candidate, AdaptiveCanvasPlan plan) {
    final cropLoss =
        plan.frames.fold<double>(
          0,
          (sum, frame) => sum + (1 - frame.retainedSourceFraction),
        ) /
        plan.frames.length;
    final retained = plan.frames
        .map((frame) => frame.retainedSourceFraction)
        .toList(growable: false);
    final balance = retained.reduce(math.max) - retained.reduce(math.min);
    final resolutionPenalty = 1 - plan.canvas.width / targetCanvasWidth;
    final coveredArea = plan.frames.fold<double>(
      0,
      (sum, frame) => sum + frame.rect.width * frame.rect.height,
    );
    final emptyCanvasPenalty =
        1 - coveredArea / (plan.canvas.width * plan.canvas.height);
    return cropLoss * .68 +
        balance * .16 +
        resolutionPenalty * .16 +
        emptyCanvasPenalty * 2 +
        candidate.aestheticPenalty;
  }

  int _even(int value) => value.isEven ? value : value - 1;
}
