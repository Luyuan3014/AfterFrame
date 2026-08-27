import 'package:after_frame/src/widgets/live_playback_scale.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Live playback enlarges the picture and settles when still', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: LivePlaybackScale(
          playing: false,
          child: SizedBox(key: Key('still'), width: 40, height: 40),
        ),
      ),
    );

    expect(
      tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
      LivePlaybackMotion.stillScale,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: LivePlaybackScale(
          playing: true,
          child: SizedBox(key: Key('live'), width: 40, height: 40),
        ),
      ),
    );

    expect(
      tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
      LivePlaybackMotion.liveScale,
    );
  });
}
