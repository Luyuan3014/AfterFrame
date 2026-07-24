import 'dart:ui';

import 'package:flutter/material.dart';

import '../models/media_asset.dart';
import '../services/media_engine.dart';
import '../theme.dart';
import '../localization/app_localizations.dart';
import 'components/advanced_settings.dart';
import 'components/collage_layout_selector.dart';
import 'components/cover_selector.dart';
import 'components/creation_mode_selector.dart';
import 'components/generate_button.dart';
import 'components/live_preview_card.dart';
import 'components/source_selector.dart';
import 'components/timeline_editor.dart';
import 'live_editor_scope.dart';
import 'models/live_editor_state.dart';

class LiveEditorPage extends StatefulWidget {
  const LiveEditorPage({
    super.key,
    required this.assets,
    required this.engine,
    this.initialMode = 0,
  }) : assert(assets.length > 0);

  final List<MediaAsset> assets;
  final MediaEngine engine;
  final int initialMode;

  @override
  State<LiveEditorPage> createState() => _LiveEditorPageState();
}

class _LiveEditorPageState extends State<LiveEditorPage> {
  late final LiveEditorState _editorState;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _editorState = LiveEditorState(
      asset: widget.assets.first,
      mode: CreationMode.fromIndex(widget.initialMode),
    );
    _loadFrames();
  }

  @override
  void dispose() {
    _loadGeneration++;
    _editorState.dispose();
    super.dispose();
  }

  Future<void> _loadFrames() async {
    final generation = ++_loadGeneration;
    final asset = _editorState.asset;
    try {
      final frames = await widget.engine.extractTimeline(
        asset.uri,
        asset.durationMs,
        count: 9,
      );
      if (mounted && generation == _loadGeneration) {
        _editorState.setFrames(frames);
      }
    } catch (error) {
      if (mounted && generation == _loadGeneration) {
        _message('errorFrame');
      }
    } finally {
      if (mounted && generation == _loadGeneration) {
        _editorState.finishLoading();
      }
    }
  }

  void _selectSource(int index) {
    if (index == _editorState.activeAssetIndex || _editorState.isProcessing) {
      return;
    }
    _editorState.replaceAsset(index, widget.assets[index]);
    _loadFrames();
  }

  Future<void> _generate() async {
    if (_editorState.selectedCover == null || _editorState.isProcessing) return;
    _editorState.setGenerateStatus(GenerateStatus.processing);
    try {
      // Keep the phase-one native processing contract and invocation order.
      final preciseCover = await widget.engine.extractFrame(
        _editorState.videoPath,
        _editorState.coverFrame,
      );
      final published = await widget.engine.exportLive(
        asset: _editorState.asset,
        startMs: _editorState.startTime,
        endMs: _editorState.endTime,
        coverMs: _editorState.coverFrame,
        coverPath: preciseCover,
        keepAudio: _editorState.audioEnabled,
        loop: _editorState.loopEnabled,
      );
      if (!mounted) return;
      _editorState.setGenerateStatus(GenerateStatus.success);
      await _showSuccess(published);
      if (mounted) {
        Navigator.pop(
          context,
          LiveExport(
            path: published.liveUri,
            createdAt: DateTime.now(),
            coverPath: preciseCover,
            galleryUri: published.galleryUri,
            displayName: published.displayName,
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        _editorState.setGenerateStatus(GenerateStatus.failed);
        _message('errorExport');
      }
    }
  }

  Future<void> _showSuccess(
    PublishedLive published,
  ) => showModalBottomSheet<void>(
    context: context,
    backgroundColor: AfterFrameColors.panel,
    showDragHandle: true,
    builder: (sheetContext) {
      final l10n = sheetContext.l10n;
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircleAvatar(
              radius: 28,
              backgroundColor: AfterFrameColors.lime,
              child: Icon(Icons.check_rounded, color: Colors.black, size: 32),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.text('momentSaved'),
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 7),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
              decoration: BoxDecoration(
                color: AfterFrameColors.lime.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: AfterFrameColors.lime.withValues(alpha: .3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.photo_library_outlined,
                    size: 16,
                    color: AfterFrameColors.lime,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    l10n.text('savedToAlbum'),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.text('done')),
              ),
            ),
          ],
        ),
      );
    },
  );

  void _message(String key) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(context.l10n.text(key)),
      behavior: SnackBarBehavior.floating,
    ),
  );

  @override
  Widget build(BuildContext context) => LiveEditorScope(
    state: _editorState,
    child: _LiveEditorScaffold(
      assets: widget.assets,
      engine: widget.engine,
      onSourceSelected: _selectSource,
      onGenerate: _generate,
    ),
  );
}

