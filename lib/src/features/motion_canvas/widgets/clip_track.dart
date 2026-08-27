import 'dart:io';

import 'package:flutter/material.dart';

import '../../../localization/app_localizations.dart';
import '../../../theme.dart';
import '../controllers/motion_canvas_controller.dart';
import '../models/motion_clip.dart';

class MotionClipTrack extends StatelessWidget {
  const MotionClipTrack({
    super.key,
    required this.controller,
    required this.onRemove,
    this.onAdd,
  });

  final MotionCanvasController controller;
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
            padding: EdgeInsets.zero,
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
                  onTap: () => controller.selectClip(index),
                  child: _ClipThumb(
                    clip: clip,
                    index: index,
                    selected: selected,
                    canRemove: controller.canRemoveClip,
                    onRemove: () => onRemove(index),
                  ),
                ),
              );
            },
          ),
        ),
        if (controller.canAddClip && onAdd != null)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: _AddClipButton(onPressed: onAdd!),
          ),
      ],
    ),
  );
}

class _ClipThumb extends StatelessWidget {
  const _ClipThumb({
    required this.clip,
    required this.index,
    required this.selected,
    required this.canRemove,
    required this.onRemove,
  });

  final MotionClip clip;
  final int index;
  final bool selected;
  final bool canRemove;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: MotionCanvasController.motion,
      curve: MotionCanvasController.curve,
      width: 72,
      margin: const EdgeInsets.only(right: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected
              ? AfterFrameColors.lime.withValues(alpha: .85)
              : Colors.white12,
          width: selected ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          clip.thumbnailPath == null
              ? const ColoredBox(color: Color(0xFF292A2F))
              : Image.file(
                  File(clip.thumbnailPath!),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      const ColoredBox(color: Color(0xFF292A2F)),
                ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.transparent, Color(0xB3000000)],
                begin: Alignment.center,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          Positioned(
            left: 6,
            top: 6,
            child: Container(
              width: 18,
              height: 18,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: AfterFrameColors.lime,
                shape: BoxShape.circle,
              ),
              child: Text(
                '${index + 1}',
                style: const TextStyle(
                  color: AfterFrameColors.ink,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          if (clip.asset.isMotionPhoto)
            Positioned(
              right: 5,
              top: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
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
          Positioned(
            left: 6,
            bottom: 6,
            child: Text(
              '${(clip.durationMs / 1000).toStringAsFixed(1)}s',
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
            ),
          ),
          if (canRemove)
            Positioned(
              right: 2,
              bottom: 2,
              child: _RemoveClipButton(onPressed: onRemove),
            ),
        ],
      ),
    );
  }
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
            width: 56,
            height: 96,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AfterFrameColors.lime.withValues(alpha: .45),
              ),
              color: AfterFrameColors.lime.withValues(alpha: .08),
            ),
            child: const Icon(
              Icons.add_rounded,
              size: 22,
              color: AfterFrameColors.lime,
            ),
          ),
        ),
      ),
    );
  }
}
