import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme.dart';

class StudioNoticeData {
  const StudioNoticeData({
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
}

/// In-app notice used by AfterFrame Studio. Unlike [SnackBar], an action does
/// not pin the banner open — it always auto-dismisses.
class StudioNoticeController extends ChangeNotifier {
  StudioNoticeData? _notice;
  int _generation = 0;
  Timer? _timer;

  StudioNoticeData? get notice => _notice;

  void show({
    required String message,
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(seconds: 4),
  }) {
    _timer?.cancel();
    _generation += 1;
    final generation = _generation;
    _notice = StudioNoticeData(
      message: message,
      actionLabel: actionLabel,
      onAction: onAction == null
          ? null
          : () {
              dismiss();
              onAction();
            },
    );
    notifyListeners();
    if (duration <= Duration.zero) return;
    _timer = Timer(duration, () {
      if (_generation == generation) dismiss();
    });
  }

  void dismiss() {
    _timer?.cancel();
    _timer = null;
    if (_notice == null) return;
    _notice = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

class StudioNoticeHost extends StatelessWidget {
  const StudioNoticeHost({
    super.key,
    required this.controller,
    required this.child,
  });

  final StudioNoticeController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final notice = controller.notice;
      final reduceMotion = MediaQuery.disableAnimationsOf(context);
      return Stack(
        children: [
          Positioned.fill(child: child),
          Positioned(
            left: 16,
            right: 16,
            bottom: MediaQuery.paddingOf(context).bottom + 18,
            child: AnimatedSwitcher(
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 280),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                if (reduceMotion) return child;
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, .16),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                );
              },
              child: notice == null
                  ? const SizedBox.shrink()
                  : StudioNoticeBanner(
                      key: ValueKey(notice.message),
                      data: notice,
                    ),
            ),
          ),
        ],
      );
    },
  );
}

class StudioNoticeBanner extends StatelessWidget {
  const StudioNoticeBanner({super.key, required this.data});

  final StudioNoticeData data;

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: Semantics(
      liveRegion: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xE61C1E22),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: AfterFrameColors.glassBorder),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 24,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AfterFrameColors.lime.withValues(alpha: .14),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.layers_clear_rounded,
                      size: 18,
                      color: AfterFrameColors.lime,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      data.message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                  ),
                  if (data.actionLabel != null)
                    TextButton(
                      onPressed: data.onAction,
                      style: TextButton.styleFrom(
                        foregroundColor: AfterFrameColors.lime,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        minimumSize: const Size(0, 36),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        data.actionLabel!,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          letterSpacing: .2,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
