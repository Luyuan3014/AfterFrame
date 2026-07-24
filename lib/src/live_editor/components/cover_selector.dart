import 'dart:io';

import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../localization/app_localizations.dart';
import '../formatters.dart';
import '../live_editor_scope.dart';
import '../models/live_editor_state.dart';

class CoverSelector extends StatelessWidget {
  const CoverSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final state = LiveEditorScope.of(context);
    final l10n = context.l10n;
    final aiMode = state.coverSelectionMode == CoverSelectionMode.aiRecommended;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.text('coverMoment'),
                    style: const TextStyle(
                      color: AfterFrameColors.lime,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.6,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.text('chooseCover'),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              formatEditorTime(state.coverFrame),
              style: const TextStyle(
                color: AfterFrameColors.lime,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 13),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: .22),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AfterFrameColors.glassBorder),
          ),
          child: Row(
            children: [
              Expanded(
                child: _SelectionTab(
                  icon: Icons.auto_awesome_rounded,
                  label: l10n.text('aiRecommended'),
                  selected: aiMode,
                  onTap: () => state.setCoverSelectionMode(
                    CoverSelectionMode.aiRecommended,
                  ),
                ),
              ),
              Expanded(
                child: _SelectionTab(
                  icon: Icons.tune_rounded,
                  label: l10n.text('manualSelect'),
                  selected: !aiMode,
                  onTap: () =>
                      state.setCoverSelectionMode(CoverSelectionMode.manual),
                ),
              ),
            ],
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          child: aiMode
              ? Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      _InsightChip(
                        label: l10n.text('bestLight'),
                        icon: Icons.light_mode_outlined,
                        value: CoverInsight.bestLight,
                        selected:
                            state.selectedInsight == CoverInsight.bestLight,
                        onTap: state.applyCoverInsight,
                      ),
                      _InsightChip(
                        label: l10n.text('sharpest'),
                        icon: Icons.center_focus_strong_rounded,
                        value: CoverInsight.sharpest,
                        selected:
                            state.selectedInsight == CoverInsight.sharpest,
                        onTap: state.applyCoverInsight,
                      ),
                      _InsightChip(
                        label: l10n.text('bestComposition'),
                        icon: Icons.grid_3x3_rounded,
                        value: CoverInsight.bestComposition,
                        selected:
                            state.selectedInsight ==
                            CoverInsight.bestComposition,
                        onTap: state.applyCoverInsight,
                      ),
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 72,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              children: [
                Row(
                  children: [
                    for (final frame in state.frames)
                      Expanded(
                        child: Image.file(
                          File(frame.path),
                          height: 72,
                          fit: BoxFit.cover,
                        ),
                      ),
                  ],
                ),
                Positioned.fill(
                  child: ColoredBox(color: Colors.black.withValues(alpha: .1)),
                ),
                Positioned.fill(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 0,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 9,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 18,
                      ),
                      thumbColor: AfterFrameColors.lime,
                      overlayColor: AfterFrameColors.lime.withValues(
                        alpha: .14,
                      ),
                    ),
                    child: Slider(
                      min: 0,
                      max: state.duration
                          .toDouble()
                          .clamp(1, double.infinity)
                          .toDouble(),
                      value: state.coverFrame.toDouble(),
                      onChanged: (value) => state.setCoverFrame(value.round()),
                    ),
                  ),
                ),
                IgnorePointer(
                  child: Align(
                    alignment: Alignment(
                      state.duration <= 0
                          ? 0
                          : (state.coverFrame / state.duration) * 2 - 1,
                      0,
                    ),
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: AfterFrameColors.lime,
                        borderRadius: BorderRadius.circular(2),
                        boxShadow: const [
                          BoxShadow(
                            color: AfterFrameColors.lime,
                            blurRadius: 7,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SelectionTab extends StatelessWidget {
  const _SelectionTab({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(14),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      decoration: BoxDecoration(
        color: selected ? AfterFrameColors.glassSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 14,
            color: selected ? AfterFrameColors.lime : AfterFrameColors.muted,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : AfterFrameColors.muted,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _InsightChip extends StatelessWidget {
  const _InsightChip({
    required this.label,
    required this.icon,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final CoverInsight value;
  final bool selected;
  final ValueChanged<CoverInsight> onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => onTap(value),
    borderRadius: BorderRadius.circular(20),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: selected
            ? AfterFrameColors.lime.withValues(alpha: .12)
            : AfterFrameColors.glassSoft,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected
              ? AfterFrameColors.lime
              : AfterFrameColors.glassBorder,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 13,
            color: selected ? AfterFrameColors.lime : AfterFrameColors.muted,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : AfterFrameColors.muted,
            ),
          ),
        ],
      ),
    ),
  );
}
