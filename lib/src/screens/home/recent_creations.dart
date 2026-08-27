import 'dart:io';

import 'package:flutter/material.dart';

import '../../localization/app_localizations.dart';
import '../../models/media_asset.dart';
import '../../theme.dart';

@visibleForTesting
String formatWorkRelativeTime(
  DateTime createdAt,
  AppLocalizations l10n, {
  DateTime? now,
}) {
  final diff = (now ?? DateTime.now()).difference(createdAt);
  if (diff.inMinutes < 1) return l10n.text('relativeJustNow');
  if (diff.inHours < 1) {
    return l10n.text('relativeMinutes', {'count': diff.inMinutes});
  }
  if (diff.inDays < 1) {
    return l10n.text('relativeHours', {'count': diff.inHours});
  }
  return l10n.text('relativeDays', {'count': diff.inDays});
}

class RecentCreations extends StatelessWidget {
  const RecentCreations({
    super.key,
    required this.exports,
    required this.onViewAll,
    required this.onOpen,
  });

  final List<LiveExport> exports;
  final VoidCallback onViewAll;
  final ValueChanged<LiveExport> onOpen;

  @override
  Widget build(BuildContext context) {
    if (exports.isEmpty) return const SizedBox.shrink();
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.text('recentCreations'),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.2,
                ),
              ),
            ),
            GestureDetector(
              key: const Key('view-all-creations'),
              onTap: onViewAll,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: AfterFrameSpace.s8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.text('viewAll'),
                      style: const TextStyle(
                        color: AfterFrameColors.textTertiary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Icon(
                      Icons.arrow_forward_rounded,
                      size: 14,
                      color: AfterFrameColors.textTertiary,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AfterFrameSpace.s12),
        SizedBox(
          height: 176,
          child: ListView.separated(
            key: const Key('recent-creations'),
            scrollDirection: Axis.horizontal,
            itemCount: exports.length.clamp(0, 12),
            separatorBuilder: (_, _) =>
                const SizedBox(width: AfterFrameSpace.s12),
            itemBuilder: (_, index) {
              final item = exports[index];
              return RecentCreationCard(
                export: item,
                onTap: () => onOpen(item),
              );
            },
          ),
        ),
      ],
    );
  }
}

class RecentCreationCard extends StatelessWidget {
  const RecentCreationCard({
    super.key,
    required this.export,
    required this.onTap,
  });

  final LiveExport export;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final typeLabel = l10n.text(
      export.isCollage ? 'workTypeCollage' : 'workTypeLive',
    );
    return Material(
      color: AfterFrameColors.elevated,
      borderRadius: BorderRadius.circular(AfterFrameRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 132,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.file(
                File(export.coverPath),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const ColoredBox(
                  color: AfterFrameColors.elevated,
                  child: Center(
                    child: Icon(
                      Icons.motion_photos_on_rounded,
                      color: AfterFrameColors.textTertiary,
                    ),
                  ),
                ),
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.transparent, Color(0xCC070708)],
                    begin: Alignment.center,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
              Positioned(
                left: AfterFrameSpace.s12,
                right: AfterFrameSpace.s12,
                bottom: AfterFrameSpace.s12,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      export.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          typeLabel,
                          style: const TextStyle(
                            color: AfterFrameColors.lime,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: .4,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          formatWorkRelativeTime(export.createdAt, l10n),
                          style: const TextStyle(
                            color: AfterFrameColors.textTertiary,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
