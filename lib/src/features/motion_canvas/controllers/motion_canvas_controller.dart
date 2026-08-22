import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';

import '../../../models/live_rules.dart';
import '../../../models/media_asset.dart';
import '../models/motion_canvas_layout.dart';
import '../models/motion_clip.dart';

class MotionCanvasController extends ChangeNotifier {
  MotionCanvasController({required List<MediaAsset> assets})
    : clips = List.generate(assets.length.clamp(1, maxLiveSources), (index) {
        final asset = assets[index];
        final end = asset.durationMs
            .clamp(minLiveDurationMs, maxLiveDurationMs)
            .toInt();
        return MotionClip(
          id: '${asset.uri}#$index',
          asset: asset,
          trimStartMs: 0,
          trimEndMs: end,
          coverMs: end ~/ 2,
          focus: smartCropFocusFor(asset),
          subject: asset.aspectRatio < .82
              ? SubjectKind.person
              : SubjectKind.landscape,
        );
      });

  static const motion = Duration(milliseconds: 320);
  static const curve = Curves.easeInOutCubic;

  final MotionCanvasLayout layout = const MotionCanvasLayout();
  List<MotionClip> clips;
  MotionExportFormat exportFormat = MotionExportFormat.motionPhoto;
  int activeClipIndex = 0;
  int positionMs = 0;
  bool isPlaying = false;
  bool isExporting = false;
  bool audioEnabled = LiveDefaults.audioEnabled;
  bool loopEnabled = LiveDefaults.loopEnabled;
  bool enhancementEnabled = LiveDefaults.enhancementEnabled;
  double playbackSpeed = LiveDefaults.playbackSpeed;

  AdaptiveCanvasPlan get canvasPlan => layout.planFor(
    clips
        .map((clip) => canvasGeometryFor(clip.asset, focus: clip.focus))
        .toList(growable: false),
  );

  List<CanvasFrame> get frames => canvasPlan.frames;

  List<MediaAsset> get assets =>
      clips.map((clip) => clip.asset).toList(growable: false);

  /// A canvas always keeps at least one source. Removing the last clip would
  /// leave Studio without anything to edit.
  bool get canRemoveClip => clips.length > 1;

  bool get canAddClip => clips.length < maxLiveSources;

  /// Shared Live length is never longer than the shortest usable source.
  int get durationMs {
    final shortest = clips
        .map((clip) {
          final assetMs = clip.asset.durationMs <= 0
              ? clip.durationMs
              : clip.asset.durationMs;
          return math.min(clip.durationMs, assetMs);
        })
        .reduce(math.min);
    return shortest.clamp(minLiveDurationMs, maxLiveDurationMs);
  }

  MotionClip get activeClip => clips[activeClipIndex];

  void selectClip(int index) {
    activeClipIndex = index.clamp(0, clips.length - 1);
    notifyListeners();
  }

  void moveCropFocus(int index, double deltaX, double deltaY) {
    if (index < 0 || index >= clips.length) return;
    final clip = clips[index];
    clips[index] = clip.copyWith(
      focus: clip.focus.copyWith(
        x: (clip.focus.x + deltaX).clamp(0, 1),
        y: (clip.focus.y + deltaY).clamp(0, 1),
        confidence: 1,
      ),
    );
    notifyListeners();
  }

  void resetSmartCrop(int index) {
    if (index < 0 || index >= clips.length) return;
    final clip = clips[index];
    clips[index] = clip.copyWith(focus: smartCropFocusFor(clip.asset));
    notifyListeners();
  }

  void reorder(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    final item = clips.removeAt(oldIndex);
    clips.insert(newIndex.clamp(0, clips.length), item);
    activeClipIndex = clips.indexOf(item);
    notifyListeners();
  }

