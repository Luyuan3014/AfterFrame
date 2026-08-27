import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../theme.dart';

/// Slow aperture / memory-ripple atmosphere behind the home hero.
///
/// The motion is intentionally almost imperceptible: an 8-second breath,
/// paused when the tab is hidden, reduced-motion is on, or widget tests run.
class MemoryGlowBackground extends StatefulWidget {
  const MemoryGlowBackground({super.key, this.active = true});

  final bool active;

  @override
  State<MemoryGlowBackground> createState() => _MemoryGlowBackgroundState();
}

class _MemoryGlowBackgroundState extends State<MemoryGlowBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant MemoryGlowBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) _sync();
  }

  void _sync() {
    final allowLoop =
        widget.active &&
        !_inWidgetTest &&
        !MediaQuery.disableAnimationsOf(context);
    if (allowLoop) {
      if (!_controller.isAnimating) {
        _controller.repeat(reverse: true);
      }
    } else {
      _controller
        ..stop()
        ..value = .42;
    }
  }

  static bool get _inWidgetTest {
    if (kIsWeb) return false;
    try {
      return Platform.environment.containsKey('FLUTTER_TEST');
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => CustomPaint(
        painter: _MemoryGlowPainter(breath: _controller.value),
        child: const SizedBox.expand(),
      ),
    ),
  );
}

class _MemoryGlowPainter extends CustomPainter {
  const _MemoryGlowPainter({required this.breath});

  final double breath;

  @override
  void paint(Canvas canvas, Size size) {
    final origin = Offset(size.width * .52, size.height * .22);
    final pulse = .86 + breath * .14;

    _orb(
      canvas,
      origin,
      math.max(size.width, size.height) * .62 * pulse,
      const Color(0xFF14241C),
      .34,
    );
    _orb(
      canvas,
      origin + Offset(size.width * .18, size.height * .08),
      90 * pulse,
      const Color(0xFF163029),
      .16,
    );
    _orb(
      canvas,
      origin + Offset(-size.width * .22, size.height * .16),
      64 * pulse,
      AfterFrameColors.brandGlow,
      .12,
    );

    for (var i = 0; i < 4; i++) {
      final radius = (56.0 + i * 46) * pulse;
      final alpha = (.10 - i * .018) * (.72 + breath * .28);
      canvas.drawCircle(
        origin,
        radius,
        Paint()
          ..color = const Color(0xFF2A4A38).withValues(alpha: alpha.clamp(0, 1))
          ..style = PaintingStyle.stroke
          ..strokeWidth = i == 0 ? 1.4 : 1,
      );
    }

    final satellites = <Offset>[
      origin + Offset(-78, 36),
      origin + Offset(92, -8),
      origin + Offset(18, 78),
    ];
    for (var i = 0; i < satellites.length; i++) {
      canvas.drawCircle(
        satellites[i],
        (11.0 + i * 3) * pulse,
        Paint()
          ..color = const Color(
            0xFF2A4A38,
          ).withValues(alpha: .07 + breath * .04)
          ..style = PaintingStyle.stroke
          ..strokeWidth = .8,
      );
    }
  }

  void _orb(
    Canvas canvas,
    Offset center,
    double radius,
    Color color,
    double a,
  ) {
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: a),
            color.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  @override
  bool shouldRepaint(covariant _MemoryGlowPainter oldDelegate) =>
      oldDelegate.breath != breath;
}
