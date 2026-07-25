import '../../../models/media_asset.dart';
import '../../../services/media_engine.dart';
import '../controllers/motion_canvas_controller.dart';

/// UI-independent export orchestration. The Android adapter uses Media3
/// Transformer and packages both a Motion Photo and share-ready MP4.
class MotionCanvasExportService {
  const MotionCanvasExportService(this.engine);

  final MediaEngine engine;

  Future<({PublishedLive published, String coverPath})> export(
    MotionCanvasController canvas,
  ) async {
    final first = canvas.clips.first;
    final coverMs =
        first.trimStartMs + canvas.positionMs.clamp(0, first.durationMs);
    final coverPath = await engine.extractFrame(first.asset.uri, coverMs);
    final published = await engine.exportLive(
      asset: first.asset,
      startMs: first.trimStartMs,
      endMs: first.trimEndMs,
      coverMs: coverMs,
      coverPath: coverPath,
      keepAudio: canvas.musicEnabled,
      loop: true,
      enhancementEnabled: canvas.style.index != 2,
      collageAssets: canvas.clips
          .map((clip) => clip.asset)
          .toList(growable: false),
      collageLayout: canvas.template.index,
      collageAudioSourceIndex: 0,
      collageStartMs: canvas.clips.map((clip) => clip.trimStartMs).toList(),
      collageEndMs: canvas.clips
          .map((clip) => clip.trimStartMs + canvas.durationMs)
          .toList(),
      motionTransition: canvas.transition.index,
      cropFocusX: canvas.clips.map((clip) => clip.focus.x).toList(),
      cropFocusY: canvas.clips.map((clip) => clip.focus.y).toList(),
      format: canvas.exportFormat.name,
    );
    return (published: published, coverPath: coverPath);
  }
}

LiveExport toLiveExport(PublishedLive published, String fallbackCover) =>
    LiveExport(
      path: published.liveUri,
      createdAt: DateTime.now(),
      coverPath: published.coverPath.isEmpty
          ? fallbackCover
          : published.coverPath,
      galleryUri: published.galleryUri,
      displayName: published.displayName,
      shareMimeType: published.shareMimeType,
    );
