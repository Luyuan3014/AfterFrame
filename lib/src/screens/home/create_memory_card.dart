import 'package:flutter/material.dart';

import '../../localization/app_localizations.dart';
import '../../theme.dart';

class CreateMemoryCard extends StatelessWidget {
  const CreateMemoryCard({
    super.key,
    required this.onTap,
    required this.loading,
  });

  final VoidCallback onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Semantics(
      button: true,
      label: l10n.text('importVideo'),
      child: Material(
        color: AfterFrameColors.paper,
        borderRadius: BorderRadius.circular(AfterFrameRadius.xl),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const Key('create-hero'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(AfterFrameRadius.xl),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AfterFrameRadius.xl),
              gradient: const LinearGradient(
                colors: [Color(0xFFF7F4EC), Color(0xFFD5E4C8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Stack(
              children: [
                const Positioned(
                  right: -36,
                  bottom: -48,
                  child: IgnorePointer(child: _CardAperture()),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AfterFrameSpace.s24,
                    AfterFrameSpace.s20,
                    AfterFrameSpace.s24,
                    AfterFrameSpace.s20,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          l10n.text('newMemory'),
                          style: const TextStyle(
                            fontSize: 10,
                            letterSpacing: 1.6,
                            fontWeight: FontWeight.w800,
                            color: AfterFrameColors.paper,
                          ),
                        ),
                      ),
                      const SizedBox(height: AfterFrameSpace.s24),
                      Text(
                        l10n.text('startFromVideo'),
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 32,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -1.2,
                          height: 1.05,
                        ),
                      ),
                      const SizedBox(height: AfterFrameSpace.s8),
                      Text(
                        l10n.text('startFromVideoDetail'),
                        style: const TextStyle(
                          color: Color(0xFF5A5F57),
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: AfterFrameSpace.s20),
                      _ImportButton(
                        loading: loading,
                        label: l10n.text('importVideo'),
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

class _ImportButton extends StatelessWidget {
  const _ImportButton({required this.loading, required this.label});

  final bool loading;
  final String label;

  static const _height = 48.0;
  static const _badge = 34.0;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('import-video-button'),
    height: _height,
    // Hugs its label instead of stretching across the card, so the accent
    // colour stays a button rather than a banner.
    padding: const EdgeInsets.only(left: 22, right: (_height - _badge) / 2),
    decoration: BoxDecoration(
      color: AfterFrameColors.lime,
      borderRadius: BorderRadius.circular(_height / 2),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.black,
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(width: AfterFrameSpace.s12),
        // A dark disc on lime restates the aperture in the AfterFrame mark.
        Container(
          width: _badge,
          height: _badge,
          decoration: const BoxDecoration(
            color: AfterFrameColors.ink,
            shape: BoxShape.circle,
          ),
          child: loading
              ? const Padding(
                  padding: EdgeInsets.all(9),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AfterFrameColors.lime,
                  ),
                )
              : const Icon(
                  Icons.arrow_forward_rounded,
                  size: 18,
                  color: AfterFrameColors.lime,
                ),
        ),
      ],
    ),
  );
}

class _CardAperture extends StatelessWidget {
  const _CardAperture();

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 180,
    height: 180,
    child: CustomPaint(painter: _CardAperturePainter()),
  );
}

class _CardAperturePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * .58, size.height * .58);
    for (var i = 0; i < 3; i++) {
      canvas.drawCircle(
        center,
        28.0 + i * 26,
        Paint()
          ..color = Colors.black.withValues(alpha: .05 - i * .008)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }
    canvas.drawCircle(
      center + const Offset(-42, 18),
      10,
      Paint()
        ..color = Colors.black.withValues(alpha: .04)
        ..style = PaintingStyle.stroke
        ..strokeWidth = .9,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
