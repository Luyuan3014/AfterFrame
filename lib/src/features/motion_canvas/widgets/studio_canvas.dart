import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../live_editor/formatters.dart';
import '../../../localization/app_localizations.dart';
import '../../../theme.dart';
import '../../../widgets/live_playback_scale.dart';
import '../controllers/motion_canvas_controller.dart';
import '../renderer/motion_canvas_renderer.dart';
import 'clip_track.dart';

/// Live collage preview using the same card hierarchy as Live single-frame.
class StudioCanvasPreview extends StatelessWidget {
  const StudioCanvasPreview({
    super.key,
    required this.controller,
    this.fullscreen = false,
    this.active = true,
    this.onFullscreen,
  });

  final MotionCanvasController controller;
  final bool fullscreen;
  final bool active;
  final VoidCallback? onFullscreen;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final plan = controller.canvasPlan;
      final maxHeight = fullscreen ? MediaQuery.sizeOf(context).height : 430.0;
      return Padding(
        padding: fullscreen
            ? const EdgeInsets.symmetric(horizontal: 8)
            : const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Fill the card like Live single-frame: use the real canvas ratio
            // and take the largest rect that fits width × maxHeight.
            final maxWidth = constraints.maxWidth;
            var width = maxWidth;
            var height = width / plan.canvas.aspectRatio;
            if (height > maxHeight) {
              height = maxHeight;
              width = height * plan.canvas.aspectRatio;
            }
            return Center(
              child: Container(
                width: width,
                height: height,
                decoration: BoxDecoration(
                  color: const Color(0xFF111216),
                  borderRadius: BorderRadius.circular(fullscreen ? 20 : 32),
                  border: fullscreen ? null : Border.all(color: Colors.white10),
                  boxShadow: fullscreen
                      ? null
                      : const [
                          BoxShadow(
                            color: Color(0x73000000),
                            blurRadius: 36,
                            offset: Offset(0, 20),
                          ),
                        ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    LivePlaybackScale(
                      playing: controller.isPlaying,
                      child: MotionCanvasRenderer(
                        controller: controller,
                        showChrome: false,
                        playbackEnabled: active,
                        showPlaybackControl: false,
                        interactive: !fullscreen,
                      ),
                    ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Color(0x26000000),
                            Colors.transparent,
                            Color(0x3D000000),
                          ],
                          stops: [0, .55, 1],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                    Positioned(
                      left: 16,
                      top: 16,
                      child: _CanvasLiveBadge(
                        count: controller.clips.length,
                        playing: controller.isPlaying,
                      ),
                    ),
                    if (!fullscreen && onFullscreen != null)
                      Positioned(
                        right: 12,
                        top: 12,
                        child: IconButton.filled(
                          tooltip: context.l10n.text('fullscreenPreview'),
                          onPressed: onFullscreen,
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.black45,
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(
                            Icons.open_in_full_rounded,
                            size: 18,
                          ),
                        ),
                      ),
                    Positioned(
                      left: 14,
                      bottom: 14,
                      child: _CanvasPlayButton(
                        playing: controller.isPlaying,
                        onTap: controller.togglePlayback,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    },
  );
}

/// Multi-source editing: source rail, this clip's cover, then shared settings.
class StudioCanvasTools extends StatelessWidget {
  const StudioCanvasTools({
    super.key,
    required this.controller,
    required this.onEditClip,
    required this.onRemoveClip,
    this.onAddClip,
  });

  final MotionCanvasController controller;
  final ValueChanged<int> onEditClip;
  final ValueChanged<int> onRemoveClip;
  final VoidCallback? onAddClip;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final clip = controller.activeClip;
      final minMs = clip.trimStartMs.toDouble();
      final maxMs = clip.trimEndMs
          .toDouble()
          .clamp(minMs + 1, double.infinity)
          .toDouble();
      final coverMs = clip.resolvedCoverMs
          .toDouble()
          .clamp(minMs, maxMs)
          .toDouble();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.text('sourcesTitle'),
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          MotionClipTrack(
            controller: controller,
            onRemove: onRemoveClip,
            onAdd: onAddClip,
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: Text(
                  context.l10n.text('clipCover'),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                formatEditorTime(clip.resolvedCoverMs),
                style: const TextStyle(
                  color: AfterFrameColors.lime,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => onEditClip(controller.activeClipIndex),
                child: Text(context.l10n.text('trimClip')),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AfterFrameColors.lime.withValues(alpha: .78),
              inactiveTrackColor: Colors.white12,
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
              thumbColor: AfterFrameColors.lime,
              overlayColor: AfterFrameColors.lime.withValues(alpha: .12),
            ),
            child: Slider(
              min: minMs,
              max: maxMs,
              value: coverMs,
              onChanged: (value) => controller.setClipCover(
                controller.activeClipIndex,
                value.round(),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _CanvasAdvancedSettings(controller: controller),
        ],
      );
    },
  );
}

class _CanvasAdvancedSettings extends StatelessWidget {
  const _CanvasAdvancedSettings({required this.controller});
  final MotionCanvasController controller;

  @override
  Widget build(BuildContext context) => Theme(
    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
    child: Container(
      decoration: BoxDecoration(
        color: AfterFrameColors.glassSoft,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AfterFrameColors.glassBorder),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 2),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 15),
        iconColor: AfterFrameColors.lime,
        collapsedIconColor: AfterFrameColors.muted,
        leading: const Icon(Icons.tune_rounded, size: 19),
        title: Text(
          context.l10n.text('moreSettings'),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          '${context.l10n.text(controller.audioEnabled ? 'soundOn' : 'muted')} · ${context.l10n.text(controller.loopEnabled ? 'loop' : 'once')} · ${controller.playbackSpeed.toStringAsFixed(1)}x',
          style: const TextStyle(fontSize: 9, color: AfterFrameColors.muted),
        ),
        children: [
          Row(
            children: [
              Expanded(
                child: _SettingOption(
                  icon: controller.audioEnabled
                      ? Icons.volume_up_rounded
                      : Icons.volume_off_rounded,
                  label: context.l10n.text('sound'),
                  active: controller.audioEnabled,
                  onTap: controller.toggleAudio,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SettingOption(
                  icon: Icons.loop_rounded,
                  label: context.l10n.text('loop'),
                  active: controller.loopEnabled,
                  onTap: controller.toggleLoop,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SettingOption(
                  icon: Icons.auto_fix_high_rounded,
                  label: context.l10n.text('enhance'),
                  active: controller.enhancementEnabled,
                  onTap: controller.toggleEnhancement,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Text(
                context.l10n.text('speed'),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              for (final speed in const [.5, 1.0, 1.5, 2.0]) ...[
                _SpeedOption(
                  value: speed,
                  selected: controller.playbackSpeed == speed,
                  onTap: controller.setPlaybackSpeed,
                ),
                if (speed != 2.0) const SizedBox(width: 5),
              ],
            ],
          ),
        ],
      ),
    ),
  );
}

class _SettingOption extends StatelessWidget {
  const _SettingOption({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(15),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 190),
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        color: active
            ? AfterFrameColors.lime.withValues(alpha: .1)
            : Colors.black.withValues(alpha: .18),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: active
              ? AfterFrameColors.lime.withValues(alpha: .42)
              : Colors.transparent,
        ),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            size: 17,
            color: active ? AfterFrameColors.lime : AfterFrameColors.muted,
          ),
          const SizedBox(height: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: active ? Colors.white : AfterFrameColors.muted,
            ),
          ),
        ],
      ),
    ),
  );
}

class _SpeedOption extends StatelessWidget {
  const _SpeedOption({
    required this.value,
    required this.selected,
    required this.onTap,
  });
  final double value;
  final bool selected;
  final ValueChanged<double> onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => onTap(value),
    borderRadius: BorderRadius.circular(12),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: selected
            ? AfterFrameColors.lime
            : Colors.black.withValues(alpha: .2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '${value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1)}x',
        style: TextStyle(
          color: selected ? AfterFrameColors.ink : AfterFrameColors.muted,
          fontSize: 9,
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
  );
}

class _CanvasLiveBadge extends StatelessWidget {
  const _CanvasLiveBadge({required this.count, required this.playing});

  final int count;
  final bool playing;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(99),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: playing ? .52 : .42),
          border: Border.all(
            color: playing
                ? AfterFrameColors.lime.withValues(alpha: .7)
                : Colors.transparent,
          ),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.motion_photos_on_rounded,
              size: 14,
              color: AfterFrameColors.lime,
            ),
            const SizedBox(width: 6),
            Text(
              playing
                  ? 'LIVE'
                  : context.l10n.text('canvasPreviewBadge', {'count': count}),
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.1,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _CanvasPlayButton extends StatelessWidget {
  const _CanvasPlayButton({required this.playing, required this.onTap});

  final bool playing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: context.l10n.text(playing ? 'pauseLive' : 'playLive'),
    child: IconButton.filledTonal(
      tooltip: context.l10n.text(playing ? 'pauseLive' : 'playLive'),
      onPressed: onTap,
      style: IconButton.styleFrom(
        backgroundColor: Colors.black.withValues(alpha: .46),
        foregroundColor: Colors.white,
      ),
      icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
    ),
  );
}
