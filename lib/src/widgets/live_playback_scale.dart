import 'package:flutter/material.dart';

/// Ken Burns-style scale used by Live Photo playback.
///
/// The still sits at [stillScale]. After Live playback starts, the picture
/// eases out to [liveScale]; when playback ends it settles back. Chrome such as
/// badges and buttons should sit outside this widget so only the image moves.
abstract final class LivePlaybackMotion {
  static const stillScale = 1.0;
  static const liveScale = 1.08;
  static const duration = Duration(milliseconds: 520);
}

class LivePlaybackScale extends StatelessWidget {
  const LivePlaybackScale({
    super.key,
    required this.playing,
    required this.child,
  });

  final bool playing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return ClipRect(
      child: AnimatedScale(
        scale: playing
            ? LivePlaybackMotion.liveScale
            : LivePlaybackMotion.stillScale,
        duration: reduceMotion ? Duration.zero : LivePlaybackMotion.duration,
        curve: playing ? Curves.easeOutCubic : Curves.easeInOutCubic,
        alignment: Alignment.center,
        child: child,
      ),
    );
  }
}
