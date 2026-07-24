String formatEditorTime(int milliseconds) {
  final total = milliseconds ~/ 1000;
  final tenth = (milliseconds % 1000) ~/ 100;
  return '${(total ~/ 60).toString().padLeft(2, '0')}:'
      '${(total % 60).toString().padLeft(2, '0')}.$tenth';
}
