import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/media_asset.dart';
import '../../theme.dart';
import '../../localization/app_localizations.dart';
import '../live_editor_scope.dart';
import '../models/live_editor_state.dart';

class CollageLayoutSelector extends StatelessWidget {
  const CollageLayoutSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final state = LiveEditorScope.of(context);
    final frames = state.frames;
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.text('chooseLayout'),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (int i = 0; i < 3; i++) ...[
              Expanded(
                child: InkWell(
                  onTap: () => state.setCollageLayout(CollageLayout.values[i]),
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    height: 68,
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: AfterFrameColors.panelSoft,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: state.collageLayout.index == i
                            ? AfterFrameColors.lime
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: _layout(i, frames),
                  ),
                ),
              ),
              if (i < 2) const SizedBox(width: 9),
            ],
          ],
        ),
        const SizedBox(height: 9),
        Text(
          l10n.text('collageMvp'),
          style: const TextStyle(fontSize: 10, color: AfterFrameColors.muted),
        ),
        if (state.assets.length > 1) ...[
          const SizedBox(height: 14),
          Text(
            l10n.text('collageAudioSource'),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: List.generate(
              state.collageSourceCount,
              (index) => ChoiceChip(
                label: Text('${index + 1}'),
                selected: state.collageAudioSourceIndex == index,
                onSelected: (_) => state.setCollageAudioSource(index),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _layout(int index, List<FrameSample> frames) {
    if (index == 0) {
      return Row(
        children: [
          _tile(0, frames),
          const SizedBox(width: 3),
          _tile(1, frames),
        ],
      );
    }
    if (index == 1) {
      return Column(
        children: [
          _tile(1, frames),
          const SizedBox(height: 3),
          _tile(2, frames),
        ],
      );
    }
    return Row(
      children: [
        _tile(0, frames, flex: 2),
        const SizedBox(width: 3),
        Expanded(
          child: Column(
            children: [
              _tile(1, frames),
              const SizedBox(height: 3),
              _tile(2, frames),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tile(int index, List<FrameSample> frames, {int flex = 1}) {
    final child = frames.isEmpty
        ? Container(color: Colors.white10)
        : ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.file(
              File(frames[index.clamp(0, frames.length - 1)].path),
              fit: BoxFit.cover,
            ),
          );
    return Expanded(flex: flex, child: child);
  }
}
