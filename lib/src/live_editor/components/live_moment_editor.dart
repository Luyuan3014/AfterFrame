import 'dart:io';

import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../localization/app_localizations.dart';
import '../formatters.dart';
import '../live_editor_scope.dart';
import '../models/live_editor_state.dart';

/// One filmstrip for both the still cover and the Live range.
///
/// Mainstream Live editors do not stack two identical strips. Suggestions jump
/// the cover pin; dragging the pin is manual; the range handles sit on the
/// same strip.
class LiveMomentEditor extends StatelessWidget {
  const LiveMomentEditor({super.key});

  @override
  Widget build(BuildContext context) {
    final state = LiveEditorScope.of(context);
    final l10n = context.l10n;
    final duration = state.duration
        .toDouble()
        .clamp(1, double.infinity)
        .toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.text('coverAndRange'),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
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
        const SizedBox(height: 12),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            _InsightChip(
              label: l10n.text('laterMoment'),
              icon: Icons.auto_awesome_rounded,
              value: CoverSuggestion.laterMoment,
              selected:
                  state.coverSelectionMode == CoverSelectionMode.suggested &&
                  state.selectedSuggestion == CoverSuggestion.laterMoment,
              onTap: state.applyCoverSuggestion,
            ),
            _InsightChip(
              label: l10n.text('middleMoment'),
              icon: Icons.center_focus_strong_rounded,
              value: CoverSuggestion.middleMoment,
              selected:
                  state.coverSelectionMode == CoverSelectionMode.suggested &&
                  state.selectedSuggestion == CoverSuggestion.middleMoment,
              onTap: state.applyCoverSuggestion,
            ),
            _InsightChip(
              label: l10n.text('earlierMoment'),
              icon: Icons.wb_twilight_rounded,
              value: CoverSuggestion.earlierMoment,
              selected:
                  state.coverSelectionMode == CoverSelectionMode.suggested &&
                  state.selectedSuggestion == CoverSuggestion.earlierMoment,
              onTap: state.applyCoverSuggestion,
            ),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          key: const Key('live-moment-strip'),
          height: 84,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              children: [
                Positioned.fill(child: _Filmstrip(state: state)),
                Positioned.fill(
                  child: ColoredBox(color: Colors.black.withValues(alpha: .08)),
                ),
                Positioned.fill(
                  child: _RangeDim(
                    start: state.startTime,
                    end: state.endTime,
                    duration: state.duration,
                  ),
                ),
                Positioned.fill(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 0,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 8,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 16,
                      ),
                      thumbColor: AfterFrameColors.lime,
                      overlayColor: AfterFrameColors.lime.withValues(
                        alpha: .14,
                      ),
                    ),
                    child: Slider(
                      min: 0,
                      max: duration.toDouble(),
                      value: state.coverFrame
                          .toDouble()
                          .clamp(0, duration)
                          .toDouble(),
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
                      margin: const EdgeInsets.symmetric(vertical: 10),
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
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: AfterFrameColors.lime.withValues(alpha: .78),
            inactiveTrackColor: Colors.white12,
            trackHeight: 3,
            rangeThumbShape: const RoundRangeSliderThumbShape(
              enabledThumbRadius: 8,
            ),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            thumbColor: AfterFrameColors.lime,
            overlayColor: AfterFrameColors.lime.withValues(alpha: .12),
          ),
          child: RangeSlider(
            min: 0,
            max: duration.toDouble(),
            values: RangeValues(
              state.startTime.toDouble().clamp(0, duration).toDouble(),
              state.endTime.toDouble().clamp(0, duration).toDouble(),
            ),
            onChanged: (value) =>
                state.setTimeline(value.start.round(), value.end.round()),
          ),
        ),
        Row(
          children: [
            Text(
              formatEditorTime(state.startTime),
              style: const TextStyle(
                color: AfterFrameColors.muted,
                fontSize: 10,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const Spacer(),
            Text(
              '${l10n.text('liveRange')}  ${formatEditorTime(state.liveLength)}',
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: .4,
              ),
            ),
            const Spacer(),
            Text(
              formatEditorTime(state.endTime),
              style: const TextStyle(
                color: AfterFrameColors.muted,
                fontSize: 10,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Filmstrip extends StatelessWidget {
  const _Filmstrip({required this.state});

  final LiveEditorState state;

  @override
  Widget build(BuildContext context) {
    if (state.frames.isEmpty) {
      return const ColoredBox(color: Color(0xFF202126));
    }
    return Row(
      children: [
        for (final frame in state.frames)
          Expanded(
            child: Image.file(
              File(frame.path),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) =>
                  const ColoredBox(color: Color(0xFF202126)),
            ),
          ),
      ],
    );
  }
}

class _RangeDim extends StatelessWidget {
  const _RangeDim({
    required this.start,
    required this.end,
    required this.duration,
  });

  final int start;
  final int end;
  final int duration;

  @override
  Widget build(BuildContext context) {
    if (duration <= 0) return const SizedBox.expand();
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final left = (start / duration) * width;
        final right = (end / duration) * width;
        return Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: left.clamp(0, width),
              child: const ColoredBox(color: Color(0x99000000)),
            ),
            Positioned(
              left: right.clamp(0, width),
              right: 0,
              top: 0,
              bottom: 0,
              child: const ColoredBox(color: Color(0x99000000)),
            ),
          ],
        );
      },
    );
  }
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
  final CoverSuggestion value;
  final bool selected;
  final ValueChanged<CoverSuggestion> onTap;

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
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : AfterFrameColors.muted,
            ),
          ),
        ],
      ),
    ),
  );
}
