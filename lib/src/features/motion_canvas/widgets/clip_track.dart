import 'dart:io';

import 'package:flutter/material.dart';

import '../../../theme.dart';
import '../controllers/motion_canvas_controller.dart';

class MotionClipTrack extends StatelessWidget {
  const MotionClipTrack({
    super.key,
    required this.controller,
    required this.onEdit,
  });

  final MotionCanvasController controller;
  final ValueChanged<int> onEdit;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 96,
    child: ReorderableListView.builder(
      scrollDirection: Axis.horizontal,
      buildDefaultDragHandles: false,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      itemCount: controller.clips.length,
      onReorder: controller.reorder,
      proxyDecorator: (child, _, animation) => ScaleTransition(
        scale: Tween(begin: 1.0, end: 1.04).animate(animation),
        child: Material(color: Colors.transparent, child: child),
      ),
      itemBuilder: (context, index) {
        final clip = controller.clips[index];
        final selected = index == controller.activeClipIndex;
        return ReorderableDelayedDragStartListener(
          key: ValueKey(clip.id),
          index: index,
          child: GestureDetector(
            onTap: () {
              controller.selectClip(index);
              onEdit(index);
            },
            child: AnimatedContainer(
              duration: MotionCanvasController.motion,
              curve: MotionCanvasController.curve,
              width: 112,
              margin: const EdgeInsets.only(right: 10),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: selected
                    ? Colors.white12
                    : Colors.white.withValues(alpha: .045),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: selected
                      ? AfterFrameColors.lime.withValues(alpha: .65)
                      : Colors.white10,
                ),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: SizedBox(
                      width: 48,
                      height: 78,
                      child: clip.thumbnailPath == null
                          ? const ColoredBox(color: Color(0xFF292A2F))
                          : Image.file(
                              File(clip.thumbnailPath!),
                              fit: BoxFit.cover,
                            ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '0${index + 1}',
                          style: const TextStyle(
                            fontSize: 10,
                            color: AfterFrameColors.muted,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '${(clip.durationMs / 1000).toStringAsFixed(1)}s',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 9),
                        const Icon(
                          Icons.drag_indicator_rounded,
                          size: 16,
                          color: Colors.white38,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}
