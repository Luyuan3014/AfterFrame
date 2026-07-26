import 'dart:ui';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../live_editor/formatters.dart';
import '../../../localization/app_localizations.dart';
import '../../../theme.dart';
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
    builder: (context, _) => Padding(
      padding: fullscreen
          ? const EdgeInsets.symmetric(horizontal: 8)
          : const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Center(
        child: Container(
          constraints: BoxConstraints(
            maxHeight: fullscreen ? MediaQuery.sizeOf(context).height : 430,
          ),
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
          child: AspectRatio(
            aspectRatio: controller.layout.aspectRatio,
            child: Stack(
              fit: StackFit.expand,
              children: [
                MotionCanvasRenderer(
                  controller: controller,
                  showChrome: false,
                  playbackEnabled: active,
                  showPlaybackControl: false,
                ),
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
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        color: Colors.black.withValues(alpha: .42),
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
                              context.l10n
                                  .text('collagePreviewBadge')
                                  .toUpperCase(),
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
                  ),
                ),
                if (!fullscreen && onFullscreen != null)
                  Positioned(
                    right: 12,
                    top: 12,
                    child: IconButton.filled(
                      tooltip: '全屏预览',
                      onPressed: onFullscreen,
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black45,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.open_in_full_rounded, size: 18),
                    ),
                  ),
                Positioned(
                  left: 18,
                  right: 18,
                  bottom: 14,
                  child: _CanvasTimeline(controller: controller),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// Collage-specific media selection, presented with the same cover, timeline,
/// advanced-settings, and generate order as Live single-frame.
class StudioCanvasTools extends StatelessWidget {
  const StudioCanvasTools({
    super.key,
    required this.controller,
    required this.onEditClip,
  });

  final MotionCanvasController controller;
  final ValueChanged<int> onEditClip;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CanvasCoverSelector(controller: controller),
        const SizedBox(height: 30),
        _CanvasClipTimeline(controller: controller, onEditClip: onEditClip),
        const SizedBox(height: 24),
        _CanvasAdvancedSettings(controller: controller),
      ],
    ),
  );
}

class _CanvasCoverSelector extends StatelessWidget {
  const _CanvasCoverSelector({required this.controller});
  final MotionCanvasController controller;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.text('coverMoment'),
                  style: const TextStyle(
                    color: AfterFrameColors.lime,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.6,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  context.l10n.text('chooseCover'),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Text(
            formatEditorTime(controller.positionMs),
            style: const TextStyle(
              color: AfterFrameColors.lime,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
      const SizedBox(height: 13),
      Container(
        height: 72,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .22),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AfterFrameColors.glassBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Row(
              children: [
                for (final clip in controller.clips)
                  Expanded(
                    child: clip.thumbnailPath == null
                        ? const ColoredBox(color: Color(0xFF202126))
                        : Image.file(
                            File(clip.thumbnailPath!),
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) =>
                                const ColoredBox(color: Color(0xFF202126)),
                          ),
                  ),
              ],
            ),
            ColoredBox(color: Colors.black.withValues(alpha: .18)),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 0,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
                thumbColor: AfterFrameColors.lime,
                overlayColor: AfterFrameColors.lime.withValues(alpha: .14),
              ),
              child: Slider(
                min: 0,
                max: controller.durationMs.toDouble(),
                value: controller.positionMs.toDouble(),
                onChanged: (value) => controller.setPosition(value.round()),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _CanvasClipTimeline extends StatelessWidget {
  const _CanvasClipTimeline({
    required this.controller,
    required this.onEditClip,
  });
  final MotionCanvasController controller;
  final ValueChanged<int> onEditClip;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        context.l10n.text('momentTimeline'),
        style: const TextStyle(
          color: AfterFrameColors.lime,
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.6,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        context.l10n.text('findMoment'),
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 11),
      Row(
        children: [
          Expanded(
            child: _Metric(
              label: context.l10n.text('currentTime'),
              value: formatEditorTime(controller.positionMs),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _Metric(
              label: context.l10n.text('liveLength'),
              value: formatEditorTime(controller.durationMs),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      MotionClipTrack(controller: controller, onEdit: onEditClip),
      const SizedBox(height: 7),
      Text(
        context.l10n.text('collageTrackHint'),
        style: const TextStyle(fontSize: 10, color: AfterFrameColors.muted),
      ),
    ],
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

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: .18),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AfterFrameColors.glassBorder),
    ),
    child: Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 8,
            color: AfterFrameColors.muted,
            fontWeight: FontWeight.w700,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
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

class _CanvasTimeline extends StatelessWidget {
  const _CanvasTimeline({required this.controller});
  final MotionCanvasController controller;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      IconButton.filledTonal(
        visualDensity: VisualDensity.compact,
        onPressed: controller.togglePlayback,
        icon: Icon(
          controller.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
        ),
      ),
      Expanded(
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
            activeTrackColor: AfterFrameColors.lime,
            inactiveTrackColor: Colors.white24,
            thumbColor: AfterFrameColors.lime,
          ),
          child: Slider(
            value: controller.positionMs.toDouble(),
            max: controller.durationMs.toDouble(),
            onChanged: (value) => controller.setPosition(value.round()),
          ),
        ),
      ),
      Text(
        '${(controller.positionMs / 1000).toStringAsFixed(1)}s',
        style: const TextStyle(
          fontSize: 10,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    ],
  );
}
