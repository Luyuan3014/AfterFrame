import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../controllers/motion_canvas_controller.dart';
import '../models/motion_canvas_layout.dart';
import '../preview/preview_engine.dart';

class MotionCanvasRenderer extends StatefulWidget {
  const MotionCanvasRenderer({
    super.key,
    required this.controller,
    this.previewEngine = const Media3PreviewEngine(),
    this.showChrome = true,
    this.playbackEnabled = true,
    this.showPlaybackControl = true,
    this.interactive = false,
  });

  final MotionCanvasController controller;
  final PreviewEngine previewEngine;
  final bool showChrome;
  final bool playbackEnabled;
  final bool showPlaybackControl;
  final bool interactive;

  @override
  State<MotionCanvasRenderer> createState() => _MotionCanvasRendererState();
}

class _MotionCanvasRendererState extends State<MotionCanvasRenderer> {
  final Map<String, VideoPlayerController> _players = {};
  bool _syncing = false;
  int _lastSyncMs = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onCanvasChanged);
    unawaited(_ensurePlayers());
  }

  @override
  void didUpdateWidget(covariant MotionCanvasRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onCanvasChanged);
      widget.controller.addListener(_onCanvasChanged);
      unawaited(_ensurePlayers());
    }
    if (oldWidget.playbackEnabled != widget.playbackEnabled) {
      unawaited(_applyPlaybackIntent());
    }
  }

  Future<void> _ensurePlayers() async {
    final expected = widget.controller.clips.map((clip) => clip.id).toSet();
    final obsolete = _players.keys
        .where((id) => !expected.contains(id))
        .toList();
    for (final id in obsolete) {
      final player = _players.remove(id);
      player?.removeListener(_onPlayerTick);
      await player?.dispose();
    }
    for (final clip in widget.controller.clips) {
      if (_players.containsKey(clip.id)) continue;
      final player = widget.previewEngine.create(clip.asset.uri);
      _players[clip.id] = player;
      try {
        await player.initialize();
        await player.setLooping(false);
        await player.setVolume(
          widget.playbackEnabled &&
                  widget.controller.audioEnabled &&
                  clip == widget.controller.clips.first
              ? 1
              : 0,
        );
        await player.setPlaybackSpeed(widget.controller.playbackSpeed);
        await player.seekTo(Duration(milliseconds: clip.resolvedCoverMs));
        player.addListener(_onPlayerTick);
        final decoded = player.value.size;
        final decodedMs = player.value.duration.inMilliseconds;
        final clipIndex = widget.controller.clips.indexWhere(
          (item) => item.id == clip.id,
        );
        if (clipIndex >= 0 && decoded.width > 2 && decoded.height > 2) {
          widget.controller.adoptDecodedSource(
            clipIndex,
            width: decoded.width.round(),
            height: decoded.height.round(),
            decodedDurationMs: decodedMs > 0
                ? decodedMs
                : clip.asset.durationMs,
          );
        }
      } catch (_) {
        // A failed source keeps its editorial placeholder without taking down
        // the rest of the canvas.
      }
    }
    await _applyPlaybackIntent();
    if (mounted) setState(() {});
  }

  void _onCanvasChanged() {
    if (!mounted) return;
    final clipIds = widget.controller.clips.map((clip) => clip.id).toSet();
    if (clipIds.length != _players.length ||
        !clipIds.every(_players.containsKey)) {
      unawaited(_ensurePlayers());
      return;
    }
    unawaited(_applyPlaybackIntent());
    setState(() {});
  }

  Future<void> _applyPlaybackIntent() async {
    if (_syncing) return;
    _syncing = true;
    try {
      for (final clip in widget.controller.clips) {
        final player = _players[clip.id];
        if (player == null || !player.value.isInitialized) continue;
        final expected = widget.controller.isPlaying
            ? clip.trimStartMs + widget.controller.positionMs
            : clip.resolvedCoverMs;
        if ((player.value.position.inMilliseconds - expected).abs() > 110) {
          await player.seekTo(Duration(milliseconds: expected));
        }
        await player.setVolume(
          widget.playbackEnabled &&
                  widget.controller.audioEnabled &&
                  clip == widget.controller.clips.first
              ? 1
              : 0,
        );
        await player.setPlaybackSpeed(widget.controller.playbackSpeed);
        if (widget.playbackEnabled &&
            widget.controller.isPlaying &&
            !player.value.isPlaying) {
          await player.play();
        } else if (!widget.controller.isPlaying && player.value.isPlaying) {
          await player.pause();
        }
      }
    } finally {
      _syncing = false;
    }
  }

  void _onPlayerTick() {
    if (_syncing || !widget.controller.isPlaying) return;
    final first = widget.controller.clips.first;
    final leader = _players[first.id];
    if (leader == null || !leader.value.isInitialized) return;
    final now = leader.value.position.inMilliseconds - first.trimStartMs;
    if (now >= widget.controller.durationMs) {
      if (widget.controller.loopEnabled) {
        unawaited(_restartLoop());
        return;
      }
      for (final player in _players.values) {
        unawaited(player.pause());
      }
      widget.controller.stopAtEnd();
      return;
    }
    if ((now - _lastSyncMs).abs() >= 90) {
      _lastSyncMs = now;
      widget.controller.setPosition(now, notify: false);
      if (mounted) setState(() {});
    }
    if (now % 400 < 100) unawaited(_correctDrift(now));
  }

  Future<void> _restartLoop() async {
    if (_syncing) return;
    _syncing = true;
    try {
      widget.controller.setPosition(0, notify: false);
      for (final clip in widget.controller.clips) {
        final player = _players[clip.id];
        if (player == null || !player.value.isInitialized) continue;
        await player.seekTo(Duration(milliseconds: clip.trimStartMs));
        if (widget.playbackEnabled) await player.play();
      }
      if (mounted) setState(() {});
    } finally {
      _syncing = false;
    }
  }

  Future<void> _correctDrift(int masterMs) async {
    for (final clip in widget.controller.clips.skip(1)) {
      final player = _players[clip.id];
      if (player == null || !player.value.isInitialized) continue;
      final expected = clip.trimStartMs + masterMs;
      if ((player.value.position.inMilliseconds - expected).abs() > 85) {
        await player.seekTo(Duration(milliseconds: expected));
      }
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onCanvasChanged);
    for (final player in _players.values) {
      player.removeListener(_onPlayerTick);
      unawaited(player.dispose());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canvas = widget.controller;
    return Semantics(
      label: 'Motion Canvas preview',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(
          widget.showChrome ? canvas.layout.cornerRadius : 0,
        ),
        clipBehavior: Clip.antiAlias,
        child: ColoredBox(
          color: const Color(0xFF101114),
          child: Stack(
            fit: StackFit.expand,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final plan = canvas.canvasPlan;
                  return Stack(
                    children: [
                      for (var i = 0; i < plan.frames.length; i++)
                        _positionedClip(
                          plan.frames[i],
                          plan.canvas,
                          constraints,
                          i,
                        ),
                      // Match the export-time opaque seam overlay so Studio
                      // preview does not hide a problem the album will show.
                      for (final seam in _seamRects(plan))
                        Positioned(
                          left:
                              seam.x / plan.canvas.width * constraints.maxWidth,
                          top:
                              seam.y /
                              plan.canvas.height *
                              constraints.maxHeight,
                          width:
                              seam.width /
                              plan.canvas.width *
                              constraints.maxWidth,
                          height:
                              seam.height /
                              plan.canvas.height *
                              constraints.maxHeight,
                          child: const ColoredBox(color: Colors.black),
                        ),
                    ],
                  );
                },
              ),
              if (!widget.showChrome && widget.showPlaybackControl)
                Positioned(
                  right: 16,
                  top: 16,
                  child: _PreviewPlaybackButton(controller: canvas),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Positioned _positionedClip(
    CanvasFrame frame,
    CanvasPixelSize canvasSize,
    BoxConstraints constraints,
    int index,
  ) => Positioned(
    left: frame.rect.x / canvasSize.width * constraints.maxWidth,
    top: frame.rect.y / canvasSize.height * constraints.maxHeight,
    width: frame.rect.width / canvasSize.width * constraints.maxWidth,
    height: frame.rect.height / canvasSize.height * constraints.maxHeight,
    child: _ClipSurface(
      player: _players[widget.controller.clips[index].id],
      frame: frame,
      sourceWidth: _orientedWidth(index),
      sourceHeight: _orientedHeight(index),
      selected:
          widget.interactive && widget.controller.activeClipIndex == index,
      onTap: widget.interactive
          ? () => widget.controller.selectClip(index)
          : null,
      onPanUpdate: widget.interactive
          ? (details, scale) => widget.controller.moveCropFocus(
              index,
              details.delta.dx / (_orientedWidth(index) * scale),
              details.delta.dy / (_orientedHeight(index) * scale),
            )
          : null,
    ),
  );

  /// Gutters between frames — same geometry the export OverlayEffect fills.
  List<CanvasRect> _seamRects(AdaptiveCanvasPlan plan) {
    final seams = <CanvasRect>[];
    for (var i = 0; i < plan.frames.length; i++) {
      for (var j = i + 1; j < plan.frames.length; j++) {
        final a = plan.frames[i].rect;
        final b = plan.frames[j].rect;
        final overlapX =
            (a.x + a.width < b.x + b.width ? a.x + a.width : b.x + b.width) -
            (a.x > b.x ? a.x : b.x);
        final overlapY =
            (a.y + a.height < b.y + b.height
                ? a.y + a.height
                : b.y + b.height) -
            (a.y > b.y ? a.y : b.y);
        if (overlapX > 0) {
          final gapTop = a.y + a.height < b.y + b.height
              ? a.y + a.height
              : b.y + b.height;
          final gapBottom = a.y > b.y ? a.y : b.y;
          final gap = gapBottom - gapTop;
          if (gap >= 1 && gap <= 8) {
            seams.add(CanvasRect(a.x > b.x ? a.x : b.x, gapTop, overlapX, gap));
          }
        }
        if (overlapY > 0) {
          final gapLeft = a.x + a.width < b.x + b.width
              ? a.x + a.width
              : b.x + b.width;
          final gapRight = a.x > b.x ? a.x : b.x;
          final gap = gapRight - gapLeft;
          if (gap >= 1 && gap <= 8) {
            seams.add(
              CanvasRect(gapLeft, a.y > b.y ? a.y : b.y, gap, overlapY),
            );
          }
        }
      }
    }
    return seams;
  }

  int _orientedWidth(int index) {
    final asset = widget.controller.clips[index].asset;
    final width = asset.rotation == 90 || asset.rotation == 270
        ? asset.height
        : asset.width;
    return width.clamp(2, 1 << 30);
  }

  int _orientedHeight(int index) {
    final asset = widget.controller.clips[index].asset;
    final height = asset.rotation == 90 || asset.rotation == 270
        ? asset.width
        : asset.height;
    return height.clamp(2, 1 << 30);
  }
}

class _ClipSurface extends StatelessWidget {
  const _ClipSurface({
    required this.player,
    required this.frame,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.selected,
    this.onTap,
    this.onPanUpdate,
  });

  final VideoPlayerController? player;
  final CanvasFrame frame;
  final int sourceWidth;
  final int sourceHeight;
  final bool selected;
  final VoidCallback? onTap;
  final void Function(DragUpdateDetails details, double displayScale)?
  onPanUpdate;

  @override
  Widget build(BuildContext context) {
    final ready = player?.value.isInitialized ?? false;
    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.transparent, Colors.black.withValues(alpha: .08)],
        ),
        border: selected
            ? Border.all(color: const Color(0xFFB8FF5B), width: 1.5)
            : null,
      ),
      child: ready
          ? LayoutBuilder(
              builder: (context, constraints) {
                final cropW = frame.crop.widthPixels < 1
                    ? 1
                    : frame.crop.widthPixels;
                final cropH = frame.crop.heightPixels < 1
                    ? 1
                    : frame.crop.heightPixels;
                final scaleX = constraints.maxWidth / cropW;
                final scaleY = constraints.maxHeight / cropH;
                final scale = scaleX < scaleY ? scaleX : scaleY;
                final originX =
                    (constraints.maxWidth - cropW * scale) / 2 -
                    frame.crop.leftPixels * scale;
                final originY =
                    (constraints.maxHeight - cropH * scale) / 2 -
                    frame.crop.topPixels * scale;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onTap,
                  onPanUpdate: onPanUpdate == null
                      ? null
                      : (details) => onPanUpdate!(details, scale),
                  child: ClipRect(
                    child: Stack(
                      clipBehavior: Clip.hardEdge,
                      children: [
                        Positioned(
                          left: originX,
                          top: originY,
                          width: sourceWidth * scale,
                          height: sourceHeight * scale,
                          child: VideoPlayer(player!),
                        ),
                      ],
                    ),
                  ),
                );
              },
            )
          : const ColoredBox(
              color: Color(0xFF202126),
              child: Center(
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: Colors.white38,
                ),
              ),
            ),
    );
  }
}

class _PreviewPlaybackButton extends StatelessWidget {
  const _PreviewPlaybackButton({required this.controller});

  final MotionCanvasController controller;

  @override
  Widget build(BuildContext context) => IconButton.filledTonal(
    tooltip: controller.isPlaying ? 'Pause' : 'Play',
    onPressed: controller.togglePlayback,
    style: IconButton.styleFrom(
      backgroundColor: Colors.black.withValues(alpha: .42),
      foregroundColor: Colors.white,
    ),
    icon: Icon(
      controller.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
    ),
  );
}
