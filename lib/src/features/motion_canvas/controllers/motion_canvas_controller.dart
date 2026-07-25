import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';

import '../../../models/media_asset.dart';
import '../models/motion_canvas_layout.dart';
import '../models/motion_clip.dart';
import '../renderer/video_crop_engine.dart';

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
          focus: const CropFocus(),
          subject: SubjectKind.landscape,
        );
      }) {
    applyTemplate(MotionTemplate.travelDiary, notify: false);
  }

  static const motion = Duration(milliseconds: 320);
  static const curve = Curves.easeInOutCubic;

  final VideoCropEngine cropEngine = const VideoCropEngine();
  final MotionCanvasLayout layout = const MotionCanvasLayout();
  List<MotionClip> clips;
  MotionTemplate template = MotionTemplate.travelDiary;
  MotionTransition transition = MotionTransition.softBlurBlend;
  MotionStyle style = MotionStyle.cinematic;
  MotionTool activeTool = MotionTool.layout;
  MotionExportFormat exportFormat = MotionExportFormat.motionPhoto;
  int activeClipIndex = 0;
  int positionMs = 0;
  bool isPlaying = false;
  bool isExporting = false;
  bool musicEnabled = true;

  int get durationMs => clips
      .map((clip) => clip.durationMs)
      .reduce((a, b) => a < b ? a : b)
      .clamp(500, 6000);

  MotionClip get activeClip => clips[activeClipIndex];

  void applyTemplate(MotionTemplate value, {bool notify = true}) {
    template = value;
    style = switch (value) {
      MotionTemplate.travelDiary => MotionStyle.cinematic,
      MotionTemplate.sunsetStory => MotionStyle.dusk,
      MotionTemplate.filmStrip => MotionStyle.film,
      MotionTemplate.minimalMemory => MotionStyle.clean,
    };
    clips = [
      for (var i = 0; i < clips.length; i++)
        clips[i].copyWith(focus: cropEngine.estimateFocus(clips[i], value, i)),
    ];
    if (notify) notifyListeners();
  }

  void createMemory() {
    transition = MotionTransition.softBlurBlend;
    applyTemplate(template);
  }

  void selectClip(int index) {
    activeClipIndex = index.clamp(0, clips.length - 1);
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

  void selectTool(MotionTool value) {
    activeTool = value;
    notifyListeners();
  }

  void setTransition(MotionTransition value) {
    transition = value;
    notifyListeners();
  }

  void setStyle(MotionStyle value) {
    style = value;
    notifyListeners();
  }

  void setExportFormat(MotionExportFormat value) {
    exportFormat = value;
    notifyListeners();
  }

  void toggleMusic() {
    musicEnabled = !musicEnabled;
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
