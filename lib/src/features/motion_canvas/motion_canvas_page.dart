import 'package:flutter/material.dart';

import '../../localization/app_localizations.dart';
import '../../models/media_asset.dart';
import '../../services/media_engine.dart';
import '../../theme.dart';
import 'controllers/motion_canvas_controller.dart';
import 'export/export_service.dart';
import 'models/motion_canvas_layout.dart';
import 'renderer/motion_canvas_renderer.dart';
import 'widgets/clip_track.dart';
import 'widgets/creative_tools.dart';

class MotionCanvasPage extends StatefulWidget {
  const MotionCanvasPage({
    super.key,
    required this.assets,
    required this.engine,
  });

  final List<MediaAsset> assets;
  final MediaEngine engine;

  @override
  State<MotionCanvasPage> createState() => _MotionCanvasPageState();
}

class _MotionCanvasPageState extends State<MotionCanvasPage> {
  late final MotionCanvasController _canvas;
  late final MotionCanvasExportService _exportService;

  @override
  void initState() {
    super.initState();
    _canvas = MotionCanvasController(assets: widget.assets)
      ..addListener(_refresh);
    _exportService = MotionCanvasExportService(widget.engine);
    _loadThumbnails();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _loadThumbnails() async {
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
        // Video preview remains available when a rail thumbnail cannot decode.
      }
    }
  }

  Future<void> _export() async {
    if (_canvas.isExporting) return;
    _canvas.setExporting(true);
    try {
      final result = await _exportService.export(_canvas);
      if (!mounted) return;
      await _showExportSheet(result.published);
      if (!mounted) return;
      Navigator.pop(context, toLiveExport(result.published, result.coverPath));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.text('errorExport')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) _canvas.setExporting(false);
    }
  }

  Future<void> _editClip(int index) async {
    final zh = context.l10n.isChinese;
    final clip = _canvas.clips[index];
    var range = RangeValues(
      clip.trimStartMs.toDouble(),
      clip.trimEndMs.toDouble(),
    );
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF18191D),
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
                Row(
                  children: [
                    Text(
                      zh ? '编辑 Clip ${index + 1}' : 'Edit Clip ${index + 1}',
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${(range.start / 1000).toStringAsFixed(1)} – ${(range.end / 1000).toStringAsFixed(1)}s',
                      style: const TextStyle(
                        color: AfterFrameColors.muted,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  zh
                      ? '拖动两端，选择这段记忆参与画布的时间范围。'
                      : 'Drag both handles to choose this clip’s memory range.',
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
                    child: Text(zh ? '完成' : 'Done'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showExportSheet(
    PublishedLive published,
  ) => showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF18191D),
    showDragHandle: true,
    builder: (sheetContext) {
      final zh = sheetContext.l10n.isChinese;
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.motion_photos_on_rounded,
              color: AfterFrameColors.lime,
              size: 38,
            ),
            const SizedBox(height: 14),
            Text(
              zh ? '动态记忆已保存' : 'Your memory is alive',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              zh
                  ? 'Motion Photo 已进入 AfterFrame 相册，同时保留聊天兼容的 MP4。'
                  : 'A Motion Photo is in your AfterFrame album, with a chat-safe MP4 copy.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AfterFrameColors.muted,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () async => widget.engine.shareVideo(published),
                icon: const Icon(Icons.send_rounded),
                label: Text(zh ? '发送 MP4' : 'Share MP4'),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(sheetContext),
              child: Text(zh ? '完成' : 'Done'),
            ),
          ],
        ),
      );
    },
  );

  @override
  void dispose() {
    _canvas.removeListener(_refresh);
    _canvas.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final zh = context.l10n.isChinese;
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0D),
      appBar: AppBar(
        title: Column(
          children: [
            Text(
              zh ? '动态记忆画布' : 'Motion Canvas',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: -.2,
              ),
            ),
            Text(
              _canvas.template.title(zh).toUpperCase(),
              style: const TextStyle(
                fontSize: 8,
                color: AfterFrameColors.muted,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _canvas.isExporting ? null : _export,
            child: Text(
              zh ? '导出' : 'Export',
              style: const TextStyle(
                color: AfterFrameColors.lime,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) => Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(18, 6, 18, 16),
                  child: Column(
                    children: [
                      Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: 430,
                            maxHeight: constraints.maxHeight * .51,
                          ),
                          child: AspectRatio(
                            aspectRatio: 9 / 13,
                            child: MotionCanvasRenderer(controller: _canvas),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _MasterTimeline(controller: _canvas),
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.only(top: 14, bottom: 6),
                decoration: const BoxDecoration(
                  color: Color(0xFF141519),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black45,
                      blurRadius: 24,
                      offset: Offset(0, -8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: Row(
                        children: [
                          Text(
                            zh ? '素材轨道' : 'CLIP TRACK',
                            style: const TextStyle(
                              fontSize: 10,
                              color: AfterFrameColors.muted,
                              letterSpacing: 1.4,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            zh ? '长按拖动排序' : 'Hold to reorder',
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.white30,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    MotionClipTrack(controller: _canvas, onEdit: _editClip),
                    CreativeToolDock(controller: _canvas),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _canvas.isExporting
                              ? null
                              : () {
                                  _canvas.createMemory();
                                  _export();
                                },
                          icon: _canvas.isExporting
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.black,
                                  ),
                                )
                              : const Icon(Icons.auto_awesome_rounded),
                          label: Text(
                            _canvas.isExporting
                                ? (zh ? '正在创造记忆…' : 'Creating memory…')
                                : 'Create Memory',
                          ),
                        ),
                      ),
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

class _MasterTimeline extends StatelessWidget {
  const _MasterTimeline({required this.controller});
  final MotionCanvasController controller;

  @override
  Widget build(BuildContext context) {
    final seconds = controller.positionMs / 1000;
    final total = controller.durationMs / 1000;
    return Row(
      children: [
        IconButton.filledTonal(
          onPressed: controller.togglePlayback,
          icon: Icon(
            controller.isPlaying
                ? Icons.pause_rounded
                : Icons.play_arrow_rounded,
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white12,
              thumbColor: AfterFrameColors.lime,
            ),
            child: Slider(
              value: controller.positionMs.toDouble().clamp(
                0,
                controller.durationMs.toDouble(),
              ),
              max: controller.durationMs.toDouble(),
              onChanged: (value) => controller.setPosition(value.round()),
            ),
          ),
        ),
        SizedBox(
          width: 68,
          child: Text(
            '${seconds.toStringAsFixed(1)} / ${total.toStringAsFixed(1)}',
            textAlign: TextAlign.end,
            style: const TextStyle(
              fontSize: 10,
              color: AfterFrameColors.muted,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}
