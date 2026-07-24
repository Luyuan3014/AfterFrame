import 'dart:io';

import 'package:flutter/material.dart';

import '../models/media_asset.dart';
import '../services/media_engine.dart';
import '../theme.dart';

class VideoPickerScreen extends StatefulWidget {
  const VideoPickerScreen({super.key, required this.engine, required this.mode});
  final MediaEngine engine;
  final int mode;

  @override
  State<VideoPickerScreen> createState() => _VideoPickerScreenState();
}

class _VideoPickerScreenState extends State<VideoPickerScreen> {
  List<MediaAsset> _videos = const [];
  bool _loading = true;
  bool _denied = false;
  String? _openingUri;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _denied = false; });
    try {
      final allowed = await widget.engine.requestVideoAccess();
      if (!allowed) {
        if (mounted) setState(() => _denied = true);
        return;
      }
      final videos = await widget.engine.listVideos();
      if (mounted) setState(() => _videos = videos);
    } catch (error) {
      if (mounted) _message(error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(MediaAsset item) async {
    if (_openingUri != null) return;
    setState(() => _openingUri = item.uri);
    try {
      final asset = await widget.engine.inspectVideo(item.uri);
      if (mounted) Navigator.pop(context, asset);
    } catch (error) {
      if (mounted) _message(error);
    } finally {
      if (mounted) setState(() => _openingUri = null);
    }
  }

  void _message(Object error) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString()), behavior: SnackBarBehavior.floating),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          titleSpacing: 4,
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.mode == 1 ? '选择拼图视频' : '选择一段视频', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            Text(widget.mode == 1 ? '用多个瞬间拼成动态叙事' : '挑选最值得留下的一帧', style: const TextStyle(fontSize: 11, color: AfterFrameColors.muted)),
          ]),
        ),
        body: _body(),
      );

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator(color: AfterFrameColors.lime));
    if (_denied) return _PermissionEmpty(onRetry: _load);
    if (_videos.isEmpty) {
      return const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.video_library_outlined, size: 72, color: Colors.white24),
        SizedBox(height: 16),
        Text('媒体库里还没有视频', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        SizedBox(height: 6),
        Text('拍摄或保存视频后，它会出现在这里', style: TextStyle(color: AfterFrameColors.muted)),
      ]));
    }
    return RefreshIndicator(
      color: AfterFrameColors.lime,
      onRefresh: _load,
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 4, crossAxisSpacing: 4, childAspectRatio: .76),
        itemCount: _videos.length,
        itemBuilder: (_, index) => _VideoTile(
          asset: _videos[index],
          engine: widget.engine,
          opening: _openingUri == _videos[index].uri,
          onTap: () => _open(_videos[index]),
        ),
      ),
    );
  }
}

class _VideoTile extends StatefulWidget {
  const _VideoTile({required this.asset, required this.engine, required this.opening, required this.onTap});
  final MediaAsset asset;
  final MediaEngine engine;
  final bool opening;
  final VoidCallback onTap;
  @override
  State<_VideoTile> createState() => _VideoTileState();
}

class _VideoTileState extends State<_VideoTile> {
  late final Future<String> _thumbnail = widget.engine.videoThumbnail(widget.asset.uri);

  @override
  Widget build(BuildContext context) => Material(
        color: AfterFrameColors.panelSoft,
        borderRadius: BorderRadius.circular(13),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onTap,
          child: Stack(fit: StackFit.expand, children: [
            FutureBuilder<String>(
              future: _thumbnail,
              builder: (_, snapshot) => snapshot.hasData && snapshot.data!.isNotEmpty
                  ? Image.file(File(snapshot.data!), fit: BoxFit.cover)
                  : const Center(child: Icon(Icons.movie_outlined, color: Colors.white24)),
            ),
            const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.transparent, Color(0xD9000000)], begin: Alignment.center, end: Alignment.bottomCenter))),
            Positioned(
              left: 7,
              bottom: 7,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                child: Row(children: [
                  const Icon(Icons.play_arrow_rounded, size: 13),
                  Text(widget.asset.durationLabel, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
            if (widget.opening) const ColoredBox(color: Colors.black54, child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: AfterFrameColors.lime))),
          ]),
        ),
      );
}

class _PermissionEmpty extends StatelessWidget {
  const _PermissionEmpty({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(color: AfterFrameColors.lime.withValues(alpha: .12), shape: BoxShape.circle),
              child: const Icon(Icons.video_library_rounded, color: AfterFrameColors.lime, size: 36),
            ),
            const SizedBox(height: 20),
            const Text('允许访问你的视频', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            const Text('AfterFrame 只读取你选择用于创作的视频，不会上传媒体库内容。', textAlign: TextAlign.center, style: TextStyle(color: AfterFrameColors.muted, height: 1.5)),
            const SizedBox(height: 24),
            FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.lock_open_rounded), label: const Text('继续授权')),
          ]),
        ),
      );
}
