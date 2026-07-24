import 'package:flutter/material.dart';

import '../../theme.dart';
import '../live_editor_scope.dart';

class AdvancedSettings extends StatelessWidget {
  const AdvancedSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final state = LiveEditorScope.of(context);
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        title: const Text(
          '高级设置',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '声音 · 循环 · ${state.playbackSpeed.toStringAsFixed(1)}x',
          style: const TextStyle(fontSize: 10, color: AfterFrameColors.muted),
        ),
        children: [
          Row(
            children: [
              Expanded(
                child: _SettingOption(
                  icon: state.audioEnabled
                      ? Icons.volume_up_rounded
                      : Icons.volume_off_rounded,
                  label: '保留声音',
                  active: state.audioEnabled,
                  onTap: state.toggleAudio,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SettingOption(
                  icon: Icons.loop_rounded,
                  label: '循环播放',
                  active: state.loopEnabled,
                  onTap: state.toggleLoop,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(
                Icons.speed_rounded,
                size: 18,
                color: AfterFrameColors.muted,
              ),
              const SizedBox(width: 8),
              const Text('播放速度', style: TextStyle(fontSize: 12)),
              const Spacer(),
              DropdownButton<double>(
                value: state.playbackSpeed,
                underline: const SizedBox.shrink(),
                items: const [
                  DropdownMenuItem(value: .5, child: Text('0.5x')),
                  DropdownMenuItem(value: 1, child: Text('1.0x')),
                  DropdownMenuItem(value: 1.5, child: Text('1.5x')),
                  DropdownMenuItem(value: 2, child: Text('2.0x')),
                ],
                onChanged: (value) {
                  if (value != null) state.setPlaybackSpeed(value);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
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
    borderRadius: BorderRadius.circular(14),
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        color: active
            ? AfterFrameColors.lime.withValues(alpha: .12)
            : AfterFrameColors.panelSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: active
              ? AfterFrameColors.lime.withValues(alpha: .45)
              : Colors.transparent,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 18,
            color: active ? AfterFrameColors.lime : AfterFrameColors.muted,
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: active ? Colors.white : AfterFrameColors.muted,
            ),
          ),
        ],
      ),
    ),
  );
}
