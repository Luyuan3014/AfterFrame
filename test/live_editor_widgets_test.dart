import 'dart:ui' show Tristate;

import 'package:after_frame/src/live_editor/components/advanced_settings.dart';
import 'package:after_frame/src/live_editor/components/creation_mode_selector.dart';
import 'package:after_frame/src/live_editor/components/generate_button.dart';
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

  testWidgets('small screen can switch mode and expand More Settings', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = LiveEditorState(asset: asset, mode: CreationMode.liveFrame);
    addTearDown(state.dispose);

    await tester.pumpWidget(_host(state));
    await tester.tap(find.text('Motion Collage'));
    await tester.pumpAndSettle();
    expect(state.mode, CreationMode.motionCollage);

    await tester.ensureVisible(find.byKey(const Key('more-settings')));
    await tester.tap(find.byKey(const Key('more-settings')));
    await tester.pumpAndSettle();
    expect(find.text('2x'), findsOneWidget);
  });

  testWidgets('generate status and accessibility semantics are exposed', (
    tester,
  ) async {
    final state = LiveEditorState(asset: asset, mode: CreationMode.liveFrame);
    addTearDown(state.dispose);
    await tester.pumpWidget(_host(state));

    final semantics = tester.getSemantics(find.byType(GenerateButton));
    expect(semantics.flagsCollection.isButton, isTrue);
    expect(semantics.flagsCollection.isEnabled, Tristate.isTrue);

    state.setGenerateStatus(GenerateStatus.processing);
    await tester.pump();
    expect(find.text('Creating your living moment…'), findsOneWidget);
  });
}

Widget _host(LiveEditorState state) => MaterialApp(
  home: AppLanguageScope(
    controller: AppLanguageController(AppLanguage.english),
    child: LiveEditorScope(
      state: state,
      child: Scaffold(
        body: SingleChildScrollView(
          child: Column(
            children: [
              const CreationModeSelector(),
              const AdvancedSettings(),
              GenerateButton(onPressed: () {}),
            ],
          ),
        ),
      ),
    ),
  ),
);
