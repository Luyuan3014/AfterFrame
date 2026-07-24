import 'dart:io';

import 'package:flutter/material.dart';

import '../../theme.dart';
import '../formatters.dart';
import '../live_editor_scope.dart';

class CoverSelector extends StatelessWidget {
  const CoverSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final state = LiveEditorScope.of(context);
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('选择封面帧', style: TextStyle(fontWeight: FontWeight.w700)),
            Text(
              formatEditorTime(state.coverFrame),
              style: const TextStyle(
                color: AfterFrameColors.lime,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 58,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(
              children: [
                Row(
                  children: [
                    for (final frame in state.frames)
                      Expanded(
                        child: Image.file(
                          File(frame.path),
                          height: 58,
                          fit: BoxFit.cover,
                        ),
                      ),
                  ],
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
              ],
            ),
          ),
        ),
      ],
    );
  }
}
