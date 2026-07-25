import 'package:flutter/material.dart';

import '../../../localization/app_localizations.dart';
import '../../../theme.dart';
import '../controllers/motion_canvas_controller.dart';
import '../models/motion_canvas_layout.dart';

class CreativeToolDock extends StatelessWidget {
  const CreativeToolDock({super.key, required this.controller});

  final MotionCanvasController controller;

  @override
  Widget build(BuildContext context) {
    final zh = context.l10n.isChinese;
    const icons = [
      Icons.dashboard_customize_outlined,
      Icons.auto_awesome_outlined,
      Icons.blur_on_rounded,
      Icons.music_note_rounded,
      Icons.ios_share_rounded,
    ];
    final labels = zh
        ? ['布局', '风格', '转场', '音乐', '导出']
        : ['Layout', 'Style', 'Transition', 'Music', 'Export'];
    return Column(
      children: [
        SizedBox(
          height: 62,
          child: Row(
            children: [
              for (var i = 0; i < MotionTool.values.length; i++)
                Expanded(
                  child: _ToolButton(
                    icon: icons[i],
                    label: labels[i],
                    selected: controller.activeTool == MotionTool.values[i],
                    onTap: () => controller.selectTool(MotionTool.values[i]),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        AnimatedSwitcher(
          duration: MotionCanvasController.motion,
          switchInCurve: MotionCanvasController.curve,
          switchOutCurve: MotionCanvasController.curve,
          child: _ToolPanel(
            key: ValueKey(controller.activeTool),
            controller: controller,
          ),
        ),
      ],
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkResponse(
    onTap: onTap,
    radius: 30,
    child: AnimatedDefaultTextStyle(
      duration: MotionCanvasController.motion,
      style: TextStyle(
        fontSize: 10,
        color: selected ? Colors.white : AfterFrameColors.muted,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 21,
            color: selected ? AfterFrameColors.lime : AfterFrameColors.muted,
          ),
          const SizedBox(height: 5),
          Text(label),
        ],
      ),
    ),
  );
}

class _ToolPanel extends StatelessWidget {
  const _ToolPanel({super.key, required this.controller});
  final MotionCanvasController controller;

  @override
  Widget build(BuildContext context) {
    final zh = context.l10n.isChinese;
    return SizedBox(
      height: 88,
      child: switch (controller.activeTool) {
        MotionTool.layout => _ChoiceList(
          values: MotionTemplate.values,
          selected: controller.template,
          label: (value) => value.title(zh),
          onTap: controller.applyTemplate,
        ),
        MotionTool.style => _ChoiceList(
          values: MotionStyle.values,
          selected: controller.style,
          label: (value) => switch (value) {
            MotionStyle.cinematic => zh ? '电影' : 'Cinema',
            MotionStyle.film => zh ? '胶片' : 'Film',
            MotionStyle.clean => zh ? '纯净' : 'Clean',
            MotionStyle.dusk => zh ? '暮色' : 'Dusk',
          },
          onTap: controller.setStyle,
        ),
        MotionTool.transition => _ChoiceList(
          values: MotionTransition.values,
          selected: controller.transition,
          label: (value) => switch (value) {
            MotionTransition.softBlurBlend => zh ? '柔焦融合' : 'Soft Blur',
            MotionTransition.softFade => zh ? '柔和淡入' : 'Soft Fade',
            MotionTransition.lightLeak => zh ? '漏光' : 'Light Leak',
            MotionTransition.blur => zh ? '模糊' : 'Blur',
            MotionTransition.filmGrain => zh ? '颗粒' : 'Grain',
          },
          onTap: controller.setTransition,
        ),
        MotionTool.music => Center(
          child: SwitchListTile.adaptive(
            value: controller.musicEnabled,
            onChanged: (_) => controller.toggleMusic(),
            title: Text(zh ? '保留主素材声音' : 'Keep primary audio'),
            subtitle: Text(zh ? '其他音轨自动静音' : 'Other tracks remain muted'),
          ),
        ),
        MotionTool.export => _ChoiceList(
          values: MotionExportFormat.values,
          selected: controller.exportFormat,
          label: (value) => switch (value) {
            MotionExportFormat.motionPhoto => 'Motion Photo',
            MotionExportFormat.mp4 => 'MP4',
            MotionExportFormat.gif => 'GIF',
            MotionExportFormat.webp => 'WebP',
          },
          onTap: controller.setExportFormat,
        ),
      },
    );
  }
}

class _ChoiceList<T> extends StatelessWidget {
  const _ChoiceList({
    required this.values,
    required this.selected,
    required this.label,
    required this.onTap,
  });
  final List<T> values;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onTap;

  @override
  Widget build(BuildContext context) => ListView.separated(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
    itemCount: values.length,
    separatorBuilder: (_, _) => const SizedBox(width: 8),
    itemBuilder: (_, index) {
      final value = values[index];
      final active = value == selected;
      return ChoiceChip(
        label: Text(label(value)),
        selected: active,
        onSelected: (_) => onTap(value),
        showCheckmark: false,
        selectedColor: Colors.white,
        backgroundColor: Colors.white.withValues(alpha: .06),
        labelStyle: TextStyle(
          fontSize: 11,
          color: active ? Colors.black : Colors.white70,
        ),
      );
    },
  );
}
