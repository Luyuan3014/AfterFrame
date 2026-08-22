import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../features/motion_canvas/widgets/canvas_layout_thumb.dart';
import '../models/live_rules.dart';
import '../models/media_asset.dart';
import '../services/media_engine.dart';
import '../theme.dart';
import '../localization/app_localizations.dart';
import '../widgets/media_preview_sheet.dart';

enum _LibraryFilter { all, video, live }

class VideoPickerScreen extends StatefulWidget {
  const VideoPickerScreen({
    super.key,
    required this.engine,
    this.initialSelection = const [],
  });
  final MediaEngine engine;
  final List<MediaAsset> initialSelection;

  @override
  State<VideoPickerScreen> createState() => _VideoPickerScreenState();
}

class _VideoPickerScreenState extends State<VideoPickerScreen> {
  final _scrollController = ScrollController();
  final List<String> _selectedIds = [];
  List<MediaAsset> _library = const [];
  _LibraryFilter _filter = _LibraryFilter.all;
  bool _loading = true;
  bool _denied = false;
  bool _submitting = false;
  bool _showScrollbar = false;
  Timer? _scrollbarTimer;

  @override
  void initState() {
    super.initState();
    _selectedIds.addAll([
      for (final asset in widget.initialSelection) asset.identity,
    ]);
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
      final library = await widget.engine.listVideos();
      if (mounted) {
        final available = {for (final item in library) item.identity};
        setState(() {
          _library = library;
          _selectedIds.removeWhere((id) => !available.contains(id));
        });
      }
    } catch (error) {
      if (mounted) _message('errorLibrary');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<MediaAsset> get _visibleLibrary => switch (_filter) {
    _LibraryFilter.all => _library,
    _LibraryFilter.video => [
      for (final item in _library)
        if (!item.isMotionPhoto) item,
    ],
    _LibraryFilter.live => [
      for (final item in _library)
        if (item.isMotionPhoto) item,
    ],
  };

  void _toggle(MediaAsset item) {
    if (_submitting) return;
    HapticFeedback.selectionClick();
    final index = _selectedIds.indexOf(item.identity);
    if (index >= 0) {
      setState(() => _selectedIds.removeAt(index));
      return;
    }
    if (_selectedIds.length >= maxLiveSources) {
      _message('sourceLimit');
      return;
    }
    setState(() => _selectedIds.add(item.identity));
  }

  void _removeSelected(String id) {
    if (_submitting) return;
    setState(() => _selectedIds.remove(id));
  }

  void _reorderSelected(int oldIndex, int newIndex) {
    if (_submitting) return;
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final id = _selectedIds.removeAt(oldIndex);
      _selectedIds.insert(newIndex.clamp(0, _selectedIds.length), id);
    });
  }

  /// Selection order is the editorial order, so it is preserved verbatim.
  List<MediaAsset> get _selectedAssets {
    final byId = {for (final item in _library) item.identity: item};
    return _selectedIds
        .map((id) => byId[id])
        .whereType<MediaAsset>()
        .toList(growable: false);
  }

  Future<void> _preview(MediaAsset item) async {
    var uri = item.uri;
    if (item.isMotionPhoto) {
      try {
        uri = (await widget.engine.resolvePlayable(item)).uri;
      } catch (_) {
        if (mounted) _message('errorLiveImport');
        return;
      }
    }
    if (!mounted) return;
    await showMediaPreview(context, uri: uri, title: item.name);
  }

  Future<void> _submit() async {
    if (_selectedIds.isEmpty || _submitting) {
      return;
    }
    setState(() => _submitting = true);
    try {
      final assets = <MediaAsset>[];
      for (final item in _selectedAssets) {
        assets.add(
          item.isMotionPhoto ? await widget.engine.resolvePlayable(item) : item,
        );
      }
      if (mounted && assets.isNotEmpty) Navigator.pop(context, assets);
    } catch (_) {
      if (mounted) _message('errorLiveImport');
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
              _selectedIds.isEmpty
                  ? l10n.text('pickHint')
                  : l10n.text('selectedCount', {'count': _selectedIds.length}),
              style: TextStyle(
                fontSize: 11,
                color: _selectedIds.isEmpty
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
        child: _selectedIds.isEmpty
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
    return Column(
      children: [
        _LibraryFilters(
          filter: _filter,
          videoCount: _library.where((item) => !item.isMotionPhoto).length,
          liveCount: _library.where((item) => item.isMotionPhoto).length,
          onChanged: (value) => setState(() => _filter = value),
        ),
        if (_selectedAssets.isNotEmpty)
          _SelectedStrip(
            assets: _selectedAssets,
            engine: widget.engine,
            onRemove: _removeSelected,
            onReorder: _reorderSelected,
            onPreview: _preview,
          ),
        Expanded(child: _libraryBody()),
      ],
    );
  }

  Widget _libraryBody() {
    if (_library.isEmpty) {
      return _LibraryEmpty(
        icon: Icons.photo_library_outlined,
        title: context.l10n.text('libraryEmpty'),
        detail: context.l10n.text('libraryEmptyHint'),
      );
    }
    final visible = _visibleLibrary;
    if (visible.isEmpty) {
      return _LibraryEmpty(
        icon: _filter == _LibraryFilter.live
            ? Icons.motion_photos_on_outlined
            : Icons.videocam_outlined,
        title: context.l10n.text(
          _filter == _LibraryFilter.live ? 'libraryEmptyLive' : 'libraryEmpty',
        ),
        detail: context.l10n.text(
          _filter == _LibraryFilter.live
              ? 'libraryEmptyLiveHint'
              : 'libraryEmptyHint',
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
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
              childAspectRatio: .76,
            ),
            itemCount: visible.length,
            itemBuilder: (_, index) {
              final asset = visible[index];
              final selectedIndex = _selectedIds.indexOf(asset.identity);
              return _VideoTile(
                key: ValueKey(asset.identity),
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

class _LibraryFilters extends StatelessWidget {
  const _LibraryFilters({
    required this.filter,
    required this.videoCount,
    required this.liveCount,
    required this.onChanged,
  });

  final _LibraryFilter filter;
  final int videoCount;
  final int liveCount;
  final ValueChanged<_LibraryFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Row(
        children: [
          _FilterChip(
            label: l10n.text('pickFilterAll'),
            selected: filter == _LibraryFilter.all,
            onTap: () => onChanged(_LibraryFilter.all),
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: l10n.text('pickFilterVideo'),
            count: videoCount,
            selected: filter == _LibraryFilter.video,
            onTap: () => onChanged(_LibraryFilter.video),
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: l10n.text('pickFilterLive'),
            count: liveCount,
            selected: filter == _LibraryFilter.live,
            live: true,
            onTap: () => onChanged(_LibraryFilter.live),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
    this.live = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;
  final bool live;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AfterFrameColors.lime : AfterFrameColors.panelSoft,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (live) ...[
                Icon(
                  Icons.motion_photos_on_rounded,
                  size: 14,
                  color: selected ? AfterFrameColors.ink : AfterFrameColors.lime,
                ),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: selected ? AfterFrameColors.ink : Colors.white,
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 5),
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: selected
                        ? AfterFrameColors.ink.withValues(alpha: .62)
                        : AfterFrameColors.muted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectedStrip extends StatelessWidget {
  const _SelectedStrip({
    required this.assets,
    required this.engine,
    required this.onRemove,
    required this.onReorder,
    required this.onPreview,
  });

  final List<MediaAsset> assets;
  final MediaEngine engine;
  final ValueChanged<String> onRemove;
  final void Function(int oldIndex, int newIndex) onReorder;
  final ValueChanged<MediaAsset> onPreview;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 92,
      child: ReorderableListView.builder(
        scrollDirection: Axis.horizontal,
        buildDefaultDragHandles: false,
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        itemCount: assets.length,
        onReorder: onReorder,
        proxyDecorator: (child, _, animation) => ScaleTransition(
          scale: Tween(begin: 1.0, end: 1.06).animate(animation),
          child: child,
        ),
        itemBuilder: (context, index) {
          final asset = assets[index];
          return ReorderableDelayedDragStartListener(
            key: ValueKey(asset.identity),
            index: index,
            child: _SelectedThumb(
              asset: asset,
              engine: engine,
              order: index + 1,
              onRemove: () => onRemove(asset.identity),
              onPreview: () => onPreview(asset),
            ),
          );
        },
      ),
    );
  }
}

class _SelectedThumb extends StatelessWidget {
  const _SelectedThumb({
    required this.asset,
    required this.engine,
    required this.order,
    required this.onRemove,
    required this.onPreview,
  });

  final MediaAsset asset;
  final MediaEngine engine;
  final int order;
  final VoidCallback onRemove;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: SizedBox(
        width: 62,
        height: 78,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: Material(
                color: AfterFrameColors.panelSoft,
                borderRadius: BorderRadius.circular(14),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onPreview,
                  child: FutureBuilder<String>(
                    future: engine.videoThumbnail(asset.thumbnailUri),
                    builder: (_, snapshot) {
                      final path = snapshot.data;
                      if (path == null || path.isEmpty) {
                        return const ColoredBox(color: Color(0xFF292A2F));
                      }
                      return Image.file(
                        File(path),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            const ColoredBox(color: Color(0xFF292A2F)),
                      );
                    },
                  ),
                ),
              ),
            ),
            Positioned(
              left: 5,
              top: 5,
              child: _OrderBadge(order: order),
            ),
            if (asset.isMotionPhoto)
              const Positioned(
                right: 5,
                bottom: 5,
                child: _LiveMark(compact: true),
              ),
            Positioned(
              right: -4,
              top: -4,
              child: IconButton.filled(
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(
                  width: 22,
                  height: 22,
                ),
                padding: EdgeInsets.zero,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black87,
                  foregroundColor: Colors.white,
                ),
                onPressed: onRemove,
                icon: const Icon(Icons.close_rounded, size: 13),
              ),
            ),
          ],
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
      widget.engine.videoThumbnail(widget.asset.thumbnailUri);

  void _retryThumbnail() => setState(
    () => _thumbnail = widget.engine.refreshVideoThumbnail(
      widget.asset.thumbnailUri,
    ),
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
              if (widget.asset.isMotionPhoto)
                const Positioned(
                  left: 7,
                  top: 7,
                  child: _LiveMark(),
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
                  icon: Icon(
                    widget.asset.isMotionPhoto
                        ? Icons.motion_photos_on_rounded
                        : Icons.play_arrow_rounded,
                    size: 18,
                  ),
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
                      Icon(
                        widget.asset.isMotionPhoto
                            ? Icons.motion_photos_on_rounded
                            : Icons.play_arrow_rounded,
                        size: 13,
                      ),
                      const SizedBox(width: 2),
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

class _LiveMark extends StatelessWidget {
  const _LiveMark({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 4 : 6,
        vertical: compact ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: AfterFrameColors.lime,
        borderRadius: BorderRadius.circular(7),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 6)],
      ),
      child: Text(
        context.l10n.text('liveBadge'),
        style: TextStyle(
          color: AfterFrameColors.ink,
          fontSize: compact ? 7 : 8,
          fontWeight: FontWeight.w900,
          letterSpacing: compact ? 0.4 : 0.7,
        ),
      ),
    );
  }
}

class _OrderBadge extends StatelessWidget {
  const _OrderBadge({required this.order});

  final int order;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: AfterFrameColors.lime,
        shape: BoxShape.circle,
      ),
      child: Text(
        '$order',
        style: const TextStyle(
          color: AfterFrameColors.ink,
          fontSize: 10,
          fontWeight: FontWeight.w900,
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

class _LibraryEmpty extends StatelessWidget {
  const _LibraryEmpty({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 72, color: Colors.white24),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AfterFrameColors.muted),
            ),
          ],
        ),
      ),
    );
  }
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
                Icons.photo_library_rounded,
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
