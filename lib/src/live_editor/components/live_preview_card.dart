import 'dart:io';

import 'package:flutter/material.dart';

import '../../theme.dart';
import '../live_editor_scope.dart';

class LivePreviewCard extends StatelessWidget {
  const LivePreviewCard({super.key});

  @override
  Widget build(BuildContext context) {
    final state = LiveEditorScope.of(context);
    final cover = state.selectedCover;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: cover == null
              ? const Icon(Icons.broken_image_outlined, size: 80)
              : ClipRRect(
                  key: ValueKey(cover.path),
                  borderRadius: BorderRadius.circular(24),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      AspectRatio(
                        aspectRatio: state.asset.aspectRatio
                            .clamp(.58, 1.2)
                            .toDouble(),
                        child: Image.file(File(cover.path), fit: BoxFit.cover),
                      ),
                      Positioned(
                        left: 13,
                        top: 13,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: const Row(
                            children: [
                              Icon(
                                Icons.motion_photos_on,
                                size: 15,
                                color: AfterFrameColors.lime,
                              ),
                              SizedBox(width: 5),
                              Text(
                                'LIVE',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: .48),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white24),
                        ),
                        child: const Icon(Icons.play_arrow_rounded, size: 32),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
