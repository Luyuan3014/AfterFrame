import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/media_asset.dart';
import '../../services/media_engine.dart';
import '../../theme.dart';
import '../live_editor_scope.dart';

class SourceSelector extends StatelessWidget {
  const SourceSelector({
    super.key,
    required this.assets,
    required this.engine,
    required this.onSelected,
  });

  final List<MediaAsset> assets;
  final MediaEngine engine;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final selectedIndex = LiveEditorScope.of(context).activeAssetIndex;
    return SizedBox(
      height: 54,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: assets.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, index) {
          final selected = index == selectedIndex;
          return InkWell(
            onTap: () => onSelected(index),
            borderRadius: BorderRadius.circular(12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 76,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: AfterFrameColors.panelSoft,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected ? AfterFrameColors.lime : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: FutureBuilder<String>(
                      future: engine.videoThumbnail(assets[index].uri),
                      builder: (_, snapshot) =>
                          snapshot.hasData && snapshot.data!.isNotEmpty
                          ? Image.file(File(snapshot.data!), fit: BoxFit.cover)
                          : const ColoredBox(color: Colors.white10),
                    ),
                  ),
                  Positioned(
                    left: 4,
                    top: 4,
                    child: CircleAvatar(
                      radius: 9,
                      backgroundColor: selected
                          ? AfterFrameColors.lime
                          : Colors.black54,
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          color: selected ? Colors.black : Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
