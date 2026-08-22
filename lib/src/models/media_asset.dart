enum MediaKind { video, motionPhoto }

class MediaAsset {
  const MediaAsset({
    required this.uri,
    required this.name,
    required this.durationMs,
    required this.width,
    required this.height,
    required this.rotation,
    this.kind = MediaKind.video,
    this.libraryUri = '',
    this.stillUri,
  });

  /// Playable source. Videos keep their MediaStore URI; Live photos become the
  /// extracted MP4 after [MediaEngine.resolvePlayable].
  final String uri;
  final String name;
  final int durationMs;
  final int width;
  final int height;
  final int rotation;
  final MediaKind kind;

  /// Stable picker identity. For Live photos this stays the original still URI
  /// even after the motion payload has been extracted.
  final String libraryUri;

  /// Original Motion Photo still, used for album thumbnails.
  final String? stillUri;

  bool get isMotionPhoto => kind == MediaKind.motionPhoto;

  String get durationLabel {
    if (isMotionPhoto && durationMs <= 0) return 'LIVE';
    final total = (durationMs / 1000).floor();
    return '${(total ~/ 60).toString().padLeft(2, '0')}:'
        '${(total % 60).toString().padLeft(2, '0')}';
  }

  String get identity => libraryUri.isNotEmpty
      ? libraryUri
      : (stillUri?.isNotEmpty == true ? stillUri! : uri);

  String get thumbnailUri => stillUri?.isNotEmpty == true ? stillUri! : uri;

  double get aspectRatio {
    final rotated = rotation == 90 || rotation == 270;
    final w = rotated ? height : width;
    final h = rotated ? width : height;
    return h == 0 ? 9 / 16 : w / h;
  }

  MediaAsset copyWith({
    String? uri,
    String? name,
    int? durationMs,
    int? width,
    int? height,
    int? rotation,
    MediaKind? kind,
    String? libraryUri,
    String? stillUri,
  }) => MediaAsset(
    uri: uri ?? this.uri,
    name: name ?? this.name,
    durationMs: durationMs ?? this.durationMs,
    width: width ?? this.width,
    height: height ?? this.height,
    rotation: rotation ?? this.rotation,
    kind: kind ?? this.kind,
    libraryUri: libraryUri ?? this.libraryUri,
    stillUri: stillUri ?? this.stillUri,
  );

  factory MediaAsset.fromMap(Map<Object?, Object?> map) => MediaAsset(
    uri: map['uri'] as String,
    name: (map['name'] as String?) ?? 'AfterFrame',
    durationMs: (map['durationMs'] as num?)?.toInt() ?? 0,
    width: (map['width'] as num?)?.toInt() ?? 0,
    height: (map['height'] as num?)?.toInt() ?? 0,
    rotation: (map['rotation'] as num?)?.toInt() ?? 0,
    kind: (map['kind'] as String?) == 'motionPhoto'
        ? MediaKind.motionPhoto
        : MediaKind.video,
    libraryUri: (map['libraryUri'] as String?) ?? '',
    stillUri: map['stillUri'] as String?,
  );
}

class FrameSample {
  const FrameSample({required this.timeMs, required this.path});
  final int timeMs;
  final String path;
}

class LiveExport {
  const LiveExport({
    required this.path,
    required this.createdAt,
    required this.coverPath,
    this.galleryUri = '',
    this.displayName = 'AfterFrame',
    this.shareMimeType = 'video/mp4',
  });
  final String path;
  final DateTime createdAt;
  final String coverPath;
  final String galleryUri;
  final String displayName;
  final String shareMimeType;

  factory LiveExport.fromMap(Map<Object?, Object?> map) => LiveExport(
    path: map['liveUri'] as String? ?? '',
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      (map['createdAt'] as num?)?.toInt() ?? 0,
    ),
    coverPath: map['coverPath'] as String? ?? '',
    galleryUri: map['galleryUri'] as String? ?? '',
    displayName: map['displayName'] as String? ?? 'AfterFrame',
    shareMimeType: map['shareMimeType'] as String? ?? 'video/mp4',
  );
}
