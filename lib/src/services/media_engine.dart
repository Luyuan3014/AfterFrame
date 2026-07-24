import 'package:flutter/services.dart';

import '../models/media_asset.dart';

class MediaEngineException implements Exception {
  const MediaEngineException(this.message);
  final String message;
  @override
  String toString() => message;
}

class MediaEngine {
  const MediaEngine();

  static const _channel = MethodChannel('com.afterframe/media_engine');

  Future<bool> requestVideoAccess() async {
    try {
      return await _channel.invokeMethod<bool>('requestVideoAccess') ?? false;
    } on PlatformException catch (error) {
      throw MediaEngineException(error.message ?? '无法请求视频访问权限');
    }
  }

  Future<List<MediaAsset>> listVideos() async {
    try {
      final data = await _channel.invokeListMethod<Object?>('listVideos') ?? const [];
      return data
          .cast<Map<Object?, Object?>>()
          .map(MediaAsset.fromMap)
          .toList(growable: false);
    } on PlatformException catch (error) {
      throw MediaEngineException(error.message ?? '无法读取视频媒体库');
    }
  }

  Future<MediaAsset> inspectVideo(String uri) async {
    try {
      final data = await _channel.invokeMapMethod<Object?, Object?>('inspectVideo', {'uri': uri});
      if (data == null) throw const MediaEngineException('无法读取视频信息');
      return MediaAsset.fromMap(data);
    } on PlatformException catch (error) {
      throw MediaEngineException(error.message ?? '无法读取视频信息');
    }
  }

  Future<String> videoThumbnail(String uri) async {
    try {
      return await _channel.invokeMethod<String>('videoThumbnail', {'uri': uri}) ?? '';
    } on PlatformException catch (error) {
      throw MediaEngineException(error.message ?? '无法生成视频缩略图');
    }
  }

  Future<String> extractFrame(String uri, int timeMs) async {
    try {
      return await _channel.invokeMethod<String>('extractFrame', {'uri': uri, 'timeMs': timeMs}) ?? '';
    } on PlatformException catch (error) {
      throw MediaEngineException(error.message ?? '封面提取失败');
    }
  }

  Future<List<FrameSample>> extractTimeline(String uri, int durationMs, {int count = 10}) async {
    final safeDuration = durationMs.clamp(1, 1 << 31).toInt();
    final futures = List.generate(count, (index) {
      final time = ((safeDuration - 1) * index / (count - 1)).round();
      return extractFrame(uri, time).then((path) => FrameSample(timeMs: time, path: path));
    });
    return Future.wait(futures);
  }

  Future<String> exportLive({
    required MediaAsset asset,
    required int startMs,
    required int endMs,
    required int coverMs,
    required String coverPath,
    required bool keepAudio,
    required bool loop,
  }) async {
    try {
      return await _channel.invokeMethod<String>('exportLive', {
            'uri': asset.uri,
            'name': asset.name,
            'startMs': startMs,
            'endMs': endMs,
            'coverMs': coverMs,
            'coverPath': coverPath,
            'keepAudio': keepAudio,
            'loop': loop,
            'width': asset.width,
            'height': asset.height,
          }) ??
          '';
    } on PlatformException catch (error) {
      throw MediaEngineException(error.message ?? 'Live 导出失败');
    }
  }
}
