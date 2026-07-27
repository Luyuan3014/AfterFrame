import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../features/motion_canvas/widgets/canvas_layout_thumb.dart';
import '../models/live_rules.dart';
import '../models/media_asset.dart';
import '../services/media_engine.dart';
import '../theme.dart';
import '../localization/app_localizations.dart';
import '../widgets/media_preview_sheet.dart';

class VideoPickerScreen extends StatefulWidget {
  const VideoPickerScreen({super.key, required this.engine});
  final MediaEngine engine;

  @override
  State<VideoPickerScreen> createState() => _VideoPickerScreenState();
}

class _VideoPickerScreenState extends State<VideoPickerScreen> {
  final _scrollController = ScrollController();
  final List<String> _selectedUris = [];
  List<MediaAsset> _videos = const [];
  bool _loading = true;
  bool _denied = false;
  bool _submitting = false;
  bool _showScrollbar = false;
  Timer? _scrollbarTimer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scrollbarTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _denied = false;
    });
    try {
      final allowed = await widget.engine.requestVideoAccess();
      if (!allowed) {
        if (mounted) setState(() => _denied = true);
        return;
      }
      final videos = await widget.engine.listVideos();
      if (mounted) {
        final available = videos.map((item) => item.uri).toSet();
        setState(() {
          _videos = videos;
          _selectedUris.removeWhere((uri) => !available.contains(uri));
        });
      }
    } catch (error) {
      if (mounted) _message('errorLibrary');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toggle(MediaAsset item) {
    if (_submitting) return;
    final index = _selectedUris.indexOf(item.uri);
    if (index >= 0) {
      setState(() => _selectedUris.removeAt(index));
      return;
    }
    if (_selectedUris.length >= maxLiveSources) {
      _message('sourceLimit');
      return;
    }
    setState(() => _selectedUris.add(item.uri));
  }

  /// Selection order is the editorial order, so it is preserved verbatim.
  List<MediaAsset> get _selectedAssets {
    final byUri = {for (final video in _videos) video.uri: video};
    return _selectedUris
        .map((uri) => byUri[uri])
        .whereType<MediaAsset>()
        .toList(growable: false);
  }

  Future<void> _preview(MediaAsset item) =>
      showMediaPreview(context, uri: item.uri, title: item.name);

  Future<void> _submit() async {
    if (_selectedUris.isEmpty || _submitting) {
      return;
    }
    setState(() => _submitting = true);
    try {
      // 直接使用已缓存的视频列表数据（listVideos 已通过 MediaStore
      // 返回了 uri / name / durationMs / width / height），避免再次
      // 使用 Android MediaMetadataRetriever 读取素材信息。
      // getSafParameterForRead 处理 content URI 时可能 native crash。
      final assets = _selectedAssets;
      if (mounted && assets.isNotEmpty) Navigator.pop(context, assets);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  bool _onScroll(ScrollNotification notification) {
    _scrollbarTimer?.cancel();
    if (!_showScrollbar && mounted) setState(() => _showScrollbar = true);
    if (notification is ScrollEndNotification) {
      _scrollbarTimer = Timer(const Duration(milliseconds: 850), () {
        if (mounted) setState(() => _showScrollbar = false);
      });
    }
    return false;
  }

  void _message(String key) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(context.l10n.text(key)),
      behavior: SnackBarBehavior.floating,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 4,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.text('pickStudioVideos'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            Text(
              _selectedUris.isEmpty
                  ? l10n.text('pickHint')
                  : l10n.text('selectedCount', {'count': _selectedUris.length}),
              style: TextStyle(
                fontSize: 11,
                color: _selectedUris.isEmpty
                    ? AfterFrameColors.muted
                    : AfterFrameColors.lime,
              ),
            ),
          ],
        ),
      ),
      body: _body(),
      bottomNavigationBar: AnimatedSize(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: _selectedUris.isEmpty
            ? const SizedBox(width: double.infinity)
            : _CompositionBar(
                assets: _selectedAssets,
                engine: widget.engine,
                loading: _submitting,
                onSubmit: _submit,
              ),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AfterFrameColors.lime),
      );
    }
    if (_denied) return _PermissionEmpty(onRetry: _load);
    if (_videos.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.video_library_outlined,
              size: 72,
              color: Colors.white24,
            ),
            const SizedBox(height: 16),
            Text(
              context.l10n.text('libraryEmpty'),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              context.l10n.text('libraryEmptyHint'),
              style: const TextStyle(color: AfterFrameColors.muted),
            ),
          ],
        ),
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: RawScrollbar(
        controller: _scrollController,
        thumbVisibility: _showScrollbar,
        interactive: true,
        thickness: 5,
        radius: const Radius.circular(8),
        thumbColor: AfterFrameColors.lime.withValues(alpha: .9),
        minThumbLength: 42,
        child: RefreshIndicator(
          color: AfterFrameColors.lime,
          onRefresh: _load,
          child: GridView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 28),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
              childAspectRatio: .76,
            ),
            itemCount: _videos.length,
            itemBuilder: (_, index) {
              final asset = _videos[index];
              final selectedIndex = _selectedUris.indexOf(asset.uri);
              return _VideoTile(
                key: ValueKey(asset.uri),
                asset: asset,
                engine: widget.engine,
                selectionOrder: selectedIndex < 0 ? null : selectedIndex + 1,
                onTap: () => _toggle(asset),
                onPreview: () => _preview(asset),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _VideoTile extends StatefulWidget {
  const _VideoTile({
    super.key,
    required this.asset,
    required this.engine,
    required this.selectionOrder,
    required this.onTap,
    required this.onPreview,
  });
  final MediaAsset asset;
  final MediaEngine engine;
  final int? selectionOrder;
  final VoidCallback onTap;
  final VoidCallback onPreview;
  @override
  State<_VideoTile> createState() => _VideoTileState();
}

class _VideoTileState extends State<_VideoTile> {
  late Future<String> _thumbnail = _loadThumbnail();

  Future<String> _loadThumbnail() =>
      widget.engine.videoThumbnail(widget.asset.uri);

  void _retryThumbnail() => setState(
    () => _thumbnail = widget.engine.refreshVideoThumbnail(widget.asset.uri),
  );

  @override
  Widget build(BuildContext context) {
    final selected = widget.selectionOrder != null;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: selected ? AfterFrameColors.lime : Colors.transparent,
          width: 2,
        ),
      ),
      child: Material(
        color: AfterFrameColors.panelSoft,
        borderRadius: BorderRadius.circular(11),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onTap,
          onLongPress: widget.onPreview,
          child: Stack(
            fit: StackFit.expand,
            children: [
              FutureBuilder<String>(
                future: _thumbnail,
                builder: (_, snapshot) {
                  if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                    return Image.file(
                      File(snapshot.data!),
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          _ThumbnailRetry(onRetry: _retryThumbnail),
                    );
                  }
                  if (snapshot.hasError) {
                    return _ThumbnailRetry(onRetry: _retryThumbnail);
                  }
                  return const Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white24,
                    ),
                  );
                },
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.transparent, Color(0xD9000000)],
                    begin: Alignment.center,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
              Positioned(
                right: 7,
                top: 7,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 25,
                  height: 25,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected ? AfterFrameColors.lime : Colors.black38,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? AfterFrameColors.lime : Colors.white,
                      width: 1.5,
                    ),
                    boxShadow: const [
                      BoxShadow(color: Colors.black38, blurRadius: 5),
                    ],
                  ),
                  child: selected
                      ? Text(
                          '${widget.selectionOrder}',
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        )
                      : null,
                ),
              ),
              Positioned(
                right: 5,
                bottom: 4,
                child: IconButton.filledTonal(
                  tooltip: context.l10n.text('previewMaterial'),
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: 31,
                    height: 31,
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: widget.onPreview,
                  icon: const Icon(Icons.play_arrow_rounded, size: 19),
                ),
              ),
              Positioned(
                left: 7,
                bottom: 7,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.play_arrow_rounded, size: 13),
                      Text(
                        widget.asset.durationLabel,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThumbnailRetry extends StatelessWidget {
  const _ThumbnailRetry({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: IconButton(
      tooltip: context.l10n.text('retryThumbnail'),
      onPressed: onRetry,
      icon: const Icon(Icons.refresh_rounded, color: Colors.white54),
    ),
  );
}

/// Announces the work the current selection will produce.
///
/// The miniature is the real Adaptive Canvas plan, so the number of chosen
/// sources — and nothing else — visibly decides the shape before Studio opens.
class _CompositionBar extends StatelessWidget {
  const _CompositionBar({
    required this.assets,
    required this.engine,
    required this.loading,
    required this.onSubmit,
  });

  final List<MediaAsset> assets;
  final MediaEngine engine;
  final bool loading;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final composition = LiveComposition.forSourceCount(assets.length);
    final isCanvas = composition.isCanvas;
    final title = isCanvas
        ? l10n.text('canvasSummary', {'count': assets.length})
        : l10n.text('singleFrameSummary');
    final detail = l10n.text(
      isCanvas ? 'canvasDetail' : 'singleFrameDetail',
      {'count': assets.length},
    );
    final remaining = maxLiveSources - assets.length;
    return SafeArea(
      top: false,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 15),
            decoration: const BoxDecoration(
              color: AfterFrameColors.glass,
              border: Border(
                top: BorderSide(color: AfterFrameColors.glassBorder),
              ),
            ),
            child: Row(
              children: [
                CanvasLayoutThumb(assets: assets, engine: engine),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    // The bottom slot offers the whole screen height, so the bar
                    // must measure itself from its content or it would cover the
                    // library and swallow every tap.
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              l10n.text('willCreate'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AfterFrameColors.lime,
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.6,
                              ),
                            ),
                          ),
                          if (remaining > 0) ...[
                            const SizedBox(width: 7),
                            Flexible(
                              child: Text(
                                l10n.text('roomForMore', {'count': remaining}),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: AfterFrameColors.muted,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        detail,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10,
                          height: 1.35,
                          color: AfterFrameColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: loading ? null : onSubmit,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    // Keeps a long label or a large text scale from starving the
                    // announcement next to it.
                    maximumSize: const Size(176, double.infinity),
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                  ),
                  child: loading
                      ? const SizedBox.square(
                          dimension: 19,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        )
                      : Text(
                          l10n.text('enterStudio'),
                          maxLines: 1,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PermissionEmpty extends StatelessWidget {
  const _PermissionEmpty({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: AfterFrameColors.lime.withValues(alpha: .12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.video_library_rounded,
                color: AfterFrameColors.lime,
                size: 36,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              l10n.text('allowVideos'),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.text('permissionDetail'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AfterFrameColors.muted,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.lock_open_rounded),
              label: Text(l10n.text('continuePermission')),
            ),
          ],
        ),
      ),
    );
  }
}
