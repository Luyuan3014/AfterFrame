import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../theme.dart';
import '../controllers/motion_canvas_controller.dart';
import '../models/motion_clip.dart';
import 'transition_engine.dart';

class MotionCanvasRenderer extends StatefulWidget {
  const MotionCanvasRenderer({super.key, required this.controller});

  final MotionCanvasController controller;

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

  VideoPlayerController _createPlayer(String source) {
    final uri = Uri.parse(source);
    if (uri.scheme == 'content') return VideoPlayerController.contentUri(uri);
    if (uri.scheme == 'http' || uri.scheme == 'https') {
      return VideoPlayerController.networkUrl(uri);
    }
    return VideoPlayerController.file(
      File(uri.scheme == 'file' ? uri.toFilePath() : source),
    );
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
      final player = _createPlayer(clip.asset.uri);
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
    final activePlayer = _players[canvas.activeClip.id];
    return Semantics(
      label: 'Motion Canvas preview',
      button: true,
      child: GestureDetector(
        onTap: canvas.togglePlayback,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(canvas.layout.cornerRadius),
          clipBehavior: Clip.antiAlias,
          child: ColoredBox(
            color: const Color(0xFF0B0B0D),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (activePlayer?.value.isInitialized ?? false)
                  Transform.scale(
                    scale: 1.3,
                    child: ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                      child: Opacity(
                        opacity: .3,
                        child: VideoPlayer(activePlayer!),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    children: [
                      for (var i = 0; i < canvas.clips.length; i++)
                        Expanded(
                          flex: canvas.layout
                              .heightFor(canvas.clips[i].asset.aspectRatio)
                              .round(),
                          child: Transform.translate(
                            offset: Offset(
                              0,
                              i == 0 ? 0 : -canvas.layout.overlap / 2,
                            ),
                            child: _ClipSurface(
                              clip: canvas.clips[i],
                              player: _players[canvas.clips[i].id],
                              selected: i == canvas.activeClipIndex,
                              onTap: () => canvas.selectClip(i),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                TransitionEngine(
                  transition: canvas.transition,
                  progress: canvas.positionMs / canvas.durationMs,
                  child: const SizedBox.expand(),
                ),
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
                        'MOTION CANVAS',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
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

class _ClipSurface extends StatelessWidget {
  const _ClipSurface({
    required this.clip,
    required this.player,
    required this.selected,
    required this.onTap,
  });

  final MotionClip clip;
  final VideoPlayerController? player;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ready = player?.value.isInitialized ?? false;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: MotionCanvasController.motion,
        curve: MotionCanvasController.curve,
        foregroundDecoration: BoxDecoration(
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
                  fit: BoxFit.cover,
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
    );
  }
}
