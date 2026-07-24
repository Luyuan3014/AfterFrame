import 'package:flutter/foundation.dart';

import '../../models/media_asset.dart';

enum CreationMode {
  liveFrame,
  motionCollage;

  static CreationMode fromIndex(int index) {
    return index == 1 ? CreationMode.motionCollage : CreationMode.liveFrame;
  }
}

enum GenerateStatus { idle, processing, success, failed }

enum CoverSelectionMode { aiRecommended, manual }

enum CoverInsight { bestLight, sharpest, bestComposition }

/// Single source of truth for the Live creation workspace.
///
/// Fields reserved for later phases (AI moments, templates and effects) should
/// be added here instead of being owned by individual widgets.
class LiveEditorState extends ChangeNotifier {
  LiveEditorState({
    required MediaAsset asset,
    required this.mode,
    this.audioEnabled = true,
    this.loopEnabled = false,
    this.enhancementEnabled = true,
  }) : _asset = asset,
       videoPath = asset.uri,
       duration = asset.durationMs,
       endTime = asset.durationMs.clamp(1, 6000).toInt(),
       coverFrame = asset.durationMs.clamp(1, 6000).toInt() ~/ 2,
       currentPosition = asset.durationMs.clamp(1, 6000).toInt() ~/ 2;

  MediaAsset _asset;
  MediaAsset get asset => _asset;

  String videoPath;
  int duration;
  int currentPosition;
  int startTime = 0;
  int endTime;
  int coverFrame;
  CreationMode mode;
  bool audioEnabled;
  bool loopEnabled;
  bool enhancementEnabled;
  CoverSelectionMode coverSelectionMode = CoverSelectionMode.aiRecommended;
  CoverInsight selectedInsight = CoverInsight.bestLight;

  /// UI-level extension point. Phase one deliberately does not pass speed to
  /// the native export engine, so video processing behavior remains unchanged.
  double playbackSpeed = 1;

  List<FrameSample> frames = const [];
  bool isLoading = true;
  int activeAssetIndex = 0;
  GenerateStatus generateStatus = GenerateStatus.idle;

  FrameSample? get selectedCover {
    if (frames.isEmpty) return null;
    return frames.reduce(
      (a, b) =>
          (a.timeMs - coverFrame).abs() < (b.timeMs - coverFrame).abs() ? a : b,
    );
  }

  bool get isProcessing => generateStatus == GenerateStatus.processing;

  int get liveLength => endTime - startTime;

  int get bestMomentTime {
    if (frames.isEmpty) return coverFrame;
    return frames[_suggestedFrameIndex(CoverInsight.bestLight)].timeMs;
  }

  void replaceAsset(int index, MediaAsset value) {
    activeAssetIndex = index;
    _asset = value;
    videoPath = value.uri;
    duration = value.durationMs;
    startTime = 0;
    endTime = duration.clamp(1, 6000).toInt();
    coverFrame = endTime ~/ 2;
    currentPosition = coverFrame;
    frames = const [];
    isLoading = true;
    coverSelectionMode = CoverSelectionMode.aiRecommended;
    selectedInsight = CoverInsight.bestLight;
    generateStatus = GenerateStatus.idle;
    notifyListeners();
  }

  void setFrames(List<FrameSample> value) {
    frames = List.unmodifiable(value);
    if (coverSelectionMode == CoverSelectionMode.aiRecommended &&
        frames.isNotEmpty) {
      _applyInsight(selectedInsight, notify: false);
    }
    notifyListeners();
  }

  void finishLoading() {
    isLoading = false;
    notifyListeners();
  }

  void setMode(CreationMode value) {
    if (mode == value) return;
    mode = value;
    notifyListeners();
  }

  void setCoverFrame(int value, {bool manual = true}) {
    final next = value.clamp(startTime, endTime).toInt();
    if (coverFrame == next &&
        (!manual || coverSelectionMode == CoverSelectionMode.manual)) {
      return;
    }
    coverFrame = next;
    currentPosition = next;
    if (manual) coverSelectionMode = CoverSelectionMode.manual;
    notifyListeners();
  }

  void setCoverSelectionMode(CoverSelectionMode value) {
    if (coverSelectionMode == value) return;
    coverSelectionMode = value;
    if (value == CoverSelectionMode.aiRecommended) {
      _applyInsight(selectedInsight, notify: false);
    }
    notifyListeners();
  }

  void applyCoverInsight(CoverInsight value) {
    selectedInsight = value;
    coverSelectionMode = CoverSelectionMode.aiRecommended;
    _applyInsight(value, notify: false);
    notifyListeners();
  }

  void _applyInsight(CoverInsight value, {required bool notify}) {
    if (frames.isNotEmpty) {
      final frame = frames[_suggestedFrameIndex(value)];
      coverFrame = frame.timeMs.clamp(startTime, endTime).toInt();
      currentPosition = coverFrame;
    }
    if (notify) notifyListeners();
  }

  int _suggestedFrameIndex(CoverInsight value) {
    if (frames.length <= 1) return 0;
    final ratio = switch (value) {
      CoverInsight.bestLight => .625,
      CoverInsight.sharpest => .5,
      CoverInsight.bestComposition => .375,
    };
    return ((frames.length - 1) * ratio).round();
  }

  void setTimeline(int start, int end) {
    if (end - start < 500) return;
    startTime = start;
    endTime = end;
    coverFrame = coverFrame.clamp(startTime, endTime).toInt();
    currentPosition = currentPosition.clamp(startTime, endTime).toInt();
    notifyListeners();
  }

  void setCurrentPosition(int value) {
    final next = value.clamp(startTime, endTime).toInt();
    if (currentPosition == next) return;
    currentPosition = next;
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
    playbackSpeed = value;
    notifyListeners();
  }

  void setGenerateStatus(GenerateStatus value) {
    if (generateStatus == value) return;
    generateStatus = value;
    notifyListeners();
  }
}
