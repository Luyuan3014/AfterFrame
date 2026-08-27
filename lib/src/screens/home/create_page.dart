import 'package:flutter/material.dart';

import '../../localization/app_localizations.dart';
import '../../models/media_asset.dart';
import '../../theme.dart';
import '../video_picker_screen.dart';
import 'create_memory_card.dart';
import 'creation_flow.dart';
import 'memory_glow_background.dart';
import 'recent_creations.dart';

class CreatePage extends StatelessWidget {
  const CreatePage({
    super.key,
    required this.onCreate,
    required this.loading,
    required this.exports,
    required this.onOpenWorks,
    required this.onPreview,
    this.active = true,
  });

  final ValueChanged<VideoLibraryFilter> onCreate;
  final bool loading;
  final List<LiveExport> exports;
  final VoidCallback onOpenWorks;
  final ValueChanged<LiveExport> onPreview;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Stack(
      children: [
        Positioned.fill(child: MemoryGlowBackground(active: active)),
        SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AfterFrameSpace.s20,
              AfterFrameSpace.s20,
              AfterFrameSpace.s20,
              AfterFrameSpace.s40,
            ),
            children: [
              const _BrandMark(),
              const SizedBox(height: AfterFrameSpace.s40),
              Text(
                l10n.text('heroTitle'),
                style: Theme.of(context).textTheme.displaySmall,
              ),
              const SizedBox(height: AfterFrameSpace.s16),
              Text(
                l10n.text('heroSubtitle'),
                style: const TextStyle(
                  color: AfterFrameColors.textSecondary,
                  fontSize: 15,
                  height: 1.55,
                ),
              ),
              const SizedBox(height: AfterFrameSpace.s32),
              CreateMemoryCard(
                onTap: () => onCreate(VideoLibraryFilter.all),
                loading: loading,
              ),
              const SizedBox(height: AfterFrameSpace.s40),
              CreationFlow(onStep: onCreate),
              if (exports.isNotEmpty) ...[
                const SizedBox(height: AfterFrameSpace.s40),
                RecentCreations(
                  exports: exports,
                  onViewAll: onOpenWorks,
                  onOpen: onPreview,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AfterFrameRadius.md),
          child: Image.asset(
            'assets/branding/logo.png',
            width: 42,
            height: 42,
            fit: BoxFit.cover,
          ),
        ),
        const SizedBox(width: AfterFrameSpace.s12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'AFTERFRAME',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 2.4,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              l10n.text('brandCn'),
              style: const TextStyle(
                fontSize: 11,
                color: AfterFrameColors.textTertiary,
                letterSpacing: 4,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
