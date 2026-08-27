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
    final plan = canvas.canvasPlan;
    final coverMs = first.resolvedCoverMs;
    final coverPath = await engine.extractFrame(first.asset.uri, coverMs);
    final published = await engine.exportLive(
      asset: first.asset,
      startMs: first.trimStartMs,
      endMs: first.trimStartMs + canvas.durationMs,
      coverMs: coverMs,
      coverPath: coverPath,
      keepAudio: canvas.audioEnabled,
      loop: canvas.loopEnabled,
      playbackSpeed: canvas.playbackSpeed,
      enhancementEnabled: canvas.enhancementEnabled,
      collageAssets: canvas.clips
          .map((clip) => clip.asset)
          .toList(growable: false),
      collageLayout: 0,
      collageAudioSourceIndex: 0,
      collageStartMs: canvas.clips.map((clip) => clip.trimStartMs).toList(),
      collageEndMs: canvas.clips.map((clip) {
        final end = clip.trimStartMs + canvas.durationMs;
        if (end > clip.trimEndMs) return clip.trimEndMs;
        if (end <= clip.trimStartMs) return clip.trimEndMs;
        return end;
      }).toList(),
      collageCoverMs: canvas.clips
          .map((clip) => clip.resolvedCoverMs)
          .toList(growable: false),
      motionTransition: 0,
      canvasWidth: plan.canvas.width,
      canvasHeight: plan.canvas.height,
      collageRects: plan.frames
          .map((frame) => frame.rect.normalized(plan.canvas))
          .toList(growable: false),
      sourceCropRects: plan.frames
          .map((frame) => frame.crop.encoded)
          .toList(growable: false),
      collagePixelRects: plan.frames
          .map((frame) => frame.rect.pixelEncoded)
          .toList(growable: false),
      sourceCropPixelRects: plan.frames
          .map((frame) => frame.crop.pixelEncoded)
          .toList(growable: false),
      collageSourceSizes: plan.frames
          .map((frame) => [frame.crop.sourceWidth, frame.crop.sourceHeight])
          .toList(growable: false),
      format: canvas.exportFormat.name,
    );
    return (published: published, coverPath: coverPath);
  }
}

LiveExport toLiveExport(
  PublishedLive published,
  String fallbackCover, {
  int sourceCount = 1,
}) => LiveExport(
  path: published.liveUri,
  createdAt: DateTime.now(),
  coverPath: published.coverPath.isEmpty ? fallbackCover : published.coverPath,
  galleryUri: published.galleryUri,
  displayName: published.displayName,
  shareMimeType: published.shareMimeType,
  sourceCount: sourceCount,
);
