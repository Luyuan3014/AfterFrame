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

  int get durationMs => clips
      .map((clip) => clip.durationMs)
      .reduce((a, b) => a < b ? a : b)
      .clamp(minLiveDurationMs, maxLiveDurationMs);

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

  void setTrim(int index, int startMs, int endMs) {
    final assetDuration = clips[index].asset.durationMs;
    final safeStart = startMs.clamp(0, assetDuration - minLiveDurationMs);
    final safeEnd = endMs.clamp(safeStart + minLiveDurationMs, assetDuration);
    clips[index] = clips[index].copyWith(
      trimStartMs: safeStart,
      trimEndMs: safeEnd,
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

  void setExporting(bool value) {
    isExporting = value;
    if (value) isPlaying = false;
    notifyListeners();
  }
}
