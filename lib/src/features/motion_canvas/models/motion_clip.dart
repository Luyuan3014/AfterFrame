import '../../../models/media_asset.dart';

enum SubjectKind { person, landscape, sky, detail }

class CropFocus {
  const CropFocus({this.x = .5, this.y = .5, this.confidence = 0});

  final double x;
  final double y;
  final double confidence;

  CropFocus copyWith({double? x, double? y, double? confidence}) => CropFocus(
    x: x ?? this.x,
    y: y ?? this.y,
    confidence: confidence ?? this.confidence,
  );
}

class MotionClip {
  const MotionClip({
    required this.id,
    required this.asset,
    required this.trimStartMs,
    required this.trimEndMs,
    required this.focus,
    required this.subject,
    this.thumbnailPath,
  });

  final String id;
  final MediaAsset asset;
  final int trimStartMs;
  final int trimEndMs;
  final CropFocus focus;
  final SubjectKind subject;
  final String? thumbnailPath;

  int get durationMs => trimEndMs - trimStartMs;

  MotionClip copyWith({
    int? trimStartMs,
    int? trimEndMs,
    CropFocus? focus,
    SubjectKind? subject,
    String? thumbnailPath,
  }) => MotionClip(
    id: id,
    asset: asset,
    trimStartMs: trimStartMs ?? this.trimStartMs,
    trimEndMs: trimEndMs ?? this.trimEndMs,
    focus: focus ?? this.focus,
    subject: subject ?? this.subject,
    thumbnailPath: thumbnailPath ?? this.thumbnailPath,
  );
}
