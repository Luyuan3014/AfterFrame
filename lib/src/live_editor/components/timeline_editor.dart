import 'dart:io';

import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../localization/app_localizations.dart';
import '../formatters.dart';
import '../live_editor_scope.dart';

class TimelineEditor extends StatelessWidget {
  const TimelineEditor({super.key});

  @override
  Widget build(BuildContext context) {
    final state = LiveEditorScope.of(context);
    final l10n = context.l10n;
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
                    l10n.text('momentTimeline'),
                    style: const TextStyle(
                      color: AfterFrameColors.lime,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.6,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.text('findMoment'),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            _BestMomentPill(label: l10n.text('bestMoment')),
          ],
        ),
        const SizedBox(height: 13),
        Row(
          children: [
            Expanded(
              child: _Metric(
                label: l10n.text('currentTime'),
                value: formatEditorTime(state.currentPosition),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _Metric(
                label: l10n.text('liveLength'),
                value: formatEditorTime(state.liveLength),
              ),
            ),
          ],
        ),
        const SizedBox(height: 11),
        SizedBox(
          height: 70,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Row(
                  children: [
                    for (final frame in state.frames)
                      Expanded(
                        child: Image.file(File(frame.path), fit: BoxFit.cover),
                      ),
                  ],
                ),
                ColoredBox(color: Colors.black.withValues(alpha: .26)),
                _MomentMarker(
                  ratio: state.duration <= 0
                      ? .5
                      : state.bestMomentTime / state.duration,
                  color: Colors.white,
                  icon: Icons.star_rounded,
                  top: 6,
                ),
                _MomentMarker(
                  ratio: state.duration <= 0
                      ? .5
                      : state.coverFrame / state.duration,
                  color: AfterFrameColors.lime,
                  icon: Icons.circle,
                  top: 45,
                ),
              ],
            ),
          ),
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: AfterFrameColors.lime.withValues(alpha: .72),
            inactiveTrackColor: Colors.white12,
            trackHeight: 2,
            rangeThumbShape: const RoundRangeSliderThumbShape(
              enabledThumbRadius: 8,
            ),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 17),
            thumbColor: AfterFrameColors.lime,
            overlayColor: AfterFrameColors.lime.withValues(alpha: .12),
          ),
          child: RangeSlider(
            min: 0,
            max: state.duration.toDouble().clamp(1, double.infinity).toDouble(),
            values: RangeValues(
              state.startTime.toDouble(),
              state.endTime.toDouble(),
            ),
            onChanged: (value) =>
                state.setTimeline(value.start.round(), value.end.round()),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              formatEditorTime(state.startTime),
              style: const TextStyle(
                color: AfterFrameColors.muted,
                fontSize: 10,
              ),
            ),
            Text(
              l10n.text('liveRange'),
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 8,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
              ),
            ),
            Text(
              formatEditorTime(state.endTime),
              style: const TextStyle(
                color: AfterFrameColors.muted,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: .18),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AfterFrameColors.glassBorder),
    ),
    child: Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 8,
            color: AfterFrameColors.muted,
            fontWeight: FontWeight.w700,
            letterSpacing: .7,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    ),
  );
}

class _BestMomentPill extends StatelessWidget {
  const _BestMomentPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      color: AfterFrameColors.lime.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AfterFrameColors.lime.withValues(alpha: .32)),
    ),
    child: Row(
      children: [
        const Icon(Icons.star_rounded, size: 13, color: AfterFrameColors.lime),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );
}

class _MomentMarker extends StatelessWidget {
  const _MomentMarker({
    required this.ratio,
    required this.color,
    required this.icon,
    required this.top,
  });

  final double ratio;
  final Color color;
  final IconData icon;
  final double top;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment(ratio.clamp(0, 1) * 2 - 1, 0),
    child: Padding(
      padding: EdgeInsets.only(top: top),
      child: Icon(
        icon,
        size: 13,
        color: color,
        shadows: const [Shadow(color: Colors.black, blurRadius: 5)],
      ),
    ),
  );
}
