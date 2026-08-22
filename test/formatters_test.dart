import 'package:after_frame/src/live_editor/formatters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('editor time rounds to the nearest tenth of a second', () {
    expect(formatEditorTime(2500), '00:02.5');
    expect(formatEditorTime(2490), '00:02.5');
    expect(formatEditorTime(2410), '00:02.4');
    expect(formatEditorTime(0), '00:00.0');
  });
}
