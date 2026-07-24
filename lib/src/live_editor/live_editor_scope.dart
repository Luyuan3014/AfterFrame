import 'package:flutter/widgets.dart';

import 'models/live_editor_state.dart';

class LiveEditorScope extends InheritedNotifier<LiveEditorState> {
  const LiveEditorScope({
    super.key,
    required LiveEditorState state,
    required super.child,
  }) : super(notifier: state);

  static LiveEditorState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<LiveEditorScope>();
    assert(scope != null, 'LiveEditorScope is missing above this widget.');
    return scope!.notifier!;
  }
}
