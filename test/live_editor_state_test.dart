import 'package:after_frame/src/live_editor/models/live_editor_state.dart';
import 'package:after_frame/src/models/live_rules.dart';
import 'package:after_frame/src/models/media_asset.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const asset = MediaAsset(
    uri: 'content://video/1',
    name: 'sample.mp4',
    durationMs: 8000,
    width: 1080,
    height: 1920,
    rotation: 0,
  );
  const short = MediaAsset(
    uri: 'content://video/short',
    name: 'short.mp4',
    durationMs: 2400,
    width: 1920,
    height: 1080,
    rotation: 0,
  );
  const middle = MediaAsset(
    uri: 'content://video/middle',
    name: 'middle.mp4',
    durationMs: 5200,
    width: 1080,
    height: 1080,
    rotation: 0,
  );

  test('initializes the existing six-second editing window', () {
    final state = LiveEditorState(assets: const [asset]);
    addTearDown(state.dispose);

    expect(state.videoPath, asset.uri);
    expect(state.duration, 8000);
    expect(state.startTime, 0);
    expect(state.endTime, 6000);
    expect(state.coverFrame, 3000);
    expect(state.audioEnabled, isTrue);
    expect(state.loopEnabled, isFalse);
  });

  test('timeline changes keep cover and position inside the selection', () {
    final state = LiveEditorState(assets: const [asset]);
    addTearDown(state.dispose);

    state.setCoverFrame(5000);
    state.setTimeline(1000, 4000);

    expect(state.startTime, 1000);
    expect(state.endTime, 4000);
    expect(state.coverFrame, 4000);
    expect(state.currentPosition, 4000);
  });

  test('rejects a range shorter than the existing minimum', () {
    final state = LiveEditorState(assets: const [asset]);
    addTearDown(state.dispose);

    state.setTimeline(1000, 1200);

    expect(state.startTime, 0);
    expect(state.endTime, 6000);
  });

  test('cover suggestions select deterministic extracted moments', () {
    final state = LiveEditorState(assets: const [asset]);
    addTearDown(state.dispose);
    state.setFrames(
      List.generate(
        9,
        (index) => FrameSample(path: 'frame-$index.jpg', timeMs: index * 750),
      ),
    );

    expect(state.coverSelectionMode, CoverSelectionMode.suggested);
    expect(state.coverFrame, 3750);

    state.applyCoverSuggestion(CoverSuggestion.earlierMoment);
    expect(state.coverFrame, 2250);
    expect(state.currentPosition, state.coverFrame);
  });

  test('one source produces a single frame without any mode choice', () {
    final state = LiveEditorState(assets: const [asset]);
    addTearDown(state.dispose);

    expect(state.composition, LiveComposition.singleFrame);
    expect(state.assets, hasLength(1));
  });

  test('two or more sources produce a canvas on the shortest window', () {
    final state = LiveEditorState(assets: const [asset, short]);
    addTearDown(state.dispose);

    expect(state.composition, LiveComposition.adaptiveCanvas);
    expect(state.duration, 2400);
    expect(state.endTime, 2400);
  });

  test('a source list longer than the canvas limit is truncated', () {
    final state = LiveEditorState(
      assets: const [asset, short, middle, asset],
    );
    addTearDown(state.dispose);

    expect(state.assets, hasLength(maxLiveSources));
  });

  test('manual cover selection and enhancement are reflected in state', () {
    final state = LiveEditorState(assets: const [asset]);
    addTearDown(state.dispose);

    state.setCoverFrame(1800);
    state.toggleEnhancement();

    expect(state.coverSelectionMode, CoverSelectionMode.manual);
    expect(state.coverFrame, 1800);
    expect(state.enhancementEnabled, isFalse);
  });

  test('preview position is constrained to the selected live range', () {
    final state = LiveEditorState(assets: const [asset]);
    addTearDown(state.dispose);
    state.setTimeline(1000, 4000);

    state.setCurrentPosition(2500);
    expect(state.currentPosition, 2500);

    state.setCurrentPosition(7000);
    expect(state.currentPosition, 4000);
  });

  test('dropping to one source returns Studio to the single-frame rule', () {
    final state = LiveEditorState(assets: const [asset, short]);
    addTearDown(state.dispose);
    state.finishLoading();

    final needsFrames = state.syncSources(const [short]);

    expect(needsFrames, isTrue);
    expect(state.composition, LiveComposition.singleFrame);
    expect(state.asset.uri, short.uri);
    expect(state.duration, short.durationMs);
    expect(state.endTime, 2400);
    expect(state.isLoading, isTrue);
  });

  test('a still-multi-source canvas re-plans without extracting frames', () {
    final state = LiveEditorState(assets: const [asset, short, middle]);
    addTearDown(state.dispose);
    state.finishLoading();
    expect(state.duration, 2400);

    final needsFrames = state.syncSources(const [asset, middle]);

    expect(needsFrames, isFalse);
    expect(state.composition, LiveComposition.adaptiveCanvas);
    expect(state.duration, 5200);
    expect(state.endTime, 5200);
    expect(state.isLoading, isFalse);
  });

  test('an unchanged single-frame subject keeps its timeline strip', () {
    final state = LiveEditorState(assets: const [asset, short]);
    addTearDown(state.dispose);
    state.syncSources(const [asset]);
    state.setFrames(const [FrameSample(path: 'frame.jpg', timeMs: 0)]);

    expect(state.syncSources(const [asset]), isFalse);
    expect(state.frames, hasLength(1));
  });
}
