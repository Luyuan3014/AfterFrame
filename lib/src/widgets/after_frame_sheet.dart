import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

Future<T?> showAfterFrameSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isDismissible = true,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  isDismissible: isDismissible,
  showDragHandle: false,
  backgroundColor: Colors.transparent,
  barrierColor: Colors.black.withValues(alpha: .72),
  builder: builder,
);

class AfterFrameSheet extends StatelessWidget {
  const AfterFrameSheet({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
    this.eyebrow = 'AFTERFRAME',
    this.subtitle,
    this.footer,
    this.accent = AfterFrameColors.lime,
  });

  final IconData icon;
  final String eyebrow;
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? footer;
  final Color accent;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .88,
      ),
      decoration: const BoxDecoration(
        color: AfterFrameColors.elevated,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AfterFrameRadius.xl),
        ),
        border: Border(top: BorderSide(color: AfterFrameColors.glassBorder)),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -90,
            right: -70,
            child: IgnorePointer(
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [accent.withValues(alpha: .11), Colors.transparent],
                  ),
                ),
              ),
            ),
          ),
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .18),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: accent.withValues(alpha: .2)),
                      ),
                      child: Icon(icon, color: accent, size: 23),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            eyebrow,
                            style: TextStyle(
                              color: accent,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.8,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            title,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              subtitle!,
                              style: const TextStyle(
                                color: AfterFrameColors.textTertiary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                child,
                if (footer != null) ...[const SizedBox(height: 22), footer!],
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class AfterFrameSheetOption extends StatelessWidget {
  const AfterFrameSheetOption({
    super.key,
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
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: selected
          ? AfterFrameColors.lime.withValues(alpha: .1)
          : Colors.white.withValues(alpha: .035),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: selected
              ? AfterFrameColors.lime.withValues(alpha: .28)
              : AfterFrameColors.glassBorder,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          child: Row(
            children: [
              Icon(
                icon,
                size: 21,
                color: selected
                    ? AfterFrameColors.lime
                    : AfterFrameColors.textSecondary,
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: selected
                    ? const Icon(
                        Icons.check_circle_rounded,
                        key: ValueKey(true),
                        color: AfterFrameColors.lime,
                      )
                    : const Icon(
                        Icons.circle_outlined,
                        key: ValueKey(false),
                        color: AfterFrameColors.disabled,
                      ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class AfterFrameConfetti extends StatefulWidget {
  const AfterFrameConfetti({super.key});

  @override
  State<AfterFrameConfetti> createState() => _AfterFrameConfettiState();
}

class _AfterFrameConfettiState extends State<AfterFrameConfetti>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1900),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => CustomPaint(
        painter: _ConfettiPainter(_controller.value),
        size: Size.infinite,
      ),
    ),
  );
}

class _ConfettiPainter extends CustomPainter {
  const _ConfettiPainter(this.progress);

  final double progress;

  static const _colors = [
    AfterFrameColors.lime,
    AfterFrameColors.coral,
    AfterFrameColors.violet,
    Color(0xFF70D7FF),
    Color(0xFFFFD85A),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final fade = (1 - ((progress - .72) / .28).clamp(0.0, 1.0));
    final eased = Curves.easeOutCubic.transform(progress);
    final paint = Paint();
    for (var i = 0; i < 46; i++) {
      final side = i.isEven ? -1.0 : 1.0;
      final seed = ((i * 47) % 101) / 101;
      final spread = .18 + seed * .78;
      final origin = Offset(
        side < 0 ? size.width * .08 : size.width * .92,
        size.height * .28,
      );
      final distanceX = size.width * spread * .58 * eased * -side;
      final lift = size.height * (.18 + seed * .18) * math.sin(math.pi * eased);
      final fall = size.height * .46 * progress * progress;
      final position = origin + Offset(distanceX, fall - lift);
      final rotation = progress * (8 + seed * 13) + i;
      final pieceSize = 4.0 + (i % 4) * 1.3;
      paint.color = _colors[i % _colors.length].withValues(alpha: fade * .9);
      canvas.save();
      canvas.translate(position.dx, position.dy);
      canvas.rotate(rotation);
      if (i % 3 == 0) {
        canvas.drawCircle(Offset.zero, pieceSize * .55, paint);
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset.zero,
              width: pieceSize,
              height: pieceSize * 2.1,
            ),
            const Radius.circular(2),
          ),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
