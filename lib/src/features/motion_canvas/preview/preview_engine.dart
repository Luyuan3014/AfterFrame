import 'dart:io';

import 'package:video_player/video_player.dart';

/// Read-only preview boundary. It may decode, seek and play, but never exports.
abstract interface class PreviewEngine {
  VideoPlayerController create(String source);
}

/// Android's endorsed video_player implementation is backed by Media3 ExoPlayer.
/// Keeping construction here separates interactive preview from file export.
final class Media3PreviewEngine implements PreviewEngine {
  const Media3PreviewEngine();

  @override
  VideoPlayerController create(String source) {
    final uri = Uri.parse(source);
    if (uri.scheme == 'content') return VideoPlayerController.contentUri(uri);
    if (uri.scheme == 'http' || uri.scheme == 'https') {
      return VideoPlayerController.networkUrl(uri);
    }
    return VideoPlayerController.file(
      File(uri.scheme == 'file' ? uri.toFilePath() : source),
    );
  }
}