  /// Drops one source and lets Adaptive Canvas re-plan. Returns the removed
  /// clip so the caller can offer an undo.
  MotionClip? removeClip(int index) {
    if (!canRemoveClip || index < 0 || index >= clips.length) return null;
    final removed = clips.removeAt(index);
    activeClipIndex = activeClipIndex.clamp(0, clips.length - 1);
    isPlaying = false;
    positionMs = positionMs.clamp(0, durationMs);
    notifyListeners();
    return removed;
  }

  void restoreClip(int index, MotionClip clip) {
    if (clips.length >= maxLiveSources) return;
    clips.insert(index.clamp(0, clips.length), clip);
    activeClipIndex = clips.indexOf(clip);
    isPlaying = false;
    positionMs = positionMs.clamp(0, durationMs);
    notifyListeners();
  }

  /// Rebuilds the ordered clip list from a new library selection.
  ///
  /// Clips whose [MediaAsset.identity] still exist keep trim, focus and
  /// thumbnail so adding a third Live photo does not wipe earlier edits.
  void replaceSources(List<MediaAsset> assets) {
    if (assets.isEmpty) return;
    final next = assets.take(maxLiveSources).toList(growable: false);
    final existing = {for (final clip in clips) clip.asset.identity: clip};
    clips = [
      for (var index = 0; index < next.length; index++)
        _clipForReplacement(next[index], index, existing[next[index].identity]),
    ];
    activeClipIndex = activeClipIndex.clamp(0, clips.length - 1);
    isPlaying = false;
    positionMs = positionMs.clamp(0, durationMs);
    notifyListeners();
  }

  MotionClip _clipForReplacement(
    MediaAsset asset,
    int index,
    MotionClip? previous,
  ) {
    if (previous == null) {
      final end = asset.durationMs
          .clamp(minLiveDurationMs, maxLiveDurationMs)
          .toInt();
      return MotionClip(
        id: '${asset.identity}#$index',
        asset: asset,
        trimStartMs: 0,
        trimEndMs: end,
        coverMs: end ~/ 2,
        focus: smartCropFocusFor(asset),
        subject: asset.aspectRatio < .82
            ? SubjectKind.person
            : SubjectKind.landscape,
      );
    }
    final end = previous.trimEndMs
        .clamp(previous.trimStartMs + minLiveDurationMs, asset.durationMs)
        .toInt();
    final start = previous.trimStartMs
        .clamp(0, end - minLiveDurationMs)
        .toInt();
    return previous.copyWith(
      asset: asset,
      trimStartMs: start,
      trimEndMs: end,
      coverMs: previous.resolvedCoverMs.clamp(start, end).toInt(),
    );
  }

  void setTrim(int index, int startMs, int endMs) {
    final assetDuration = clips[index].asset.durationMs;
    final safeStart = startMs
        .clamp(0, assetDuration - minLiveDurationMs)
        .toInt();
    final safeEnd = endMs
        .clamp(safeStart + minLiveDurationMs, assetDuration)
        .toInt();
    clips[index] = clips[index].copyWith(
      trimStartMs: safeStart,
      trimEndMs: safeEnd,
      coverMs: clips[index].resolvedCoverMs.clamp(safeStart, safeEnd).toInt(),
    );
    positionMs = positionMs.clamp(0, durationMs).toInt();
    notifyListeners();
  }

  void setClipCover(int index, int timeMs) {
    if (index < 0 || index >= clips.length) return;
    final clip = clips[index];
    final cover = timeMs.clamp(clip.trimStartMs, clip.trimEndMs).toInt();
    if (clip.resolvedCoverMs == cover && !isPlaying) return;
    isPlaying = false;
    clips[index] = clip.copyWith(coverMs: cover);
    notifyListeners();
  }

