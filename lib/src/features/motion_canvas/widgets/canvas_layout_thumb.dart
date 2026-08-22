import 'dart:io';

import 'package:flutter/material.dart';

import '../../../models/media_asset.dart';
import '../../../services/media_engine.dart';
import '../../../theme.dart';
import '../models/motion_canvas_layout.dart';
import '../models/motion_clip.dart';

/// A true-to-output miniature of the Adaptive Canvas plan.
///
/// It runs the same planner Studio uses, so the picker can show exactly how the
/// chosen sources will be arranged before anyone commits to the editor.
class CanvasLayoutThumb extends StatelessWidget {
  const CanvasLayoutThumb({
    super.key,
    required this.assets,
    required this.engine,
    this.height = 74,
  });

  final List<MediaAsset> assets;
  final MediaEngine engine;
  final double height;

  static const _layout = MotionCanvasLayout();
  static const _gap = 1.4;

  @override
  Widget build(BuildContext context) {
    if (assets.isEmpty) return SizedBox(height: height);
    final plan = _layout.planFor(
      assets.map((asset) => canvasGeometryFor(asset)).toList(growable: false),
    );
    final width = height * plan.canvas.aspectRatio;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFF0D0E11),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: AfterFrameColors.glassBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          for (var index = 0; index < plan.frames.length; index++)
            AnimatedPositioned(
              key: ValueKey(assets[index].uri),
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 340),
              curve: Curves.easeOutCubic,
              left:
                  plan.frames[index].rect.x / plan.canvas.width * width + _gap,
              top:
                  plan.frames[index].rect.y / plan.canvas.height * height +
                  _gap,
              width:
                  plan.frames[index].rect.width / plan.canvas.width * width -
                  _gap * 2,
              height:
                  plan.frames[index].rect.height / plan.canvas.height * height -
                  _gap * 2,
              child: _ThumbFrame(
                asset: assets[index],
                engine: engine,
                order: index + 1,
                showOrder: plan.frames.length > 1,
              ),
            ),
        ],
      ),
    );
  }
}

class _ThumbFrame extends StatelessWidget {
  const _ThumbFrame({
    required this.asset,
    required this.engine,
    required this.order,
    required this.showOrder,
  });

  final MediaAsset asset;
  final MediaEngine engine;
  final int order;
  final bool showOrder;

  @override
  Widget build(BuildContext context) {
    final focus = smartCropFocusFor(asset);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      builder: (_, value, child) => Opacity(opacity: value, child: child),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: ColoredBox(
          color: const Color(0xFF1E2025),
          child: Stack(
            fit: StackFit.expand,
            children: [
              FutureBuilder<String>(
                future: engine.videoThumbnail(asset.thumbnailUri),
                builder: (_, snapshot) {
                  final path = snapshot.data;
                  if (path == null || path.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return Image.file(
                    File(path),
                    // Cells keep the source aspect ratio, so contain matches
                    // the full-framing collage plan (no silent cover crop).
                    fit: BoxFit.contain,
                    alignment: Alignment(focus.x * 2 - 1, focus.y * 2 - 1),
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  );
                },
              ),
              if (showOrder)
                Align(
                  alignment: Alignment.topLeft,
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: .5),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 3,
                          vertical: 1,
                        ),
                        child: Text(
                          '$order',
                          style: const TextStyle(
                            fontSize: 7,
                            height: 1.2,
                            fontWeight: FontWeight.w900,
                            color: AfterFrameColors.lime,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
