import 'package:flutter/services.dart';

import '../models/media_asset.dart';

class MediaEngineException implements Exception {
  const MediaEngineException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => message;
}

class MediaEngine {
  const MediaEngine();

  static const _channel = MethodChannel('com.afterframe/media_engine');
  static final Map<String, Future<String>> _thumbnailCache = {};
  static final Map<String, Future<String>> _frameCache = {};
  static const int _memoryCacheLimit = 96;

  Future<bool> requestVideoAccess() async {
    try {
      return await _channel.invokeMethod<bool>('requestVideoAccess') ?? false;
    } on PlatformException catch (error) {
      throw MediaEngineException(error.code, error.message ?? '无法请求视频访问权限');
    }
  }

  Future<List<MediaAsset>> listVideos() async {
    try {
      final data =
          await _channel.invokeListMethod<Object?>('listVideos') ?? const [];
      return data
          .cast<Map<Object?, Object?>>()
          .map(MediaAsset.fromMap)
          .toList(growable: false);
    } on PlatformException catch (error) {
      throw MediaEngineException(error.code, error.message ?? '无法读取视频媒体库');
    }
  }

  Future<MediaAsset> inspectVideo(String uri) async {
    try {
      final data = await _channel.invokeMapMethod<Object?, Object?>(
        'inspectVideo',
        {'uri': uri},
      );
      if (data == null) {
        throw const MediaEngineException('INSPECT_FAILED', '无法读取视频信息');
      }
      return MediaAsset.fromMap(data);
    } on PlatformException catch (error) {
      throw MediaEngineException(error.code, error.message ?? '无法读取视频信息');
    }
  }

  Future<String> videoThumbnail(String uri) async {
    return _remember(_thumbnailCache, uri, () => _videoThumbnail(uri));
  }

  Future<String> _videoThumbnail(String uri) async {
    try {
      return await _channel.invokeMethod<String>('videoThumbnail', {
            'uri': uri,
          }) ??
          '';
    } on PlatformException catch (error) {
      throw MediaEngineException(error.code, error.message ?? '无法生成视频缩略图');
    }
  }

  Future<String> extractFrame(String uri, int timeMs) async {
    final key = '$uri@$timeMs';
    return _remember(_frameCache, key, () => _extractFrame(uri, timeMs));
  }

  Future<String> _extractFrame(String uri, int timeMs) async {
    try {
      return await _channel.invokeMethod<String>('extractFrame', {
            'uri': uri,
            'timeMs': timeMs,
          }) ??
          '';
    } on PlatformException catch (error) {
      throw MediaEngineException(error.code, error.message ?? '封面提取失败');
    }
  }

  static Future<String> _remember(
    Map<String, Future<String>> cache,
    String key,
    Future<String> Function() loader,
  ) {
    final existing = cache[key];
    if (existing != null) return existing;
    if (cache.length >= _memoryCacheLimit) cache.remove(cache.keys.first);
    final future = loader();
    cache[key] = future;
    future.catchError((Object _) {
      cache.remove(key);
      return '';
    });
    return future;
  }

  Future<List<LiveExport>> listExports() async {
    try {
      final data =
          await _channel.invokeListMethod<Object?>('listExports') ?? const [];
      return data
          .cast<Map<Object?, Object?>>()
          .map(LiveExport.fromMap)
          .toList(growable: false);
    } on PlatformException catch (error) {
      throw MediaEngineException(error.code, error.message ?? '无法恢复作品索引');
    }
  }

  Future<List<FrameSample>> extractTimeline(
    String uri,
    int durationMs, {
    int count = 10,
  }) async {
    final safeDuration = durationMs.clamp(1, 1 << 31).toInt();
    final futures = List.generate(count, (index) {
      final time = ((safeDuration - 1) * index / (count - 1)).round();
      return extractFrame(
        uri,
        time,
      ).then((path) => FrameSample(timeMs: time, path: path));
    });
    return Future.wait(futures);
  }

  Future<PublishedLive> exportLive({
    required MediaAsset asset,
    required int startMs,
    required int endMs,
    required int coverMs,
    required String coverPath,
    required bool keepAudio,
    required bool loop,
    double playbackSpeed = 1,
    bool enhancementEnabled = false,
    List<MediaAsset> collageAssets = const [],
    int collageLayout = 0,
    int collageAudioSourceIndex = 0,
  }) async {
    try {
      final data = await _channel
          .invokeMapMethod<Object?, Object?>('exportLive', {
            'uri': asset.uri,
            'name': asset.name,
            'startMs': startMs,
            'endMs': endMs,
            'coverMs': coverMs,
            'coverPath': coverPath,
            'keepAudio': keepAudio,
            'loop': loop,
            'playbackSpeed': playbackSpeed,
            'enhancementEnabled': enhancementEnabled,
            'collageUris': collageAssets.map((item) => item.uri).toList(),
            'collageLayout': collageLayout,
            'collageAudioSourceIndex': collageAudioSourceIndex,
            'width': asset.width,
            'height': asset.height,
          });
      if (data == null) {
        throw const MediaEngineException('EXPORT_EMPTY', 'Live 导出结果为空');
      }
      return PublishedLive.fromMap(data);
    } on PlatformException catch (error) {
      throw MediaEngineException(error.code, error.message ?? 'Live 导出失败');
    }
  }

  Future<void> shareMotionPhoto(PublishedLive published) => _shareMedia(
    uri: published.liveUri,
    mimeType: 'image/jpeg',
    title: '分享动态照片原文件',
  );

  Future<void> shareVideo(PublishedLive published) => _shareMedia(
    uri: published.galleryUri,
    mimeType: 'video/mp4',
    title: '发送到微信、抖音或其他应用',
  );

  Future<void> shareExport(String uri, {String mimeType = 'video/mp4'}) =>
      _shareMedia(uri: uri, mimeType: mimeType, title: '发送到微信、抖音或其他应用');

  Future<void> _shareMedia({
    required String uri,
    required String mimeType,
    required String title,
  }) async {
    if (uri.isEmpty) {
      throw const MediaEngineException('SHARE_EMPTY', '没有可分享的文件');
    }
    try {
      await _channel.invokeMethod<void>('shareMedia', {
        'uri': uri,
        'mimeType': mimeType,
        'title': title,
      });
    } on PlatformException catch (error) {
      throw MediaEngineException(error.code, error.message ?? '无法打开分享面板');
    }
  }
}

class PublishedLive {
  const PublishedLive({
    required this.liveUri,
    required this.galleryUri,
    required this.coverUri,
    required this.displayName,
    required this.albumName,
    required this.coverPath,
  });

  final String liveUri;
  final String galleryUri;
  final String coverUri;
  final String displayName;
  final String albumName;
  final String coverPath;

  factory PublishedLive.fromMap(Map<Object?, Object?> map) => PublishedLive(
    liveUri: map['liveUri'] as String? ?? '',
    galleryUri: map['galleryUri'] as String? ?? '',
    coverUri: map['coverUri'] as String? ?? '',
    displayName: map['displayName'] as String? ?? 'AfterFrame',
    albumName: map['albumName'] as String? ?? 'AfterFrame',
    coverPath: map['coverPath'] as String? ?? '',
  );
}
