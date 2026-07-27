import 'package:flutter/foundation.dart';

import '../../models/live_rules.dart';
import '../../models/media_asset.dart';

enum GenerateStatus { idle, processing, success, failed }

enum CoverSelectionMode { suggested, manual }

enum CoverSuggestion { laterMoment, middleMoment, earlierMoment }

/// Single source of truth for the Live creation workspace.
///
/// Studio always edits an ordered source list. The number of sources decides
/// the work's shape, so there is no editable mode here. Future templates and
/// effects should be added to this class instead of individual widgets.
class LiveEditorState extends ChangeNotifier {
  factory LiveEditorState({
    required List<MediaAsset> assets,
    bool audioEnabled = LiveDefaults.audioEnabled,
    bool loopEnabled = LiveDefaults.loopEnabled,
    bool enhancementEnabled = LiveDefaults.enhancementEnabled,
  }) {
    assert(assets.isNotEmpty, 'Studio needs at least one source.');
    final sources = List<MediaAsset>.unmodifiable(
      assets.take(maxLiveSources),
    );
    return LiveEditorState._(
      sources: sources,
      window: _syncedDuration(sources),
      audioEnabled: audioEnabled,
      loopEnabled: loopEnabled,
      enhancementEnabled: enhancementEnabled,
    );
  }

  LiveEditorState._({
    required List<MediaAsset> sources,
    required int window,
    required this.audioEnabled,
    required this.loopEnabled,
    required this.enhancementEnabled,
  }) : _sources = sources,
       videoPath = sources.first.uri,
       duration = window,
       endTime = window.clamp(1, maxLiveDurationMs).toInt(),
       coverFrame = window.clamp(1, maxLiveDurationMs).toInt() ~/ 2,
       currentPosition = window.clamp(1, maxLiveDurationMs).toInt() ~/ 2;

  List<MediaAsset> _sources;
  List<MediaAsset> get assets => _sources;

  /// Editing subject and primary audio track. It is always the first source in
  /// the user's order.
  MediaAsset get asset => _sources.first;

  /// The work's shape follows the number of sources. It is never a user choice,
  /// so nothing in the editor is allowed to set it.
  LiveComposition get composition =>
      LiveComposition.forSourceCount(_sources.length);

  String videoPath;
  int duration;
  int currentPosition;
  int startTime = 0;
  int endTime;
  int coverFrame;
  bool audioEnabled;
  bool loopEnabled;
  bool enhancementEnabled;
  CoverSelectionMode coverSelectionMode = CoverSelectionMode.suggested;
  CoverSuggestion selectedSuggestion = CoverSuggestion.laterMoment;

  /// UI-level extension point. Phase one deliberately does not pass speed to
  /// the native export engine, so video processing behavior remains unchanged.
  double playbackSpeed = LiveDefaults.playbackSpeed;

  List<FrameSample> frames = const [];
  bool isLoading = true;
  GenerateStatus generateStatus = GenerateStatus.idle;

  /// Source whose timeline strip is currently held in [frames]. Tracking it
  /// keeps the single-frame cover strip honest when the source list changes.
  String? _framesUri;

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
    return frames[_suggestedFrameIndex(CoverSuggestion.laterMoment)].timeMs;
  }

  /// Shortest synchronized window across the sources. A single source keeps its
  /// own duration, so one rule covers both shapes.
  static int _syncedDuration(List<MediaAsset> sources) => sources
      .map((item) => item.durationMs)
      .reduce((current, next) => current < next ? current : next);

  /// Adopts a new source list and re-derives the shape and the shared editing
  /// window. Returns `true` when the single-frame timeline strip has to be
  /// extracted again for the new subject.
  bool syncSources(List<MediaAsset> value) {
    if (value.isEmpty) return false;
    _sources = List.unmodifiable(value.take(maxLiveSources));
    videoPath = asset.uri;
    duration = _syncedDuration(_sources);
    startTime = 0;
    endTime = duration.clamp(1, maxLiveDurationMs).toInt();
    coverFrame = endTime ~/ 2;
    currentPosition = coverFrame;
    generateStatus = GenerateStatus.idle;
    final needsFrames =
        composition == LiveComposition.singleFrame && _framesUri != videoPath;
    if (needsFrames) {
      frames = const [];
      isLoading = true;
      coverSelectionMode = CoverSelectionMode.suggested;
      selectedSuggestion = CoverSuggestion.laterMoment;
    }
    notifyListeners();
    return needsFrames;
  }

  void setFrames(List<FrameSample> value) {
    frames = List.unmodifiable(value);
    _framesUri = videoPath;
    if (coverSelectionMode == CoverSelectionMode.suggested &&
        frames.isNotEmpty) {
      _applySuggestion(selectedSuggestion, notify: false);
    }
    notifyListeners();
  }

  void finishLoading() {
    isLoading = false;
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
    if (value == CoverSelectionMode.suggested) {
      _applySuggestion(selectedSuggestion, notify: false);
    }
    notifyListeners();
  }

  void applyCoverSuggestion(CoverSuggestion value) {
    selectedSuggestion = value;
    coverSelectionMode = CoverSelectionMode.suggested;
    _applySuggestion(value, notify: false);
    notifyListeners();
  }

  void _applySuggestion(CoverSuggestion value, {required bool notify}) {
    if (frames.isNotEmpty) {
      final frame = frames[_suggestedFrameIndex(value)];
      coverFrame = frame.timeMs.clamp(startTime, endTime).toInt();
      currentPosition = coverFrame;
    }
    if (notify) notifyListeners();
  }

  int _suggestedFrameIndex(CoverSuggestion value) {
    if (frames.length <= 1) return 0;
    final ratio = switch (value) {
      CoverSuggestion.laterMoment => .625,
      CoverSuggestion.middleMoment => .5,
      CoverSuggestion.earlierMoment => .375,
    };
    return ((frames.length - 1) * ratio).round();
  }

  /// Adopts playback semantics chosen elsewhere so a change of shape never
  /// silently resets the user's settings.
  void adoptSettings({
    required bool audio,
    required bool loop,
    required bool enhancement,
    required double speed,
  }) {
    audioEnabled = audio;
    loopEnabled = loop;
    enhancementEnabled = enhancement;
    playbackSpeed = speed;
    notifyListeners();
  }

  void setTimeline(int start, int end) {
    if (end - start < minLiveDurationMs) return;
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
