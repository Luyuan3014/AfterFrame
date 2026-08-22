import 'dart:math' as math;

import '../../../models/live_rules.dart';

enum MotionExportFormat { motionPhoto, mp4 }

/// The editorial families considered by Adaptive Canvas. Same-aspect tiles
/// share one cell size; mixed-aspect tiles keep native pixels.
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

  double get aspectRatio => width / height;
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
/// source. Same-aspect tiles may keep a larger crop than the destination
/// frame; export then uniformly scales that window into the cell.
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

/// Content-first layout planner.
///
/// Frames keep each source's aspect ratio and prefer the full source window so
/// Studio never silently reframes footage. Canvas size is derived from the
/// arranged frames — never forced to 9:16. Only when the arrangement exceeds
/// [maxExportSide] does the planner uniformly shrink (same-aspect extract).
class MotionCanvasLayout {
  const MotionCanvasLayout({
    this.maxExportSide = 4320,
    this.cornerRadius = 22,
    // Fixed opaque gutter between panels. Media3's compositor alpha-blends
    // abutting video quads and picks secondary frames by nearest timestamp —
    // that makes a content seam shimmer. A static solid bar in this gutter
    // (painted after compose) is stable in both Studio and the exported Live.
    this.gapPixels = 2,
    this.seamOverlapPixels = 0,
  });

  /// Upper bound for either canvas side. Kept in sync with Media3RenderEngine.
  final int maxExportSide;
  final double cornerRadius;
  final int gapPixels;

  /// Kept for API stability; must stay 0 so panels never alpha-blend into each
  /// other. The export path fills [gapPixels] with an opaque bitmap overlay.
  final int seamOverlapPixels;

