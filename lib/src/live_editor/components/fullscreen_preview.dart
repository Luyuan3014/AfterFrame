import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme.dart';

/// A route-based immersive preview with predictable back, close, and
/// pull-down dismissal. System UI is always restored when the route leaves.
class FullscreenPreview extends StatefulWidget {
  const FullscreenPreview({
    super.key,
    required this.child,
    required this.label,
    required this.exitHint,
  });

  final Widget child;
  final String label;
  final String exitHint;

  static Future<void> show(
    BuildContext context, {
    required Widget child,
    required String label,
    required String exitHint,
  }) => Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: true,
      barrierColor: Colors.black,
      transitionDuration: const Duration(milliseconds: 280),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, _, _) =>
          FullscreenPreview(label: label, exitHint: exitHint, child: child),
      transitionsBuilder: (_, animation, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        child: ScaleTransition(
          scale: Tween(begin: .985, end: 1.0).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          ),
          child: child,
        ),
      ),
    ),
  );

  @override
  State<FullscreenPreview> createState() => _FullscreenPreviewState();
}

class _FullscreenPreviewState extends State<FullscreenPreview> {
  double _dragOffset = 0;
  bool _chromeVisible = true;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _finishDrag(DragEndDetails details) {
    final dismiss = _dragOffset > 88 || (details.primaryVelocity ?? 0) > 850;
    if (dismiss) {
      Navigator.maybePop(context);
    } else {
      setState(() => _dragOffset = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _chromeVisible = !_chromeVisible),
        onVerticalDragUpdate: (details) => setState(
          () => _dragOffset = (_dragOffset + details.delta.dy).clamp(0, 180),
        ),
        onVerticalDragEnd: _finishDrag,
        child: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedContainer(
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              transform: Matrix4.translationValues(0, _dragOffset, 0)
                ..scaleByDouble(
                  1 - _dragOffset / 2400,
                  1 - _dragOffset / 2400,
                  1,
                  1,
                ),
              child: SafeArea(
                minimum: const EdgeInsets.symmetric(vertical: 12),
                child: Center(child: widget.child),
              ),
            ),
            IgnorePointer(
              ignoring: !_chromeVisible,
              child: AnimatedOpacity(
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                opacity: _chromeVisible ? 1 : 0,
                child: SafeArea(
                  child: Stack(
                    children: [
                      Positioned(
                        left: 18,
                        top: 10,
                        child: Text(
                          widget.label,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: .4,
                            shadows: [
                              Shadow(color: Colors.black, blurRadius: 8),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        right: 14,
                        top: 0,
                        child: IconButton.filled(
                          tooltip: 'Exit full screen',
                          onPressed: () => Navigator.maybePop(context),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.black54,
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(Icons.close_fullscreen_rounded),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 12,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: 17,
                              color: AfterFrameColors.muted,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              widget.exitHint,
                              style: const TextStyle(
                                color: AfterFrameColors.muted,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
