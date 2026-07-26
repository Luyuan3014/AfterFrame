import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../theme.dart';
import '../controllers/motion_canvas_controller.dart';
import '../models/motion_canvas_layout.dart';
import '../models/motion_clip.dart';
import '../preview/preview_engine.dart';
import 'transition_engine.dart';

class MotionCanvasRenderer extends StatefulWidget {
  const MotionCanvasRenderer({
    super.key,
    required this.controller,
    this.previewEngine = const Media3PreviewEngine(),
    this.showChrome = true,
  });

  final MotionCanvasController controller;
  final PreviewEngine previewEngine;
  final bool showChrome;

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
  }

  Future<void> _ensurePlayers() async {
    final expected = widget.controller.clips.map((clip) => clip.id).toSet();
    final obsolete = _players.keys
        .where((id) => !expected.contains(id))
        .toList();
    for (final id in obsolete) {
      await _players.remove(id)?.dispose();
    }
    for (final clip in widget.controller.clips) {
      if (_players.containsKey(clip.id)) continue;
      final player = widget.previewEngine.create(clip.asset.uri);
      _players[clip.id] = player;
      try {
        await player.initialize();
        await player.setLooping(false);
        await player.setVolume(clip == widget.controller.clips.first ? 1 : 0);
        await player.seekTo(Duration(milliseconds: clip.trimStartMs));
        player.addListener(_onPlayerTick);
      } catch (_) {
        // A failed source keeps its editorial placeholder without taking down
        // the rest of the canvas.
      }
    }
    if (mounted) setState(() {});
  }

  void _onCanvasChanged() {
    if (!mounted) return;
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
        final expected = clip.trimStartMs + widget.controller.positionMs;
        if ((player.value.position.inMilliseconds - expected).abs() > 110) {
          await player.seekTo(Duration(milliseconds: expected));
        }
        if (widget.controller.isPlaying && !player.value.isPlaying) {
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
                  final contentSlots = canvas.contentSlots;
                  return Stack(
                    children: [
                      for (var i = 0; i < contentSlots.length; i++)
                        _positionedClip(
                          contentSlots[i],
                          constraints,
                          _ClipSurface(
                            clip: canvas.clips[i],
                            player: _players[canvas.clips[i].id],
                            interactive: widget.showChrome,
                            selected:
                                widget.showChrome &&
                                i == canvas.activeClipIndex,
                            onTap: () => canvas.selectClip(i),
                            onDoubleTap: () => canvas.resetClipFocus(i),
                            onMove: (delta) =>
                                canvas.moveClipFocus(i, delta.dx, delta.dy),
                          ),
                        ),
                    ],
                  );
                },
              ),
              TransitionEngine(
                transition: canvas.transition,
                progress: canvas.positionMs / canvas.durationMs,
                child: const SizedBox.expand(),
              ),
              if (widget.showChrome)
                Positioned(
                  left: 16,
                  bottom: 14,
                  child: Row(
                    children: [
                      Icon(
                        canvas.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: 17,
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'DRAG TO POSITION',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              if (!widget.showChrome)
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
    CanvasSlot slot,
    BoxConstraints constraints,
    Widget child,
  ) => Positioned(
    left: slot.x * constraints.maxWidth,
    top: slot.y * constraints.maxHeight,
    width: slot.width * constraints.maxWidth,
    height: slot.height * constraints.maxHeight,
    child: child,
  );
}

class _ClipSurface extends StatelessWidget {
  const _ClipSurface({
    required this.clip,
    required this.player,
    required this.interactive,
    required this.selected,
    required this.onTap,
    required this.onDoubleTap,
    required this.onMove,
  });

  final MotionClip clip;
  final VideoPlayerController? player;
  final bool interactive;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final ValueChanged<Offset> onMove;

  @override
  Widget build(BuildContext context) {
    final ready = player?.value.isInitialized ?? false;
    return LayoutBuilder(
      builder: (context, constraints) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: interactive ? onTap : null,
        onDoubleTap: interactive ? onDoubleTap : null,
        onPanUpdate: interactive
            ? (details) => onMove(
                Offset(
                  details.delta.dx / constraints.maxWidth,
                  details.delta.dy / constraints.maxHeight,
                ),
              )
            : null,
        child: AnimatedContainer(
          duration: MotionCanvasController.motion,
          curve: MotionCanvasController.curve,
          foregroundDecoration: BoxDecoration(
            border: selected
                ? Border.all(color: AfterFrameColors.lime, width: 1.5)
                : null,
            gradient: LinearGradient(
              colors: [Colors.transparent, Colors.black.withValues(alpha: .08)],
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AfterFrameColors.lime.withValues(alpha: .12),
                      blurRadius: 28,
                    ),
                  ]
                : const [],
          ),
          child: ready
              ? ClipRect(
                  child: FittedBox(
                    fit: BoxFit.contain,
                    alignment: Alignment(
                      clip.focus.x * 2 - 1,
                      clip.focus.y * 2 - 1,
                    ),
                    child: SizedBox(
                      width: player!.value.size.width,
                      height: player!.value.size.height,
                      child: VideoPlayer(player!),
                    ),
                  ),
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
