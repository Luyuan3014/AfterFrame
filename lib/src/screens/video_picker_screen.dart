import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../models/media_asset.dart';
import '../services/media_engine.dart';
import '../theme.dart';
import '../localization/app_localizations.dart';
import '../widgets/media_preview_sheet.dart';

class VideoPickerScreen extends StatefulWidget {
  const VideoPickerScreen({
    super.key,
    required this.engine,
    required this.mode,
  });
  final MediaEngine engine;
  final int mode;

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
    setState(() {
      final index = _selectedUris.indexOf(item.uri);
      if (index >= 0) {
        _selectedUris.removeAt(index);
      } else {
        if (widget.mode == 0) {
          _selectedUris
            ..clear()
            ..add(item.uri);
        } else if (_selectedUris.length < 3) {
          _selectedUris.add(item.uri);
        } else {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _message('collageSourceLimit'),
          );
        }
      }
    });
  }

  Future<void> _preview(MediaAsset item) =>
      showMediaPreview(context, uri: item.uri, title: item.name);

  Future<void> _submit() async {
    if (_selectedUris.isEmpty ||
        (widget.mode == 1 && _selectedUris.length < 2) ||
        _submitting) {
      return;
    }
    setState(() => _submitting = true);
    try {
      final assets = <MediaAsset>[];
      for (final uri in _selectedUris) {
        assets.add(await widget.engine.inspectVideo(uri));
      }
      if (mounted) Navigator.pop(context, assets);
    } catch (error) {
      if (mounted) _message('errorInspect');
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
              l10n.text(widget.mode == 1 ? 'pickCollageVideos' : 'pickVideo'),
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
      bottomNavigationBar: _selectedUris.isEmpty
          ? null
          : _SelectionBar(
              count: _selectedUris.length,
              mode: widget.mode,
              loading: _submitting,
              onSubmit: _submit,
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

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.count,
    required this.mode,
    required this.loading,
    required this.onSubmit,
  });
  final int count;
  final int mode;
  final bool loading;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 11, 18, 11),
        decoration: const BoxDecoration(
          color: AfterFrameColors.panel,
          border: Border(top: BorderSide(color: Colors.white10)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                l10n.text('selectedInOrder', {'count': count}),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            FilledButton(
              onPressed: loading || (mode == 1 && count < 2) ? null : onSubmit,
              style: FilledButton.styleFrom(
                minimumSize: const Size(116, 48),
                padding: const EdgeInsets.symmetric(horizontal: 22),
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
                      l10n.text(mode == 1 ? 'addCount' : 'doneCount', {
                        'count': count,
                      }),
                    ),
            ),
          ],
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
