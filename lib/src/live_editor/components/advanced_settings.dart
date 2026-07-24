import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../localization/app_localizations.dart';
import '../live_editor_scope.dart';

class AdvancedSettings extends StatelessWidget {
  const AdvancedSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final state = LiveEditorScope.of(context);
    final l10n = context.l10n;
    return Theme(
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
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(22)),
          ),
          collapsedShape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(22)),
          ),
          leading: const Icon(Icons.tune_rounded, size: 19),
          title: Text(
            l10n.text('moreSettings'),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
          ),
          subtitle: Text(
            '${l10n.text(state.audioEnabled ? 'soundOn' : 'muted')} · ${l10n.text(state.loopEnabled ? 'loop' : 'once')} · ${state.playbackSpeed.toStringAsFixed(1)}x',
            style: const TextStyle(fontSize: 9, color: AfterFrameColors.muted),
          ),
          children: [
            Row(
              children: [
                Expanded(
                  child: _SettingOption(
                    icon: state.audioEnabled
                        ? Icons.volume_up_rounded
                        : Icons.volume_off_rounded,
                    label: l10n.text('sound'),
                    active: state.audioEnabled,
                    onTap: state.toggleAudio,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SettingOption(
                    icon: Icons.loop_rounded,
                    label: l10n.text('loop'),
                    active: state.loopEnabled,
                    onTap: state.toggleLoop,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SettingOption(
                    icon: Icons.auto_fix_high_rounded,
                    label: l10n.text('enhance'),
                    active: state.enhancementEnabled,
                    onTap: state.toggleEnhancement,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Text(
                  l10n.text('speed'),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                for (final speed in const [.5, 1.0, 1.5, 2.0]) ...[
                  _SpeedOption(
                    value: speed,
                    selected: state.playbackSpeed == speed,
                    onTap: state.setPlaybackSpeed,
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
