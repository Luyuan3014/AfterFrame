import 'package:after_frame/src/live_editor/components/live_moment_editor.dart';
import 'package:after_frame/src/live_editor/live_editor_scope.dart';
import 'package:after_frame/src/live_editor/models/live_editor_state.dart';
import 'package:after_frame/src/localization/app_localizations.dart';
import 'package:after_frame/src/models/media_asset.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const asset = MediaAsset(
    uri: 'content://video/1',
    name: 'sample.mp4',
    durationMs: 6000,
    width: 1080,
    height: 1920,
    rotation: 0,
  );

  testWidgets(
    'single-frame editor uses one strip without duplicate timelines',
    (tester) async {
      final state = LiveEditorState(assets: const [asset]);
      addTearDown(state.dispose);
      state.finishLoading();

      await tester.pumpWidget(
        MaterialApp(
          home: AppLanguageScope(
            controller: AppLanguageController(AppLanguage.english),
            child: LiveEditorScope(
              state: state,
              child: const Scaffold(
                body: SingleChildScrollView(child: LiveMomentEditor()),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Cover & range'), findsOneWidget);
      expect(find.byKey(const Key('live-moment-strip')), findsOneWidget);
      expect(find.byType(RangeSlider), findsOneWidget);
      expect(find.text('Later moment'), findsOneWidget);
      expect(find.text('COVER MOMENT'), findsNothing);
      expect(find.text('MOMENT TIMELINE'), findsNothing);
      expect(find.text('Time Suggestions'), findsNothing);
      expect(find.text('Manual Select'), findsNothing);
      expect(find.text('Find the moment'), findsNothing);
    },
  );
}