class _LiveEditorScaffold extends StatelessWidget {
  const _LiveEditorScaffold({
    required this.assets,
    required this.engine,
    required this.onSourceSelected,
    required this.onGenerate,
  });

  final List<MediaAsset> assets;
  final MediaEngine engine;
  final ValueChanged<int> onSourceSelected;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    final state = LiveEditorScope.of(context);
    final l10n = context.l10n;
    final canGenerate = state.selectedCover != null && !state.isProcessing;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            const Text(
              'AfterFrame Studio',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: -.2,
              ),
            ),
            Text(
              l10n.text('studioSubtitle'),
              style: const TextStyle(
                fontSize: 9,
                color: AfterFrameColors.muted,
                letterSpacing: .35,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: canGenerate ? onGenerate : null,
            child: Text(
              l10n.text('export'),
              style: const TextStyle(
                color: AfterFrameColors.lime,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
      body: state.isLoading
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: AfterFrameColors.lime),
                  const SizedBox(height: 16),
                  Text(
                    l10n.text('readingVideo'),
                    style: const TextStyle(color: AfterFrameColors.muted),
                  ),
                ],
              ),
            )
          : TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 480),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) => Opacity(
                opacity: value,
                child: Transform.translate(
                  offset: Offset(0, 12 * (1 - value)),
                  child: child,
                ),
              ),
              child: Stack(
                children: [
                  const Positioned(
                    left: -90,
                    right: -90,
                    top: -130,
                    height: 390,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          colors: [Color(0x172CFF79), Colors.transparent],
                        ),
                      ),
                    ),
                  ),
                  CustomScrollView(
                    physics: const BouncingScrollPhysics(),
                    slivers: [
                      const SliverToBoxAdapter(child: LivePreviewCard()),
                      SliverToBoxAdapter(
                        child: ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(34),
                          ),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                            child: Container(
                              decoration: const BoxDecoration(
                                color: AfterFrameColors.glass,
                                borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(34),
                                ),
                                border: Border(
                                  top: BorderSide(
                                    color: AfterFrameColors.glassBorder,
                                  ),
                                ),
                              ),
                              padding: const EdgeInsets.fromLTRB(
                                18,
                                24,
                                18,
                                30,
                              ),
                              child: Column(
                                children: [
                                  if (assets.length > 1) ...[
                                    _Reveal(
                                      child: SourceSelector(
                                        assets: assets,
                                        engine: engine,
                                        onSelected: onSourceSelected,
                                      ),
                                    ),
                                    const SizedBox(height: 22),
                                  ],
                                  const _Reveal(child: CreationModeSelector()),
                                  const SizedBox(height: 28),
                                  _Reveal(
                                    child: AnimatedSwitcher(
                                      duration: const Duration(
                                        milliseconds: 280,
                                      ),
                                      child:
                                          state.mode == CreationMode.liveFrame
                                          ? const CoverSelector(
                                              key: ValueKey('cover'),
                                            )
                                          : const CollageLayoutSelector(
                                              key: ValueKey('collage'),
                                            ),
                                    ),
                                  ),
                                  const SizedBox(height: 30),
                                  const _Reveal(child: TimelineEditor()),
                                  const SizedBox(height: 24),
                                  const _Reveal(child: AdvancedSettings()),
                                  const SizedBox(height: 20),
                                  _Reveal(
                                    child: GenerateButton(
                                      onPressed: canGenerate
                                          ? onGenerate
                                          : null,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}

class _Reveal extends StatelessWidget {
  const _Reveal({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: const Duration(milliseconds: 520),
    curve: Curves.easeOutCubic,
    builder: (_, value, child) => Opacity(
      opacity: value,
      child: Transform.translate(
        offset: Offset(0, 16 * (1 - value)),
        child: child,
      ),
    ),
    child: child,
  );
}
