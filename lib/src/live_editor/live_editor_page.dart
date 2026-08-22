import 'dart:ui';

import 'package:flutter/material.dart';

import '../models/live_rules.dart';
import '../models/media_asset.dart';
import '../screens/video_picker_screen.dart';
import '../services/media_engine.dart';
import '../theme.dart';
import '../widgets/studio_notice.dart';
import '../localization/app_localizations.dart';
import '../features/motion_canvas/controllers/motion_canvas_controller.dart';
import '../features/motion_canvas/export/export_service.dart';
import '../features/motion_canvas/models/motion_clip.dart';
import '../features/motion_canvas/widgets/studio_canvas.dart';
import 'components/advanced_settings.dart';
import 'components/cover_selector.dart';
import 'components/generate_button.dart';
import 'components/fullscreen_preview.dart';
import 'components/live_preview_card.dart';
import 'components/timeline_editor.dart';
import 'formatters.dart';
import 'live_editor_scope.dart';
import 'models/live_editor_state.dart';

/// AfterFrame Studio.
///
/// Studio edits an ordered source list and never asks the user to pick a mode:
/// one source keeps its original framing, two or three are arranged by Adaptive
/// Canvas. Everything after that — cover, timeline, settings, export — is one
/// shared rule.
class LiveEditorPage extends StatefulWidget {
  const LiveEditorPage({super.key, required this.assets, required this.engine})
    : assert(assets.length > 0);

  final List<MediaAsset> assets;
  final MediaEngine engine;

  @override
  State<LiveEditorPage> createState() => _LiveEditorPageState();
}

