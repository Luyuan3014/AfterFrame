import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/motion_canvas_layout.dart';

class TransitionEngine extends StatelessWidget {
  const TransitionEngine({
    super.key,
    required this.transition,
    required this.progress,
    required this.child,
  });

  final MotionTransition transition;
  final double progress;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final pulse = math.sin(progress * math.pi * 2).abs();
    final overlay = switch (transition) {
      MotionTransition.lightLeak => LinearGradient(
        begin: Alignment(-1 + progress * 2, -1),
        end: Alignment(progress * 2, 1),
        colors: [
          Colors.transparent,
          const Color(0x35FF9B61),
          Colors.transparent,
        ],
      ),
      MotionTransition.filmGrain => const LinearGradient(
        colors: [Color(0x0AFFFFFF), Color(0x12000000), Color(0x08FFFFFF)],
      ),
      _ => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          Colors.black.withValues(alpha: .08 + pulse * .06),
        ],
      ),
    };
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        IgnorePointer(
          child: DecoratedBox(decoration: BoxDecoration(gradient: overlay)),
        ),
      ],
    );
  }
}
