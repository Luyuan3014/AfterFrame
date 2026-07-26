import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../localization/app_localizations.dart';
import '../../../theme.dart';
import '../controllers/motion_canvas_controller.dart';
import '../renderer/motion_canvas_renderer.dart';
import 'clip_track.dart';
import 'creative_tools.dart';

/// Motion Canvas presented with the same visual hierarchy as Live single-frame
/// editing. Rendering and export state remain owned by MotionCanvasController.
class StudioCanvasPreview extends StatelessWidget {
  const StudioCanvasPreview({super.key, required this.controller});

  final MotionCanvasController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Container(
        height: 310,
        decoration: BoxDecoration(
          color: const Color(0xFF111216),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: Colors.white10),
          boxShadow: const [
            BoxShadow(
              color: Colors.black54,
              blurRadius: 28,
              offset: Offset(0, 14),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [Color(0x243B4B22), Color(0xFF0D0E11)],
                  radius: 1.1,
                ),
              ),
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: AspectRatio(
                  aspectRatio: controller.layout.aspectRatio,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: MotionCanvasRenderer(controller: controller),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 16,
              top: 16,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    color: Colors.black.withValues(alpha: .45),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.auto_awesome_mosaic_rounded,
                          size: 13,
                          color: AfterFrameColors.lime,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          context.l10n
                              .text('collagePreviewBadge')
                              .toUpperCase(),
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 18,
              right: 18,
              bottom: 12,
              child: _CanvasTimeline(controller: controller),
            ),
          ],
        ),
      ),
    ),
  );
}

class StudioCanvasTools extends StatelessWidget {
  const StudioCanvasTools({
    super.key,
    required this.controller,
    required this.onEditClip,
  });

  final MotionCanvasController controller;
  final ValueChanged<int> onEditClip;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.text('collageMaterialTrack'),
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          context.l10n.text('collageTrackHint'),
          style: const TextStyle(fontSize: 10, color: AfterFrameColors.muted),
        ),
        const SizedBox(height: 12),
        MotionClipTrack(controller: controller, onEdit: onEditClip),
        const SizedBox(height: 8),
        CreativeToolDock(controller: controller),
      ],
    ),
  );
}

class _CanvasTimeline extends StatelessWidget {
  const _CanvasTimeline({required this.controller});

  final MotionCanvasController controller;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      IconButton.filledTonal(
        visualDensity: VisualDensity.compact,
        onPressed: controller.togglePlayback,
        icon: Icon(
          controller.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
        ),
      ),
      Expanded(
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
            activeTrackColor: AfterFrameColors.lime,
            inactiveTrackColor: Colors.white24,
            thumbColor: AfterFrameColors.lime,
          ),
          child: Slider(
            value: controller.positionMs.toDouble().clamp(
              0,
              controller.durationMs.toDouble(),
            ),
            max: controller.durationMs.toDouble(),
            onChanged: (value) => controller.setPosition(value.round()),
          ),
        ),
      ),
      Text(
        '${(controller.positionMs / 1000).toStringAsFixed(1)}s',
        style: const TextStyle(
          fontSize: 10,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    ],
  );
}
