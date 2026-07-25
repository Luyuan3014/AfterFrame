import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../localization/app_localizations.dart';
import '../../theme.dart';
import '../live_editor_scope.dart';
import '../models/live_editor_state.dart';

class LivePreviewCard extends StatefulWidget {
  const LivePreviewCard({super.key});

  @override
  State<LivePreviewCard> createState() => _LivePreviewCardState();
}

class _LivePreviewCardState extends State<LivePreviewCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  VideoPlayerController? _controller;
  String? _activeUri;
  Object? _previewError;
  bool _initializing = false;
  bool _handlingRangeEnd = false;
  bool _lastPlaying = false;
  int _lastReportedMs = -1000;
  int? _lastCoverFrame;
  int? _lastStartTime;
  int? _lastEndTime;
  bool? _lastAudioEnabled;
  double? _lastSpeed;
  LiveEditorState? _editorState;
  bool? _reduceMotion;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = LiveEditorScope.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion != reduceMotion) {
      _reduceMotion = reduceMotion;
      if (reduceMotion) {
        _breath.stop();
        _breath.value = 1;
      } else {
        _breath.repeat(reverse: true);
      }
    }
    _editorState = state;
    if (_activeUri != state.videoPath) {
      unawaited(_initialize(state));
      return;
    }
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    if (_lastAudioEnabled != state.audioEnabled) {
      _lastAudioEnabled = state.audioEnabled;
      unawaited(controller.setVolume(state.audioEnabled ? 1 : 0));
    }
    if (_lastSpeed != state.playbackSpeed) {
      _lastSpeed = state.playbackSpeed;
      unawaited(controller.setPlaybackSpeed(state.playbackSpeed));
    }
    if (_lastCoverFrame != state.coverFrame && !controller.value.isPlaying) {
      _lastCoverFrame = state.coverFrame;
      unawaited(controller.seekTo(Duration(milliseconds: state.coverFrame)));
    }
    if (_lastStartTime != state.startTime || _lastEndTime != state.endTime) {
      _lastStartTime = state.startTime;
      _lastEndTime = state.endTime;
      final position = controller.value.position.inMilliseconds;
      if (position < state.startTime || position > state.endTime) {
        unawaited(controller.seekTo(Duration(milliseconds: state.startTime)));
      }
    }
  }

  Future<void> _initialize(LiveEditorState state) async {
    final uri = state.videoPath;
    _activeUri = uri;
    _previewError = null;
    _initializing = true;
    if (mounted) setState(() {});

    final previous = _controller;
    _controller = null;
    if (previous != null) {
      previous.removeListener(_onPlayerChanged);
      await previous.dispose();
    }

    final parsed = Uri.parse(uri);
    final controller = parsed.scheme == 'content'
        ? VideoPlayerController.contentUri(parsed)
        : parsed.scheme == 'http' || parsed.scheme == 'https'
        ? VideoPlayerController.networkUrl(parsed)
        : VideoPlayerController.file(
            File(parsed.scheme == 'file' ? parsed.toFilePath() : uri),
          );
    _controller = controller;
    try {
      await controller.initialize();
      if (!mounted || _activeUri != uri) {
        await controller.dispose();
        return;
      }
      await controller.setLooping(false);
      await controller.setVolume(state.audioEnabled ? 1 : 0);
      await controller.setPlaybackSpeed(state.playbackSpeed);
      await controller.seekTo(Duration(milliseconds: state.coverFrame));
      _lastAudioEnabled = state.audioEnabled;
      _lastSpeed = state.playbackSpeed;
      _lastCoverFrame = state.coverFrame;
      _lastStartTime = state.startTime;
      _lastEndTime = state.endTime;
      _lastPlaying = false;
      controller.addListener(_onPlayerChanged);
    } catch (error) {
      _previewError = error;
    } finally {
      if (mounted && _activeUri == uri) {
        setState(() => _initializing = false);
      }
    }
  }

  void _onPlayerChanged() {
    if (!mounted) return;
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final state = _editorState;
    if (state == null) return;
    final value = controller.value;
    final positionMs = value.position.inMilliseconds;

    if (value.isPlaying &&
        positionMs >= state.endTime - 35 &&
        !_handlingRangeEnd) {
      _handlingRangeEnd = true;
      unawaited(_finishRange(state));
      return;
    }
    if ((positionMs - _lastReportedMs).abs() >= 100) {
      _lastReportedMs = positionMs;
      state.setCurrentPosition(positionMs);
    }
    if (_lastPlaying != value.isPlaying) {
      _lastPlaying = value.isPlaying;
      setState(() {});
    }
  }

  Future<void> _finishRange(LiveEditorState state) async {
    final controller = _controller;
    if (controller == null) return;
    try {
      if (state.loopEnabled) {
        await controller.seekTo(Duration(milliseconds: state.startTime));
        await controller.play();
      } else {
        await controller.pause();
        await controller.seekTo(Duration(milliseconds: state.endTime));
        state.setCurrentPosition(state.endTime);
      }
    } finally {
      _handlingRangeEnd = false;
    }
  }

  Future<void> _togglePlayback() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final state = LiveEditorScope.of(context);
    if (controller.value.isPlaying) {
      await controller.pause();
      return;
    }
    final position = controller.value.position.inMilliseconds;
    if (position < state.startTime || position >= state.endTime - 35) {
      await controller.seekTo(Duration(milliseconds: state.startTime));
    }
    await controller.play();
  }

  @override
  void dispose() {
    _breath.dispose();
    final controller = _controller;
    if (controller != null) {
      controller.removeListener(_onPlayerChanged);
      unawaited(controller.dispose());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = LiveEditorScope.of(context);
    final cover = state.selectedCover;
    final controller = _controller;
    final ready = controller?.value.isInitialized ?? false;
    final playing = ready && controller!.value.isPlaying;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxHeight: 430),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(32),
            boxShadow: const [
              BoxShadow(
                color: Color(0x73000000),
                blurRadius: 36,
                offset: Offset(0, 20),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: AspectRatio(
              aspectRatio: state.asset.aspectRatio.clamp(.62, 1.35).toDouble(),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (cover != null)
                    Image.file(File(cover.path), fit: BoxFit.cover),
                  if (controller != null && controller.value.isInitialized)
                    _CoverVideo(controller: controller),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Color(0x26000000),
                          Colors.transparent,
                          Color(0x52000000),
                        ],
                        stops: [0, .48, 1],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 16,
                    top: 16,
                    child: _LiveBadge(animation: _breath),
                  ),
                  Center(
                    child: _PreviewButton(
                      ready: ready,
                      playing: playing,
                      loading: _initializing,
                      failed: _previewError != null,
                      onTap: _togglePlayback,
                    ),
                  ),
                  Positioned(
                    left: 18,
                    right: 18,
                    bottom: 14,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _previewError != null
                              ? context.l10n.text('previewFailed')
                              : _initializing
                              ? context.l10n.text('previewLoading')
                              : context.l10n.text('livingMoment'),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .76),
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            letterSpacing: .5,
                          ),
                        ),
                        if (controller != null &&
                            controller.value.isInitialized) ...[
                          const SizedBox(height: 7),
                          VideoProgressIndicator(
                            controller,
                            allowScrubbing: true,
                            padding: EdgeInsets.zero,
                            colors: const VideoProgressColors(
                              playedColor: AfterFrameColors.lime,
                              bufferedColor: Colors.white30,
                              backgroundColor: Colors.white12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CoverVideo extends StatelessWidget {
  const _CoverVideo({required this.controller});

  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.cover,
    clipBehavior: Clip.hardEdge,
    child: SizedBox(
      width: controller.value.size.width,
      height: controller.value.size.height,
      child: VideoPlayer(controller),
    ),
  );
}

class _PreviewButton extends StatelessWidget {
  const _PreviewButton({
    required this.ready,
    required this.playing,
    required this.loading,
    required this.failed,
    required this.onTap,
  });

  final bool ready;
  final bool playing;
  final bool loading;
  final bool failed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ClipOval(
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
      child: Material(
        color: Colors.black.withValues(alpha: .34),
        child: InkWell(
          onTap: ready ? onTap : null,
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: .34)),
            ),
            child: loading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Icon(
                    failed
                        ? Icons.error_outline_rounded
                        : playing
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    size: 23,
                  ),
          ),
        ),
      ),
    ),
  );
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: animation,
    builder: (_, child) => Opacity(
      opacity: .72 + animation.value * .28,
      child: Transform.scale(scale: .98 + animation.value * .02, child: child),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: .38),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: .2)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.motion_photos_on_rounded,
                size: 14,
                color: AfterFrameColors.lime,
              ),
              SizedBox(width: 6),
              Text(
                'AFTER LIVE',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
