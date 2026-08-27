import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../localization/app_localizations.dart';
import '../../theme.dart';
import '../video_picker_screen.dart';

/// Geometry shared by the steps and the hairline that links them, so the
/// connector always runs through the middle of the icon discs.
const _stepPadding = AfterFrameSpace.s8;
const _stepIconSize = 44.0;
const _connectorThickness = 1.0;
const _connectorTop =
    _stepPadding + _stepIconSize / 2 - _connectorThickness / 2;

class CreationFlow extends StatelessWidget {
  const CreationFlow({super.key, required this.onStep});

  final ValueChanged<VideoLibraryFilter> onStep;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _FlowStep(
            key: const Key('creation-flow-video'),
            icon: Icons.videocam_rounded,
            title: l10n.text('createSignalVideo'),
            detail: l10n.text('createSignalVideoDetail'),
            onTap: () => onStep(VideoLibraryFilter.video),
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(top: _connectorTop),
          child: _FlowConnector(),
        ),
        Expanded(
          child: _FlowStep(
            key: const Key('creation-flow-live'),
            icon: Icons.motion_photos_on_rounded,
            title: l10n.text('createSignalLive'),
            detail: l10n.text('createSignalLiveDetail'),
            onTap: () => onStep(VideoLibraryFilter.live),
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(top: _connectorTop),
          child: _FlowConnector(),
        ),
        Expanded(
          child: _FlowStep(
            key: const Key('creation-flow-collage'),
            icon: Icons.grid_view_rounded,
            title: l10n.text('createSignalCollage'),
            detail: l10n.text('createSignalCollageDetail'),
            onTap: () => onStep(VideoLibraryFilter.all),
          ),
        ),
      ],
    );
  }
}

class _FlowConnector extends StatelessWidget {
  const _FlowConnector();

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 22,
    height: _connectorThickness,
    child: DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AfterFrameColors.lime.withValues(alpha: .08),
            AfterFrameColors.lime.withValues(alpha: .28),
            AfterFrameColors.lime.withValues(alpha: .08),
          ],
        ),
      ),
    ),
  );
}

class _FlowStep extends StatefulWidget {
  const _FlowStep({
    super.key,
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback onTap;

  @override
  State<_FlowStep> createState() => _FlowStepState();
}

class _FlowStepState extends State<_FlowStep> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    // The discs carry the brand lime at rest so the row reads as AfterFrame's
    // own flow; pressing only lifts the same colour.
    final accent = AfterFrameColors.lime.withValues(alpha: _pressed ? 1 : .85);
    return Semantics(
      button: true,
      label: '${widget.title}，${widget.detail}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            widget.onTap();
          },
          onHighlightChanged: (value) => setState(() => _pressed = value),
          borderRadius: BorderRadius.circular(AfterFrameRadius.md),
          splashColor: AfterFrameColors.lime.withValues(alpha: .08),
          highlightColor: AfterFrameColors.lime.withValues(alpha: .04),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AfterFrameSpace.s4,
              vertical: _stepPadding,
            ),
            child: Column(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: _stepIconSize,
                  height: _stepIconSize,
                  decoration: BoxDecoration(
                    color: Color.alphaBlend(
                      AfterFrameColors.lime.withValues(
                        alpha: _pressed ? .22 : .12,
                      ),
                      AfterFrameColors.elevated,
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AfterFrameColors.lime.withValues(
                        alpha: _pressed ? .5 : .24,
                      ),
                    ),
                    boxShadow: _pressed
                        ? [
                            BoxShadow(
                              color: AfterFrameColors.lime.withValues(
                                alpha: .16,
                              ),
                              blurRadius: 16,
                            ),
                          ]
                        : null,
                  ),
                  child: Icon(widget.icon, size: 20, color: accent),
                ),
                const SizedBox(height: AfterFrameSpace.s12),
                Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AfterFrameColors.textPrimary,
                  ),
                ),
                const SizedBox(height: AfterFrameSpace.s4),
                Text(
                  widget.detail,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AfterFrameColors.textTertiary,
                    fontSize: 11,
                    height: 1.35,
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
