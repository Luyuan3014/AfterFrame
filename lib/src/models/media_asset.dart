class MediaAsset {
  const MediaAsset({
    required this.uri,
    required this.name,
    required this.durationMs,
    required this.width,
    required this.height,
    required this.rotation,
  });

  final String uri;
  final String name;
  final int durationMs;
  final int width;
  final int height;
  final int rotation;

  double get aspectRatio {
    final rotated = rotation == 90 || rotation == 270;
    final w = rotated ? height : width;
    final h = rotated ? width : height;
    return h == 0 ? 9 / 16 : w / h;
  }

  String get durationLabel {
    final seconds = durationMs ~/ 1000;
    return '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  factory MediaAsset.fromMap(Map<Object?, Object?> map) => MediaAsset(
        uri: map['uri'] as String,
        name: (map['name'] as String?) ?? '未命名视频',
        durationMs: (map['durationMs'] as num?)?.toInt() ?? 0,
        width: (map['width'] as num?)?.toInt() ?? 0,
        height: (map['height'] as num?)?.toInt() ?? 0,
        rotation: (map['rotation'] as num?)?.toInt() ?? 0,
      );
}

class FrameSample {
  const FrameSample({required this.timeMs, required this.path});
  final int timeMs;
  final String path;
}

class LiveExport {
  const LiveExport({required this.path, required this.createdAt, required this.coverPath});
  final String path;
  final DateTime createdAt;
  final String coverPath;
}
