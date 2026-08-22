import 'dart:io';

import 'package:flutter/material.dart';

import '../../../localization/app_localizations.dart';
import '../../../theme.dart';
import '../controllers/motion_canvas_controller.dart';

class MotionClipTrack extends StatelessWidget {
  const MotionClipTrack({
    super.key,
    required this.controller,
    required this.onEdit,
    required this.onRemove,
    this.onAdd,
  });

  final MotionCanvasController controller;
  final ValueChanged<int> onEdit;
  final ValueChanged<int> onRemove;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 96,
    child: Row(
      children: [
        Expanded(
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
                        Stack(
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
                                        errorBuilder: (_, _, _) =>
                                            const ColoredBox(
                                              color: Color(0xFF292A2F),
                                            ),
                                      ),
                              ),
                            ),
                            if (clip.asset.isMotionPhoto)
                              Positioned(
                                left: 4,
                                top: 4,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AfterFrameColors.lime,
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: Text(
                                    context.l10n.text('liveBadge'),
                                    style: const TextStyle(
                                      color: AfterFrameColors.ink,
                                      fontSize: 7,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: .4,
                                    ),
                                  ),
                                ),
                              ),
                          ],
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
                              const SizedBox(height: 7),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.drag_indicator_rounded,
                                    size: 16,
                                    color: Colors.white38,
                                  ),
                                  if (controller.canRemoveClip)
                                    _RemoveClipButton(
                                      onPressed: () => onRemove(index),
                                    ),
                                ],
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
        ),
        if (controller.canAddClip && onAdd != null)
          Padding(
            padding: const EdgeInsets.only(right: 18),
            child: _AddClipButton(onPressed: onAdd!),
          ),
      ],
    ),
  );
}

/// Removing a source is how the user changes the work's shape: drop to one clip
/// and Studio returns to the single-frame rule.
class _RemoveClipButton extends StatelessWidget {
  const _RemoveClipButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: context.l10n.text('removeSource'),
    child: InkResponse(
      onTap: onPressed,
      radius: 18,
      containedInkWell: true,
      customBorder: const CircleBorder(),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Container(
          width: 17,
          height: 17,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: .38),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white24),
          ),
          child: const Icon(
            Icons.close_rounded,
            size: 11,
            color: Colors.white70,
          ),
        ),
      ),
    ),
  );
}

class _AddClipButton extends StatelessWidget {
  const _AddClipButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: context.l10n.text('addSource'),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            width: 72,
            height: 88,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AfterFrameColors.lime.withValues(alpha: .45),
              ),
              color: AfterFrameColors.lime.withValues(alpha: .08),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AfterFrameColors.lime.withValues(alpha: .18),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.add_rounded,
                    size: 18,
                    color: AfterFrameColors.lime,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  context.l10n.text('addSource'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: AfterFrameColors.lime,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
