import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../localization/app_localizations.dart';
import '../live_editor_scope.dart';
import '../models/live_editor_state.dart';

class CreationModeSelector extends StatelessWidget {
  const CreationModeSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final state = LiveEditorScope.of(context);
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeading(
          eyebrow: l10n.text('createMode'),
          title: l10n.text('shapeMemory'),
        ),
        const SizedBox(height: 13),
        Row(
          children: [
            Expanded(
              child: _ModeCard(
                icon: Icons.motion_photos_on_rounded,
                title: l10n.text('liveFrame'),
                description: l10n.text('liveFrameDescription'),
                selected: state.mode == CreationMode.liveFrame,
                onTap: () => state.setMode(CreationMode.liveFrame),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ModeCard(
                icon: Icons.auto_awesome_mosaic_rounded,
                title: l10n.text('motionCollage'),
                description: l10n.text('collageDescription'),
                selected: state.mode == CreationMode.motionCollage,
                enabled: state.canUseCollage,
                onTap: () => state.setMode(CreationMode.motionCollage),
              ),
            ),
          ],
        ),
        if (!state.canUseCollage) ...[
          const SizedBox(height: 9),
          Text(
            l10n.text('collageNeedsSources'),
            style: const TextStyle(color: AfterFrameColors.muted, fontSize: 10),
          ),
        ],
      ],
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.eyebrow, required this.title});

  final String eyebrow;
  final String title;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        eyebrow,
        style: const TextStyle(
          color: AfterFrameColors.lime,
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.6,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        title,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      ),
    ],
  );
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool selected;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(22),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          height: 116,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected
                ? AfterFrameColors.lime.withValues(alpha: .1)
                : AfterFrameColors.glassSoft.withValues(
                    alpha: enabled ? 1 : .45,
                  ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: selected
                  ? AfterFrameColors.lime
                  : AfterFrameColors.glassBorder,
              width: selected ? 1.5 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AfterFrameColors.lime.withValues(alpha: .08),
                      blurRadius: 18,
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    icon,
                    size: 21,
                    color: selected
                        ? AfterFrameColors.lime
                        : Colors.white.withValues(alpha: enabled ? .7 : .28),
                  ),
                  const Spacer(),
                  AnimatedOpacity(
                    opacity: selected ? 1 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: const Icon(
                      Icons.check_circle_rounded,
                      size: 17,
                      color: AfterFrameColors.lime,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 9,
                  height: 1.25,
                  color: AfterFrameColors.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
