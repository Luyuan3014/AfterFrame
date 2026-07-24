import 'dart:io';

import 'package:flutter/material.dart';

import '../../theme.dart';
import '../formatters.dart';
import '../live_editor_scope.dart';

class TimelineEditor extends StatelessWidget {
  const TimelineEditor({super.key});

  @override
  Widget build(BuildContext context) {
    final state = LiveEditorScope.of(context);
    return Column(
      children: [
        SizedBox(
          height: 38,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
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
                ColoredBox(color: Colors.black.withValues(alpha: .2)),
              ],
            ),
          ),
        ),
        Row(
          children: [
            Text(
              formatEditorTime(state.startTime),
              style: const TextStyle(
                color: AfterFrameColors.muted,
                fontSize: 11,
              ),
            ),
            Expanded(
              child: RangeSlider(
                min: 0,
                max: state.duration
                    .toDouble()
                    .clamp(1, double.infinity)
                    .toDouble(),
                values: RangeValues(
                  state.startTime.toDouble(),
                  state.endTime.toDouble(),
                ),
                onChanged: (value) =>
                    state.setTimeline(value.start.round(), value.end.round()),
              ),
            ),
            Text(
              formatEditorTime(state.endTime),
              style: const TextStyle(
                color: AfterFrameColors.muted,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
