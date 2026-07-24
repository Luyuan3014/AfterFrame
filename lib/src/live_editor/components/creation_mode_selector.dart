import 'package:flutter/material.dart';

import '../../theme.dart';
import '../live_editor_scope.dart';
import '../models/live_editor_state.dart';

class CreationModeSelector extends StatelessWidget {
  const CreationModeSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final state = LiveEditorScope.of(context);
    return Row(
      children: [
        Expanded(
          child: _ModeSegment(
            label: 'Live 单帧',
            selected: state.mode == CreationMode.liveFrame,
            onTap: () => state.setMode(CreationMode.liveFrame),
          ),
        ),
        Expanded(
          child: _ModeSegment(
            label: 'Live 拼图',
            selected: state.mode == CreationMode.motionCollage,
            onTap: () => state.setMode(CreationMode.motionCollage),
          ),
        ),
      ],
    );
  }
}

class _ModeSegment extends StatelessWidget {
  const _ModeSegment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: selected ? AfterFrameColors.panelSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: selected ? Colors.white : AfterFrameColors.muted,
        ),
      ),
    ),
  );
}