  /// Ground-truth size and duration from the decoded preview player.
  ///
  /// Live stills are often 1080p while the motion is 720p. Layout must follow
  /// the playable video, not the JPEG.
  void adoptDecodedSource(
    int index, {
    required int width,
    required int height,
    required int decodedDurationMs,
  }) {
    if (index < 0 || index >= clips.length) return;
    final clip = clips[index];
    final safeDuration = decodedDurationMs
        .clamp(minLiveDurationMs, 1 << 30)
        .toInt();
    final widthChanged =
        width >= 2 &&
        height >= 2 &&
        (clip.asset.width != width || clip.asset.height != height);
    final durationChanged = clip.asset.durationMs != safeDuration;
    if (!widthChanged && !durationChanged) return;

    var start = clip.trimStartMs
        .clamp(0, math.max(0, safeDuration - minLiveDurationMs))
        .toInt();
    var end = clip.trimEndMs
        .clamp(start + minLiveDurationMs, safeDuration)
        .toInt();
    if (clip.trimStartMs == 0 &&
        clip.trimEndMs <= minLiveDurationMs &&
        safeDuration > minLiveDurationMs) {
      start = 0;
      end = math.min(safeDuration, maxLiveDurationMs);
    }
    clips[index] = clip.copyWith(
      asset: clip.asset.copyWith(
        width: widthChanged ? width : null,
        height: widthChanged ? height : null,
        durationMs: durationChanged ? safeDuration : null,
        rotation: 0,
      ),
      trimStartMs: start,
      trimEndMs: end,
      coverMs: (clip.coverMs ?? (start + (end - start) ~/ 2))
          .clamp(start, end)
          .toInt(),
    );
    positionMs = positionMs.clamp(0, durationMs);
    notifyListeners();
  }

  void setPosition(int value, {bool notify = true}) {
    positionMs = value.clamp(0, durationMs);
    if (notify) notifyListeners();
  }

  void togglePlayback() {
    if (positionMs >= durationMs) positionMs = 0;
    isPlaying = !isPlaying;
    notifyListeners();
  }

  void stopAtEnd() {
    isPlaying = false;
    positionMs = durationMs;
    notifyListeners();
  }

  void setExportFormat(MotionExportFormat value) {
    exportFormat = value;
    notifyListeners();
  }

  void toggleAudio() {
    audioEnabled = !audioEnabled;
    notifyListeners();
  }

  void toggleLoop() {
    loopEnabled = !loopEnabled;
    notifyListeners();
  }

  void toggleEnhancement() {
    enhancementEnabled = !enhancementEnabled;
    notifyListeners();
  }

  void setPlaybackSpeed(double value) {
    if (playbackSpeed == value) return;
    playbackSpeed = value.clamp(.5, 2);
    notifyListeners();
  }

  /// Addressed by clip id because the rail can be reordered or trimmed while
  /// thumbnails are still being extracted.
  void setThumbnail(String clipId, String path) {
    final index = clips.indexWhere((clip) => clip.id == clipId);
    if (index < 0) return;
    clips[index] = clips[index].copyWith(thumbnailPath: path);
    notifyListeners();
  }

  Completer<void>? _previewRelease;

  void setExporting(bool value) {
    if (isExporting == value) return;
    isExporting = value;
    if (value) {
      isPlaying = false;
      _previewRelease = Completer<void>();
    } else {
      notifyPreviewReleased();
      _previewRelease = null;
    }
    notifyListeners();
  }

  /// Releases Studio preview decoders before Media3 export starts. Three Live
  /// or 1080p sources otherwise keep three ExoPlayers alive and the export
  /// decoder pool runs out of memory.
  Future<void> prepareExport() async {
    setExporting(true);
    final gate = _previewRelease;
    if (gate == null) return;
    if (!hasListeners) {
      notifyPreviewReleased();
      return;
    }
    try {
      await gate.future.timeout(const Duration(milliseconds: 1500));
    } on TimeoutException {
      // Widget tests and a missing renderer must not block export.
    }
  }

  void notifyPreviewReleased() {
    final gate = _previewRelease;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  @override
  void dispose() {
    notifyPreviewReleased();
    super.dispose();
  }
}
