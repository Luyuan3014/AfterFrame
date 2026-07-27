import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';

import '../../../models/media_asset.dart';
import '../models/motion_canvas_layout.dart';
import '../models/motion_clip.dart';

class MotionCanvasController extends ChangeNotifier {
  MotionCanvasController({required List<MediaAsset> assets})
    : clips = List.generate(assets.length.clamp(1, 3), (index) {
        final asset = assets[index];
        final end = asset.durationMs.clamp(500, 6000).toInt();
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
  bool audioEnabled = true;
  bool loopEnabled = true;
  bool enhancementEnabled = false;
  double playbackSpeed = 1;

  AdaptiveCanvasPlan get canvasPlan => layout.planFor(
    clips
        .map((clip) {
          final rotated =
              clip.asset.rotation == 90 || clip.asset.rotation == 270;
          return CanvasSourceGeometry(
            width: rotated ? clip.asset.height : clip.asset.width,
            height: rotated ? clip.asset.width : clip.asset.height,
            focusX: clip.focus.x,
            focusY: clip.focus.y,
            subjectConfidence: clip.focus.confidence,
          );
        })
        .toList(growable: false),
  );

  List<CanvasFrame> get frames => canvasPlan.frames;

  int get durationMs => clips
      .map((clip) => clip.durationMs)
      .reduce((a, b) => a < b ? a : b)
      .clamp(500, 6000);

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

  void setTrim(int index, int startMs, int endMs) {
    final assetDuration = clips[index].asset.durationMs;
    final safeStart = startMs.clamp(0, assetDuration - 500);
    final safeEnd = endMs.clamp(safeStart + 500, assetDuration);
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

  void setThumbnail(int index, String path) {
    clips[index] = clips[index].copyWith(thumbnailPath: path);
    notifyListeners();
  }

  void setExporting(bool value) {
    isExporting = value;
    if (value) isPlaying = false;
    notifyListeners();
  }
}
