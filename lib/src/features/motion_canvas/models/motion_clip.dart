import '../../../models/media_asset.dart';
import 'motion_canvas_layout.dart';

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

CropFocus smartCropFocusFor(MediaAsset asset) {
  final portrait = asset.aspectRatio < .82;
  return CropFocus(
    x: .5,
    // A conservative upper-third bias protects faces in portrait captures;
    // it is deterministic and remains replaceable by on-device saliency data.
    y: portrait ? .43 : .5,
    confidence: portrait ? .35 : .2,
  );
}

/// Oriented source geometry for the layout planner. Rotation metadata is
/// resolved here so no caller has to swap width and height again.
CanvasSourceGeometry canvasGeometryFor(MediaAsset asset, {CropFocus? focus}) {
  final rotated = asset.rotation == 90 || asset.rotation == 270;
  final effective = focus ?? smartCropFocusFor(asset);
  return CanvasSourceGeometry(
    width: rotated ? asset.height : asset.width,
    height: rotated ? asset.width : asset.height,
    focusX: effective.x,
    focusY: effective.y,
    subjectConfidence: effective.confidence,
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
