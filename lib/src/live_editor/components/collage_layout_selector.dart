import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/media_asset.dart';
import '../../theme.dart';
import '../live_editor_scope.dart';

class CollageLayoutSelector extends StatefulWidget {
  const CollageLayoutSelector({super.key});

  @override
  State<CollageLayoutSelector> createState() => _CollageLayoutSelectorState();
}

class _CollageLayoutSelectorState extends State<CollageLayoutSelector> {
  int selected = 0;

  @override
  Widget build(BuildContext context) {
    final frames = LiveEditorScope.of(context).frames;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('选择拼图布局', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Row(
          children: [
            for (int i = 0; i < 3; i++) ...[
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => selected = i),
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    height: 68,
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: AfterFrameColors.panelSoft,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: selected == i
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
        const Text(
          '当前 MVP 使用同一视频的不同时间切片；多视频同步将在下一阶段开放。',
          style: TextStyle(fontSize: 10, color: AfterFrameColors.muted),
        ),
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
