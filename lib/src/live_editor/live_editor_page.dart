import 'package:flutter/material.dart';

import '../models/media_asset.dart';
import '../services/media_engine.dart';
import '../theme.dart';
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
        _message(error.toString());
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
      final path = await widget.engine.exportLive(
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
      await _showSuccess(path);
      if (mounted) {
        Navigator.pop(
          context,
          LiveExport(
            path: path,
            createdAt: DateTime.now(),
            coverPath: preciseCover,
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        _editorState.setGenerateStatus(GenerateStatus.failed);
        _message(error.toString());
      }
    }
  }

  Future<void> _showSuccess(String path) => showModalBottomSheet<void>(
    context: context,
    backgroundColor: AfterFrameColors.panel,
    showDragHandle: true,
    builder: (_) => Padding(
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
          const Text(
            '这一刻，留下了',
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 7),
          Text(
            path,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AfterFrameColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('完成'),
            ),
          ),
        ],
      ),
    ),
  );

  void _message(String value) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(value), behavior: SnackBarBehavior.floating),
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
    final canGenerate = state.selectedCover != null && !state.isProcessing;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Column(
          children: [
            const Text(
              '动态工作台',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            Text(
              assets.length > 1
                  ? '${state.activeAssetIndex + 1} / ${assets.length} · 按选择顺序'
                  : '选择最值得留下的一帧',
              style: const TextStyle(
                fontSize: 10,
                color: AfterFrameColors.muted,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: canGenerate ? onGenerate : null,
            child: const Text(
              '导出',
              style: TextStyle(
                color: AfterFrameColors.lime,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
      body: state.isLoading
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: AfterFrameColors.lime),
                  SizedBox(height: 16),
                  Text(
                    '正在读懂这段视频…',
                    style: TextStyle(color: AfterFrameColors.muted),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                const Expanded(child: LivePreviewCard()),
                Container(
                  decoration: const BoxDecoration(
                    color: AfterFrameColors.panel,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(30),
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(18, 17, 18, 22),
                  child: Column(
                    children: [
                      if (assets.length > 1) ...[
                        SourceSelector(
                          assets: assets,
                          engine: engine,
                          onSelected: onSourceSelected,
                        ),
                        const SizedBox(height: 14),
                      ],
                      const CreationModeSelector(),
                      const SizedBox(height: 18),
                      if (state.mode == CreationMode.liveFrame)
                        const CoverSelector()
                      else
                        const CollageLayoutSelector(),
                      const SizedBox(height: 8),
                      const AdvancedSettings(),
                      const TimelineEditor(),
                      GenerateButton(
                        onPressed: canGenerate ? onGenerate : null,
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