  AdaptiveCanvasPlan planFor(List<CanvasSourceGeometry> sources) {
    final safeSources = sources
        .take(maxLiveSources)
        .map(_sanitize)
        .toList(growable: true);
    if (safeSources.isEmpty) {
      safeSources.add(const CanvasSourceGeometry(width: 1080, height: 1920));
    }
    final candidates = _candidates(safeSources);
    AdaptiveCanvasPlan? best;
    var bestScore = double.infinity;
    for (final candidate in candidates) {
      final score = _score(candidate);
      if (score < bestScore) {
        best = candidate;
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

  List<AdaptiveCanvasPlan> _candidates(List<CanvasSourceGeometry> sources) {
    if (sources.length == 1) {
      return [_fitPlan(_materializeSingle(sources.first))];
    }
    final plans = <AdaptiveCanvasPlan>[
      _fitPlan(_materializeStack(sources, vertical: true)),
      _fitPlan(_materializeStack(sources, vertical: false)),
    ];
    if (sources.length == 3) {
      plans.add(_fitPlan(_materializeGrid(sources)));
    }
    return plans;
  }

  AdaptiveCanvasPlan _materializeSingle(CanvasSourceGeometry source) =>
      AdaptiveCanvasPlan(
        kind: AdaptiveLayoutKind.single,
        canvas: CanvasPixelSize(source.width, source.height),
        frames: [
          _frameFor(
            source: source,
            left: 0,
            top: 0,
            width: source.width,
            height: source.height,
          ),
        ],
      );

  /// Stack full sources. Same-aspect clips share one cell size (the smallest
  /// native frame) so a 1080p Live still and a 720p video of the same shot
  /// sit as equal panels instead of a hero tile plus pillarboxed leftover.
  /// Different aspect ratios keep native pixels and are centered on the
  /// shared axis — tiny gutters beat stretching.
  AdaptiveCanvasPlan _materializeStack(
    List<CanvasSourceGeometry> sources, {
    required bool vertical,
  }) {
    final stepGap = gapPixels - seamOverlapPixels;
    final n = sources.length;
    final frames = <CanvasFrame>[];

    if (vertical) {
      if (_sameAspectFamily(sources)) {
        final cellWidth = _even(
          sources.map((source) => source.width).reduce(math.min),
        );
        final cellHeight = _even(
          sources
              .map(
                (source) => (cellWidth * source.height / source.width).round(),
              )
              .reduce(math.min),
        );
        var y = 0;
        for (var index = 0; index < n; index++) {
          frames.add(
            _frameForFitted(
              source: sources[index],
              left: 0,
              top: y,
              width: cellWidth,
              height: cellHeight,
            ),
          );
          y += cellHeight + (index == n - 1 ? 0 : stepGap);
        }
        return AdaptiveCanvasPlan(
          kind: AdaptiveLayoutKind.verticalTimeFlow,
          canvas: CanvasPixelSize(cellWidth, y),
          frames: frames,
        );
      }
      final canvasWidth = _even(
        sources.map((source) => source.width).reduce(math.max),
      );
      var y = 0;
      for (var index = 0; index < n; index++) {
        final source = sources[index];
        final width = source.width <= canvasWidth
            ? _even(source.width)
            : canvasWidth;
        final height = source.width <= canvasWidth
            ? _even(source.height)
            : _even(
                math.min(
                  source.height,
                  (width * source.height / source.width).round(),
                ),
              );
        final left = _even(((canvasWidth - width) / 2).round());
        frames.add(
          _frameFor(
            source: source,
            left: left,
            top: y,
            width: width,
            height: height,
          ),
        );
        y += height + (index == n - 1 ? 0 : stepGap);
      }
      return AdaptiveCanvasPlan(
        kind: AdaptiveLayoutKind.verticalTimeFlow,
        canvas: CanvasPixelSize(canvasWidth, y),
        frames: frames,
      );
    }

    if (_sameAspectFamily(sources)) {
      final cellHeight = _even(
        sources.map((source) => source.height).reduce(math.min),
      );
      final cellWidth = _even(
        sources
            .map(
              (source) => (cellHeight * source.width / source.height).round(),
            )
            .reduce(math.min),
      );
      var x = 0;
      for (var index = 0; index < n; index++) {
        frames.add(
          _frameForFitted(
            source: sources[index],
            left: x,
            top: 0,
            width: cellWidth,
            height: cellHeight,
          ),
        );
        x += cellWidth + (index == n - 1 ? 0 : stepGap);
      }
      return AdaptiveCanvasPlan(
        kind: AdaptiveLayoutKind.horizontalTimeFlow,
        canvas: CanvasPixelSize(x, cellHeight),
        frames: frames,
      );
    }

    final canvasHeight = _even(
      sources.map((source) => source.height).reduce(math.max),
    );
    var x = 0;
    for (var index = 0; index < n; index++) {
      final source = sources[index];
      final height = source.height <= canvasHeight
          ? _even(source.height)
          : canvasHeight;
      final width = source.height <= canvasHeight
          ? _even(source.width)
          : _even(
              math.min(
                source.width,
                (height * source.width / source.height).round(),
              ),
            );
      final top = _even(((canvasHeight - height) / 2).round());
      frames.add(
        _frameFor(
          source: source,
          left: x,
          top: top,
          width: width,
          height: height,
        ),
      );
      x += width + (index == n - 1 ? 0 : stepGap);
    }
    return AdaptiveCanvasPlan(
      kind: AdaptiveLayoutKind.horizontalTimeFlow,
      canvas: CanvasPixelSize(x, canvasHeight),
      frames: frames,
    );
  }

  /// Two-over-one using native source pixels; empty strips are allowed when
  /// aspect ratios differ so framing stays intact.
  AdaptiveCanvasPlan _materializeGrid(List<CanvasSourceGeometry> sources) {
    assert(sources.length == 3);
    final stepGap = gapPixels - seamOverlapPixels;
    final a = sources[0];
    final b = sources[1];
    final c = sources[2];
    final topHeight = math.max(a.height, b.height);
    final pairGap = math.max(stepGap, 0);
    final topWidth = a.width + pairGap + b.width;
    final canvasWidth = math.max(topWidth, c.width);
    final bottomTop = topHeight + stepGap;

    return AdaptiveCanvasPlan(
      kind: AdaptiveLayoutKind.grid,
      canvas: CanvasPixelSize(_even(canvasWidth), bottomTop + c.height),
      frames: [
        _frameFor(
          source: a,
          left: _even(((canvasWidth - topWidth) / 2).round()),
          top: _even(((topHeight - a.height) / 2).round()),
          width: a.width,
          height: a.height,
        ),
        _frameFor(
          source: b,
          left: _even(
            ((canvasWidth - topWidth) / 2).round() + a.width + pairGap,
          ),
          top: _even(((topHeight - b.height) / 2).round()),
          width: b.width,
          height: b.height,
        ),
        _frameFor(
          source: c,
          left: _even(((canvasWidth - c.width) / 2).round()),
          top: bottomTop,
          width: c.width,
          height: c.height,
        ),
      ],
    );
  }

  /// Uniformly shrink a native-pixel plan so both sides stay within
  /// [maxExportSide], then re-stack so seam overlaps stay exact.
  AdaptiveCanvasPlan _fitPlan(AdaptiveCanvasPlan plan) {
    final longest = math.max(plan.canvas.width, plan.canvas.height);
    if (longest <= maxExportSide) return plan;

    final scale = maxExportSide / longest;
    final stepGap = gapPixels - seamOverlapPixels;
    final scaled =
        <({CanvasSourceGeometry source, int width, int height, int left})>[];
    for (final frame in plan.frames) {
      final source = CanvasSourceGeometry(
        width: frame.crop.sourceWidth,
        height: frame.crop.sourceHeight,
        focusX:
            (frame.crop.leftPixels + frame.crop.widthPixels / 2) /
            frame.crop.sourceWidth,
        focusY:
            (frame.crop.topPixels + frame.crop.heightPixels / 2) /
            frame.crop.sourceHeight,
      );
      final width = _even(
        math.max(2, math.min(source.width, (frame.rect.width * scale).floor())),
      );
      final height = _even(
        math.max(
          2,
          math.min(
            source.height,
            (width * frame.rect.height / frame.rect.width).round(),
          ),
        ),
      );
      final left = _even(math.max(0, (frame.rect.x * scale).round()));
      scaled.add((source: source, width: width, height: height, left: left));
    }

    final frames = <CanvasFrame>[];
    if (plan.kind == AdaptiveLayoutKind.horizontalTimeFlow) {
      final canvasHeight = scaled.map((item) => item.height).reduce(math.max);
      var x = 0;
      for (var index = 0; index < scaled.length; index++) {
        final item = scaled[index];
        final top = _even(((canvasHeight - item.height) / 2).round());
        frames.add(
          _frameFor(
            source: item.source,
            left: x,
            top: top,
            width: item.width,
            height: item.height,
          ),
        );
        x += item.width + (index == scaled.length - 1 ? 0 : stepGap);
      }
      return AdaptiveCanvasPlan(
        kind: plan.kind,
        canvas: CanvasPixelSize(x, _even(canvasHeight)),
        frames: frames,
      );
    }

    // verticalTimeFlow, grid, single, and other stacks: rebuild tops in order.
    final canvasWidth = _even(
      math.max(
        2,
        scaled.map((item) => item.left + item.width).reduce(math.max),
      ),
    );
    var y = 0;
    for (var index = 0; index < scaled.length; index++) {
      final item = scaled[index];
      final left = item.left
          .clamp(0, math.max(0, canvasWidth - item.width))
          .toInt();
      frames.add(
        _frameFor(
          source: item.source,
          left: left,
          top: y,
          width: item.width,
          height: item.height,
        ),
      );
      y += item.height + (index == scaled.length - 1 ? 0 : stepGap);
    }
    return AdaptiveCanvasPlan(
      kind: plan.kind,
      canvas: CanvasPixelSize(canvasWidth, y),
      frames: frames,
    );
  }

  CanvasFrame _frameFor({
    required CanvasSourceGeometry source,
    required int left,
    required int top,
    required int width,
    required int height,
  }) {
    final frameWidth = _even(width.clamp(2, source.width));
    final frameHeight = _even(height.clamp(2, source.height));
    final cropLeftPixels =
        ((source.focusX * source.width - frameWidth / 2).round())
            .clamp(0, math.max(0, source.width - frameWidth))
            .toInt();
    final cropTopPixels =
        ((source.focusY * source.height - frameHeight / 2).round())
            .clamp(0, math.max(0, source.height - frameHeight))
            .toInt();

    return CanvasFrame(
      rect: CanvasRect(
        left.toDouble(),
        top.toDouble(),
        frameWidth.toDouble(),
        frameHeight.toDouble(),
      ),
      crop: SmartCropWindow(
        leftPixels: cropLeftPixels,
        topPixels: cropTopPixels,
        widthPixels: frameWidth,
        heightPixels: frameHeight,
        sourceWidth: source.width,
        sourceHeight: source.height,
      ),
      retainedSourceFraction:
          (frameWidth * frameHeight) / (source.width * source.height),
    );
  }

  /// Places the largest same-aspect window of [source] into a cell that may
  /// be smaller than the source. Matching 16:9 clips therefore keep full
  /// framing and are uniformly scaled to the shared cell at export time.
  CanvasFrame _frameForFitted({
    required CanvasSourceGeometry source,
    required int left,
    required int top,
    required int width,
    required int height,
  }) {
    final frameWidth = _even(math.max(2, width));
    final frameHeight = _even(math.max(2, height));
    final frameAr = frameWidth / frameHeight;
    final sourceAr = source.width / source.height;
    late final int cropW;
    late final int cropH;
    if (sourceAr >= frameAr) {
      cropH = _even(math.max(2, source.height));
      cropW = _even(((cropH * frameAr).round()).clamp(2, source.width));
    } else {
      cropW = _even(math.max(2, source.width));
      cropH = _even(((cropW / frameAr).round()).clamp(2, source.height));
    }
    final cropLeftPixels = ((source.focusX * source.width - cropW / 2).round())
        .clamp(0, math.max(0, source.width - cropW))
        .toInt();
    final cropTopPixels = ((source.focusY * source.height - cropH / 2).round())
        .clamp(0, math.max(0, source.height - cropH))
        .toInt();
    return CanvasFrame(
      rect: CanvasRect(
        left.toDouble(),
        top.toDouble(),
        frameWidth.toDouble(),
        frameHeight.toDouble(),
      ),
      crop: SmartCropWindow(
        leftPixels: cropLeftPixels,
        topPixels: cropTopPixels,
        widthPixels: cropW,
        heightPixels: cropH,
        sourceWidth: source.width,
        sourceHeight: source.height,
      ),
      retainedSourceFraction: (cropW * cropH) / (source.width * source.height),
    );
  }

  bool _sameAspectFamily(List<CanvasSourceGeometry> sources) {
    if (sources.length < 2) return true;
    final ratios = sources.map((source) => source.aspectRatio);
    final minRatio = ratios.reduce(math.min);
    final maxRatio = ratios.reduce(math.max);
    if (minRatio <= 0) return false;
    return maxRatio / minRatio <= 1.12;
  }

  double _score(AdaptiveCanvasPlan plan) {
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
    final resolutionPenalty =
        1 - plan.canvas.width / math.max(1, maxExportSide);
    final coveredArea = plan.frames.fold<double>(
      0,
      (sum, frame) => sum + frame.rect.width * frame.rect.height,
    );
    final emptyCanvasPenalty = math.max(
      0,
      1 - coveredArea / (plan.canvas.width * plan.canvas.height),
    );
    // Prefer canvases that fill a phone Studio card. Extreme tall stacks
    // create the large side pillarboxes users hate on landscape pairs.
    final ar = plan.canvas.aspectRatio;
    final phoneFitPenalty = ar < .55
        ? (.55 - ar) * 1.8
        : ar > 2.0
        ? (ar - 2.0) * 1.2
        : 0.0;
    final kindBias = switch (plan.kind) {
      AdaptiveLayoutKind.grid => .01,
      AdaptiveLayoutKind.pinterest => .02,
      AdaptiveLayoutKind.filmStrip => .08,
      _ => 0.0,
    };
    return cropLoss * .78 +
        balance * .1 +
        resolutionPenalty * .05 +
        emptyCanvasPenalty * 2.2 +
        phoneFitPenalty +
        kindBias;
  }

  int _even(int value) => value.isEven ? value : value - 1;
}
