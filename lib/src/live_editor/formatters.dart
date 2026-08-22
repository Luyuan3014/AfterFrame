String formatEditorTime(int milliseconds) {
  final tenths = (milliseconds / 100).round().clamp(0, 1 << 30);
  final totalSeconds = tenths ~/ 10;
  final tenth = tenths % 10;
  return '${(totalSeconds ~/ 60).toString().padLeft(2, '0')}:'
      '${(totalSeconds % 60).toString().padLeft(2, '0')}.$tenth';
}
