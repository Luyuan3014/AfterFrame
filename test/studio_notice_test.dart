import 'package:after_frame/src/widgets/studio_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a notice with an action still auto-dismisses', (tester) async {
    final controller = StudioNoticeController();
    addTearDown(controller.dispose);
    var undone = false;

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: StudioNoticeHost(
            controller: controller,
            child: const Scaffold(body: SizedBox.expand()),
          ),
        ),
      ),
    );

    controller.show(
      message: '已移除 1 段素材',
      actionLabel: '撤销',
      onAction: () => undone = true,
      duration: const Duration(seconds: 4),
    );
    await tester.pump();

    expect(find.text('已移除 1 段素材'), findsOneWidget);
    expect(find.text('撤销'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    await tester.pump();

    expect(find.text('已移除 1 段素材'), findsNothing);
    expect(undone, isFalse);
  });

  testWidgets('undo dismisses the notice and restores the clip', (
    tester,
  ) async {
    final controller = StudioNoticeController();
    addTearDown(controller.dispose);
    var undone = false;

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: StudioNoticeHost(
            controller: controller,
            child: const Scaffold(body: SizedBox.expand()),
          ),
        ),
      ),
    );

    controller.show(
      message: '已移除 1 段素材',
      actionLabel: '撤销',
      onAction: () => undone = true,
      duration: const Duration(seconds: 8),
    );
    await tester.pump();
    await tester.tap(find.text('撤销'));
    await tester.pump();

    expect(undone, isTrue);
    expect(find.text('已移除 1 段素材'), findsNothing);
  });
}
