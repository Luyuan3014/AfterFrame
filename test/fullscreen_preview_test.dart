import 'package:after_frame/src/live_editor/components/fullscreen_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('full-screen preview supports close and pull-down dismissal', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => FullscreenPreview.show(
              context,
              label: 'Live Frame',
              exitHint: 'Swipe down to exit full screen',
              child: const ColoredBox(color: Colors.black),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.close_fullscreen_rounded), findsOneWidget);
    expect(find.text('Swipe down to exit full screen'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_fullscreen_rounded));
    await tester.pumpAndSettle();
    expect(find.byType(FullscreenPreview), findsNothing);

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(FullscreenPreview), const Offset(0, 140));
    await tester.pumpAndSettle();
    expect(find.byType(FullscreenPreview), findsNothing);
  });
}
