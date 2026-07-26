import 'dart:ui';

import 'package:flutter/material.dart';

import '../models/media_asset.dart';
import '../services/media_engine.dart';
import '../theme.dart';
import '../localization/app_localizations.dart';
import '../features/motion_canvas/controllers/motion_canvas_controller.dart';
import '../features/motion_canvas/export/export_service.dart';
import '../features/motion_canvas/widgets/studio_canvas.dart';
import 'components/advanced_settings.dart';
import 'components/cover_selector.dart';
import 'components/creation_mode_selector.dart';
import 'components/generate_button.dart';
import 'components/fullscreen_preview.dart';
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
  late final MotionCanvasController _canvas;
  late final MotionCanvasExportService _canvasExportService;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _editorState = LiveEditorState(
      asset: widget.assets.first,
      mode: CreationMode.fromIndex(
        widget.assets.length < 2 ? 0 : widget.initialMode,
      ),
      assets: widget.assets,
    );
    _canvas = MotionCanvasController(assets: widget.assets)
      ..addListener(_refreshCanvas);
    _canvasExportService = MotionCanvasExportService(widget.engine);
    _loadFrames();
    _loadCanvasThumbnails();
  }

  @override
  void dispose() {
    _loadGeneration++;
    _editorState.dispose();
    _canvas.removeListener(_refreshCanvas);
    _canvas.dispose();
    super.dispose();
  }

  void _refreshCanvas() {
    if (mounted) setState(() {});
  }

  Future<void> _loadCanvasThumbnails() async {
    for (var index = 0; index < _canvas.clips.length; index++) {
      final clip = _canvas.clips[index];
      try {
        final path = await widget.engine.extractFrame(
          clip.asset.uri,
          clip.trimStartMs + clip.durationMs ~/ 2,
        );
        if (!mounted) return;
        _canvas.setThumbnail(index, path);
      } catch (_) {
        // A failed rail thumbnail must not block the synchronized preview.
      }
    }
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
    if (_editorState.mode == CreationMode.motionCollage) {
      await _generateCollage();
      return;
    }
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
        playbackSpeed: _editorState.playbackSpeed,
        enhancementEnabled: _editorState.enhancementEnabled,
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
            coverPath: published.coverPath.isEmpty
                ? preciseCover
                : published.coverPath,
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

  Future<void> _generateCollage() async {
    if (_canvas.isExporting || !_editorState.canUseCollage) return;
    _canvas.setExporting(true);
    try {
      final result = await _canvasExportService.export(_canvas);
      if (!mounted) return;
      await _showSuccess(result.published);
      if (!mounted) return;
      Navigator.pop(context, toLiveExport(result.published, result.coverPath));
    } catch (_) {
      if (mounted) _message('errorExport');
    } finally {
      if (mounted) _canvas.setExporting(false);
    }
  }

  Future<void> _editCanvasClip(int index) async {
    final clip = _canvas.clips[index];
    var range = RangeValues(
      clip.trimStartMs.toDouble(),
      clip.trimEndMs.toDouble(),
    );
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AfterFrameColors.panel,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.text('editCollageClip', {'index': index + 1}),
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  context.l10n.text('editCollageClipHint'),
                  style: const TextStyle(color: AfterFrameColors.muted),
                ),
                const SizedBox(height: 18),
                RangeSlider(
                  values: range,
                  min: 0,
                  max: clip.asset.durationMs.toDouble().clamp(
                    500,
                    double.infinity,
                  ),
                  labels: RangeLabels(
                    '${(range.start / 1000).toStringAsFixed(1)}s',
                    '${(range.end / 1000).toStringAsFixed(1)}s',
                  ),
                  onChanged: (value) {
                    if (value.end - value.start < 500) return;
                    setSheetState(() => range = value);
                    _canvas.setTrim(
                      index,
                      value.start.round(),
                      value.end.round(),
                    );
                  },
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    child: Text(context.l10n.text('done')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showSuccess(
    PublishedLive published,
  ) => showModalBottomSheet<void>(
    context: context,
    backgroundColor: AfterFrameColors.panel,
    showDragHandle: true,
    builder: (sheetContext) {
      final l10n = sheetContext.l10n;
      final isMotionPhoto = published.format == 'motionPhoto';
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
              child: FilledButton.icon(
                onPressed: () async {
                  try {
                    await widget.engine.shareVideo(published);
                  } catch (_) {
                    if (mounted) _message('errorShare');
                  }
                },
                icon: const Icon(Icons.send_rounded),
                label: Text(l10n.text('shareToChat')),
              ),
            ),
            if (isMotionPhoto) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    try {
                      await widget.engine.shareMotionPhoto(published);
                    } catch (_) {
                      if (mounted) _message('errorShare');
                    }
                  },
                  icon: const Icon(Icons.motion_photos_on_outlined),
                  label: Text(l10n.text('shareMotionOriginal')),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              l10n.text('shareCompatibilityHint'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AfterFrameColors.muted,
                fontSize: 11,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: TextButton(
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
      canvas: _canvas,
      onEditCanvasClip: _editCanvasClip,
    ),
  );
}

class _LiveEditorScaffold extends StatefulWidget {
  const _LiveEditorScaffold({
    required this.assets,
    required this.engine,
    required this.onSourceSelected,
    required this.onGenerate,
    required this.canvas,
    required this.onEditCanvasClip,
  });

  final List<MediaAsset> assets;
  final MediaEngine engine;
  final ValueChanged<int> onSourceSelected;
  final VoidCallback onGenerate;
  final MotionCanvasController canvas;
  final ValueChanged<int> onEditCanvasClip;

  @override
  State<_LiveEditorScaffold> createState() => _LiveEditorScaffoldState();
}

class _LiveEditorScaffoldState extends State<_LiveEditorScaffold> {
  bool _previewRouteOpen = false;

  Future<void> _openFullscreen(bool collageMode) async {
    if (_previewRouteOpen) return;
    final editorState = LiveEditorScope.of(context);
    setState(() => _previewRouteOpen = true);
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    try {
      await FullscreenPreview.show(
        context,
        label: collageMode ? 'Live Collage' : 'Live Frame',
        exitHint: context.l10n.text('fullscreenExitHint'),
        child: collageMode
            ? StudioCanvasPreview(controller: widget.canvas, fullscreen: true)
            : LiveEditorScope(
                state: editorState,
                child: const LivePreviewCard(fullscreen: true),
              ),
      );
    } finally {
      if (mounted) setState(() => _previewRouteOpen = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = LiveEditorScope.of(context);
    final l10n = context.l10n;
    final collageMode = state.mode == CreationMode.motionCollage;
    final canGenerate = collageMode
        ? state.canUseCollage && !widget.canvas.isExporting
        : state.selectedCover != null && !state.isProcessing;
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
            onPressed: canGenerate ? widget.onGenerate : null,
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
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 480),
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
                      SliverToBoxAdapter(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 280),
                          child: collageMode
                              ? StudioCanvasPreview(
                                  key: const ValueKey('canvasPreview'),
                                  controller: widget.canvas,
                                  active: !_previewRouteOpen,
                                  onFullscreen: () => _openFullscreen(true),
                                )
                              : LivePreviewCard(
                                  key: const ValueKey('singlePreview'),
                                  active: !_previewRouteOpen,
                                  onFullscreen: () => _openFullscreen(false),
                                ),
                        ),
                      ),
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
                                  if (widget.assets.length > 1 &&
                                      !collageMode) ...[
                                    _Reveal(
                                      child: SourceSelector(
                                        assets: widget.assets,
                                        engine: widget.engine,
                                        onSelected: widget.onSourceSelected,
                                      ),
                                    ),
                                    const SizedBox(height: 22),
                                  ],
                                  const _Reveal(child: CreationModeSelector()),
                                  const SizedBox(height: 28),
                                  _Reveal(
                                    child: AnimatedSwitcher(
                                      duration:
                                          MediaQuery.disableAnimationsOf(
                                            context,
                                          )
                                          ? Duration.zero
                                          : const Duration(milliseconds: 280),
                                      child:
                                          state.mode == CreationMode.liveFrame
                                          ? const CoverSelector(
                                              key: ValueKey('cover'),
                                            )
                                          : StudioCanvasTools(
                                              key: const ValueKey(
                                                'canvasTools',
                                              ),
                                              controller: widget.canvas,
                                              onEditClip:
                                                  widget.onEditCanvasClip,
                                            ),
                                    ),
                                  ),
                                  if (!collageMode) ...[
                                    const SizedBox(height: 30),
                                    const _Reveal(child: TimelineEditor()),
                                    const SizedBox(height: 24),
                                    const _Reveal(child: AdvancedSettings()),
                                  ],
                                  const SizedBox(height: 20),
                                  _Reveal(
                                    child: GenerateButton(
                                      onPressed: canGenerate
                                          ? widget.onGenerate
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
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 520),
    curve: Curves.easeOutCubic,
    builder: (_, value, child) => Opacity(
      opacity: value,
      child: Transform.translate(
        offset: MediaQuery.disableAnimationsOf(context)
            ? Offset.zero
            : Offset(0, 16 * (1 - value)),
        child: child,
      ),
    ),
    child: child,
  );
}