class _LiveEditorPageState extends State<LiveEditorPage> {
  late final LiveEditorState _editorState;
  late final MotionCanvasController _canvas;
  late final MotionCanvasExportService _canvasExportService;
  final StudioNoticeController _notice = StudioNoticeController();
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _editorState = LiveEditorState(assets: widget.assets);
    _canvas = MotionCanvasController(assets: widget.assets)
      ..addListener(_refreshCanvas);
    _canvasExportService = MotionCanvasExportService(widget.engine);
    if (_editorState.composition.isCanvas) {
      // The canvas rail owns its own thumbnails; the single-frame timeline strip
      // is only extracted if the user later drops back to one source.
      _editorState.finishLoading();
      _loadCanvasThumbnails();
    } else {
      _loadFrames();
    }
  }

  @override
  void dispose() {
    _loadGeneration++;
    _notice.dispose();
    _editorState.dispose();
    _canvas.removeListener(_refreshCanvas);
    _canvas.dispose();
    super.dispose();
  }

  void _refreshCanvas() {
    if (mounted) setState(() {});
  }

  Future<void> _loadCanvasThumbnails() async {
    for (final clip in _canvas.clips) {
      try {
        final path = await widget.engine.extractFrame(
          clip.asset.uri,
          clip.resolvedCoverMs,
        );
        if (!mounted) return;
        _canvas.setThumbnail(clip.id, path);
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

  /// Removing a source is the only way to change a work's shape. Dropping to a
  /// single clip returns Studio to the single-frame rule without any mode
  /// switch, and the change stays undoable.
  void _removeCanvasClip(int index) {
    if (_canvas.isExporting) return;
    final removed = _canvas.removeClip(index);
    if (removed == null) return;
    _adoptCanvasSources();
    final l10n = context.l10n;
    _notice.show(
      message: l10n.text('sourceRemoved'),
      actionLabel: l10n.text('undo'),
      onAction: () => _restoreCanvasClip(index, removed),
    );
  }

  void _restoreCanvasClip(int index, MotionClip clip) {
    _canvas.restoreClip(index, clip);
    _adoptCanvasSources();
  }

  void _adoptCanvasSources() {
    _editorState.adoptSettings(
      audio: _canvas.audioEnabled,
      loop: _canvas.loopEnabled,
      enhancement: _canvas.enhancementEnabled,
      speed: _canvas.playbackSpeed,
    );
    if (_editorState.syncSources(_canvas.assets)) _loadFrames();
  }

  Future<void> _addSources() async {
    if (_canvas.isExporting || _editorState.isProcessing) return;
    _notice.dismiss();
    final selected = await Navigator.of(context).push<List<MediaAsset>>(
      MaterialPageRoute(
        builder: (_) => VideoPickerScreen(
          engine: widget.engine,
          initialSelection: _canvas.assets,
        ),
      ),
    );
    if (!mounted || selected == null || selected.isEmpty) return;
    _canvas.replaceSources(selected);
    _adoptCanvasSources();
    if (_canvas.clips.length >= 2) {
      await _loadCanvasThumbnails();
    }
  }

  Future<void> _generate() async {
    if (_editorState.isLoading ||
        _editorState.isProcessing ||
        _canvas.isExporting) {
      return;
    }
    if (_editorState.composition.isCanvas) {
      await _generateCanvas();
      return;
    }
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

  Future<void> _generateCanvas() async {
    _editorState.setGenerateStatus(GenerateStatus.processing);
    await _canvas.prepareExport();
    try {
      final result = await _canvasExportService.export(_canvas);
      if (!mounted) return;
      _editorState.setGenerateStatus(GenerateStatus.success);
      await _showSuccess(result.published);
      if (!mounted) return;
      Navigator.pop(context, toLiveExport(result.published, result.coverPath));
    } catch (_) {
      if (mounted) {
        _editorState.setGenerateStatus(GenerateStatus.failed);
        _message('errorExport');
      }
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
        builder: (context, setSheetState) {
          final clip = _canvas.clips[index];
          return SafeArea(
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
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Icon(
                          Icons.crop_free_rounded,
                          size: 16,
                          color: AfterFrameColors.lime,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          context.l10n.text('smartCropHint'),
                          style: const TextStyle(
                            color: AfterFrameColors.muted,
                            fontSize: 12,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
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
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        context.l10n.text('clipCover'),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        formatEditorTime(clip.resolvedCoverMs),
                        style: const TextStyle(
                          color: AfterFrameColors.lime,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    min: range.start,
                    max: range.end,
                    value: clip.resolvedCoverMs.toDouble().clamp(
                      range.start,
                      range.end,
                    ),
                    onChanged: (value) {
                      _canvas.setClipCover(index, value.round());
                      setSheetState(() {});
                    },
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => _canvas.resetSmartCrop(index),
                      icon: const Icon(Icons.center_focus_strong_rounded),
                      label: Text(context.l10n.text('resetSmartCrop')),
                    ),
                  ),
                  const SizedBox(height: 4),
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
          );
        },
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
    child: StudioNoticeHost(
      controller: _notice,
      child: _LiveEditorScaffold(
        onGenerate: _generate,
        canvas: _canvas,
        onEditCanvasClip: _editCanvasClip,
        onRemoveCanvasClip: _removeCanvasClip,
        onAddSources: _addSources,
      ),
    ),
  );
}

class _LiveEditorScaffold extends StatefulWidget {
  const _LiveEditorScaffold({
    required this.onGenerate,
    required this.canvas,
    required this.onEditCanvasClip,
    required this.onRemoveCanvasClip,
    required this.onAddSources,
  });

  final VoidCallback onGenerate;
  final MotionCanvasController canvas;
  final ValueChanged<int> onEditCanvasClip;
  final ValueChanged<int> onRemoveCanvasClip;
  final VoidCallback onAddSources;

  @override
  State<_LiveEditorScaffold> createState() => _LiveEditorScaffoldState();
}

class _LiveEditorScaffoldState extends State<_LiveEditorScaffold> {
  bool _previewRouteOpen = false;

  Future<void> _openFullscreen(LiveComposition composition) async {
    if (_previewRouteOpen) return;
    final editorState = LiveEditorScope.of(context);
    setState(() => _previewRouteOpen = true);
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    try {
      await FullscreenPreview.show(
        context,
        label: composition.isCanvas ? 'Live Collage' : 'Live Frame',
        exitHint: context.l10n.text('fullscreenExitHint'),
        child: composition.isCanvas
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
    final composition = state.composition;
    final isCanvas = composition.isCanvas;
    final exporting = isCanvas ? widget.canvas.isExporting : state.isProcessing;
    final canGenerate = !state.isLoading && !exporting;
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
            // The shape is stated instead of chosen, so the header carries it.
            Text(
              isCanvas
                  ? l10n.text('canvasSummary', {
                      'count': widget.canvas.clips.length,
                    })
                  : l10n.text('singleFrameSummary'),
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
            child: exporting
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AfterFrameColors.lime,
                    ),
                  )
                : Text(
                    l10n.text('export'),
                    style: TextStyle(
                      color: AfterFrameColors.lime.withValues(
                        alpha: canGenerate ? 1 : .38,
                      ),
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
                          child: isCanvas
                              ? StudioCanvasPreview(
                                  key: const ValueKey('canvasPreview'),
                                  controller: widget.canvas,
                                  active:
                                      !_previewRouteOpen &&
                                      !widget.canvas.isExporting,
                                  onFullscreen: () =>
                                      _openFullscreen(composition),
                                )
                              : LivePreviewCard(
                                  key: const ValueKey('singlePreview'),
                                  active:
                                      !_previewRouteOpen && !state.isProcessing,
                                  onFullscreen: () =>
                                      _openFullscreen(composition),
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
                                26,
                                18,
                                30,
                              ),
                              child: Column(
                                children: [
                                  _Reveal(
                                    child: AnimatedSize(
                                      duration:
                                          MediaQuery.disableAnimationsOf(
                                            context,
                                          )
                                          ? Duration.zero
                                          : const Duration(milliseconds: 280),
                                      curve: Curves.easeOutCubic,
                                      alignment: Alignment.topCenter,
                                      child: AnimatedSwitcher(
                                        duration:
                                            MediaQuery.disableAnimationsOf(
                                              context,
                                            )
                                            ? Duration.zero
                                            : const Duration(milliseconds: 280),
                                        child: isCanvas
                                            ? StudioCanvasTools(
                                                key: const ValueKey(
                                                  'canvasTools',
                                                ),
                                                controller: widget.canvas,
                                                onEditClip:
                                                    widget.onEditCanvasClip,
                                                onRemoveClip:
                                                    widget.onRemoveCanvasClip,
                                                onAddClip: widget.onAddSources,
                                              )
                                            : _SingleFrameTools(
                                                key: const ValueKey(
                                                  'frameTools',
                                                ),
                                                remaining:
                                                    maxLiveSources -
                                                    widget.canvas.clips.length,
                                                onAddSources:
                                                    widget.onAddSources,
                                              ),
                                      ),
                                    ),
                                  ),
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

/// Single-frame tools follow the same order as the canvas ones: cover, then
/// timeline, then shared settings.
class _SingleFrameTools extends StatelessWidget {
  const _SingleFrameTools({
    super.key,
    required this.remaining,
    required this.onAddSources,
  });

  final int remaining;
  final VoidCallback onAddSources;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const CoverSelector(),
      const SizedBox(height: 30),
      const TimelineEditor(),
      if (remaining > 0) ...[
        const SizedBox(height: 18),
        _AddSourcesInvite(remaining: remaining, onAdd: onAddSources),
      ],
      const SizedBox(height: 24),
      const AdvancedSettings(),
    ],
  );
}

class _AddSourcesInvite extends StatelessWidget {
  const _AddSourcesInvite({required this.remaining, required this.onAdd});

  final int remaining;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Material(
      color: AfterFrameColors.lime.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onAdd,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AfterFrameColors.lime.withValues(alpha: .16),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.add_rounded,
                  color: AfterFrameColors.lime,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.text('addSource'),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      l10n.text('addSourceHint', {'count': remaining}),
                      style: const TextStyle(
                        fontSize: 11,
                        height: 1.3,
                        color: AfterFrameColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_rounded,
                size: 18,
                color: AfterFrameColors.lime,
              ),
            ],
          ),
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
