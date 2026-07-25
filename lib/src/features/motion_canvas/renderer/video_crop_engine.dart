import '../models/motion_canvas_layout.dart';
import '../models/motion_clip.dart';

/// Deterministic crop planning boundary. Subject detectors can replace
/// [estimateFocus] without changing the renderer or export contract.
class VideoCropEngine {
  const VideoCropEngine();

  CropFocus estimateFocus(MotionClip clip, MotionTemplate template, int index) {
    final ratio = clip.asset.aspectRatio;
    final subject = _subjectFor(template, index, ratio);
    final y = switch (subject) {
      SubjectKind.sky => .32,
      SubjectKind.person => ratio > 1.2 ? .45 : .42,
      SubjectKind.detail => .56,
      SubjectKind.landscape => .48,
    };
    return CropFocus(x: .5, y: y, confidence: .38);
  }

  SubjectKind _subjectFor(
    MotionTemplate template,
    int index,
    double aspectRatio,
  ) => switch (template) {
    MotionTemplate.travelDiary => [
      SubjectKind.landscape,
      SubjectKind.person,
      SubjectKind.detail,
    ][index % 3],
    MotionTemplate.sunsetStory => [
      SubjectKind.sky,
      SubjectKind.landscape,
      SubjectKind.person,
    ][index % 3],
    MotionTemplate.filmStrip =>
      aspectRatio < .9 ? SubjectKind.person : SubjectKind.landscape,
    MotionTemplate.minimalMemory => SubjectKind.detail,
  };
}
