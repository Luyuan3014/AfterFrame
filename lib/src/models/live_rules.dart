/// The one rule set behind every AfterFrame Live.
///
/// Studio edits an ordered source list. The number of sources decides how the
/// canvas is arranged, and nothing else about the work changes: cover moment,
/// editing window, playback semantics and export are shared. Because of that
/// there is no creation mode to pick — the shape is derived, never chosen.
library;

/// Upper bound for one canvas. Beyond three sources a content-first canvas can
/// no longer keep every frame above a usable resolution.
const int maxLiveSources = 3;

/// Shortest and longest motion a Live may hold, in milliseconds.
const int minLiveDurationMs = 500;
const int maxLiveDurationMs = 6000;

enum LiveComposition {
  /// One source: a full-canvas frame that keeps the original framing without
  /// any crop.
  singleFrame,

  /// Two or three sources: Adaptive Canvas arranges them in the user's order
  /// and plays them synchronized.
  adaptiveCanvas;

  static LiveComposition forSourceCount(int count) =>
      count >= 2 ? adaptiveCanvas : singleFrame;

  bool get isCanvas => this == adaptiveCanvas;
}

/// Playback semantics are identical for every shape, so a work keeps behaving
/// the same way when its source list changes.
abstract final class LiveDefaults {
  static const bool audioEnabled = true;
  static const bool loopEnabled = false;
  static const bool enhancementEnabled = true;
  static const double playbackSpeed = 1;
}
