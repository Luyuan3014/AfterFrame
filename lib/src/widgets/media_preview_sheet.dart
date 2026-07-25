import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../localization/app_localizations.dart';
import '../theme.dart';

Future<void> showMediaPreview(
  BuildContext context, {
  required String uri,
  required String title,
  String? coverPath,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: AfterFrameColors.panel,
  builder: (_) =>
      MediaPreviewSheet(uri: uri, title: title, coverPath: coverPath),
);

class MediaPreviewSheet extends StatefulWidget {
  const MediaPreviewSheet({
    super.key,
    required this.uri,
    required this.title,
    this.coverPath,
  });

  final String uri;
  final String title;
  final String? coverPath;

  @override
  State<MediaPreviewSheet> createState() => _MediaPreviewSheetState();
}

class _MediaPreviewSheetState extends State<MediaPreviewSheet> {
  VideoPlayerController? _controller;
  Object? _error;
  bool _muted = false;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    final parsed = Uri.parse(widget.uri);
    final controller = parsed.scheme == 'content'
        ? VideoPlayerController.contentUri(parsed)
        : parsed.scheme == 'http' || parsed.scheme == 'https'
        ? VideoPlayerController.networkUrl(parsed)
        : VideoPlayerController.file(
            File(parsed.scheme == 'file' ? parsed.toFilePath() : widget.uri),
          );
    _controller = controller;
    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.play();
      if (mounted) setState(() {});
    } catch (error) {
      _error = error;
      if (mounted) setState(() {});
    }
  }

  Future<void> _togglePlayback() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    controller.value.isPlaying
        ? await controller.pause()
        : await controller.play();
    if (mounted) setState(() {});
  }

  Future<void> _toggleMute() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    _muted = !_muted;
    await controller.setVolume(_muted ? 0 : 1);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    final controller = _controller;
    if (controller != null) unawaited(controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final ready = controller?.value.isInitialized ?? false;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: 280,
                maxHeight: MediaQuery.sizeOf(context).height * .68,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: ColoredBox(
                  color: Colors.black,
                  child: AspectRatio(
                    aspectRatio: ready
                        ? controller!.value.aspectRatio
                              .clamp(.55, 1.8)
                              .toDouble()
                        : 9 / 16,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (widget.coverPath case final path?)
                          Image.file(File(path), fit: BoxFit.cover),
                        if (ready)
                          FittedBox(
                            fit: BoxFit.contain,
                            child: SizedBox(
                              width: controller!.value.size.width,
                              height: controller.value.size.height,
                              child: VideoPlayer(controller),
                            ),
                          ),
                        if (!ready)
                          Center(
                            child: _error == null
                                ? const CircularProgressIndicator(
                                    color: AfterFrameColors.lime,
                                  )
                                : Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.error_outline_rounded,
                                        color: Colors.white54,
                                        size: 36,
                                      ),
                                      const SizedBox(height: 10),
                                      Text(context.l10n.text('previewFailed')),
                                    ],
                                  ),
                          ),
                        if (ready)
                          Center(
                            child: IconButton.filledTonal(
                              iconSize: 32,
                              onPressed: _togglePlayback,
                              icon: Icon(
                                controller!.value.isPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (ready) ...[
            const SizedBox(height: 12),
            VideoProgressIndicator(
              controller!,
              allowScrubbing: true,
              colors: const VideoProgressColors(
                playedColor: AfterFrameColors.lime,
                bufferedColor: Colors.white30,
                backgroundColor: Colors.white12,
              ),
            ),
            Row(
              children: [
                IconButton(
                  tooltip: context.l10n.text(_muted ? 'unmute' : 'mute'),
                  onPressed: _toggleMute,
                  icon: Icon(
                    _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                  ),
                ),
                const Spacer(),
                Text(
                  context.l10n.text('loopPreview'),
                  style: const TextStyle(
                    color: AfterFrameColors.muted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
