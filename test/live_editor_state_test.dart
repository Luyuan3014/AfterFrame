import 'package:after_frame/src/live_editor/models/live_editor_state.dart';
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

  test('initializes the existing six-second editing window', () {
    final state = LiveEditorState(asset: asset, mode: CreationMode.liveFrame);
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
    final state = LiveEditorState(asset: asset, mode: CreationMode.liveFrame);
    addTearDown(state.dispose);

    state.setCoverFrame(5000);
    state.setTimeline(1000, 4000);

    expect(state.startTime, 1000);
    expect(state.endTime, 4000);
    expect(state.coverFrame, 4000);
    expect(state.currentPosition, 4000);
  });

  test('rejects a range shorter than the existing minimum', () {
    final state = LiveEditorState(asset: asset, mode: CreationMode.liveFrame);
    addTearDown(state.dispose);

    state.setTimeline(1000, 1200);

    expect(state.startTime, 0);
    expect(state.endTime, 6000);
  });

  test('replacing an asset resets media-specific state', () {
    final state = LiveEditorState(
      asset: asset,
      mode: CreationMode.motionCollage,
    );
    addTearDown(state.dispose);
    const replacement = MediaAsset(
      uri: 'content://video/2',
      name: 'short.mp4',
      durationMs: 2400,
      width: 1920,
      height: 1080,
      rotation: 0,
    );

    state.replaceAsset(1, replacement);

    expect(state.activeAssetIndex, 1);
    expect(state.videoPath, replacement.uri);
    expect(state.endTime, 2400);
    expect(state.coverFrame, 1200);
    expect(state.isLoading, isTrue);
    expect(state.mode, CreationMode.motionCollage);
  });

  test('cover suggestions select deterministic extracted moments', () {
    final state = LiveEditorState(asset: asset, mode: CreationMode.liveFrame);
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

  test('collage mode uses the shortest source duration', () {
    const short = MediaAsset(
      uri: 'content://video/2',
      name: 'short.mp4',
      durationMs: 3200,
      width: 1920,
      height: 1080,
      rotation: 0,
    );
    final state = LiveEditorState(
      asset: asset,
      assets: const [asset, short],
      mode: CreationMode.motionCollage,
    );
    addTearDown(state.dispose);

    expect(state.duration, 3200);
    expect(state.endTime, 3200);
  });

  test('manual cover selection and enhancement are reflected in state', () {
    final state = LiveEditorState(asset: asset, mode: CreationMode.liveFrame);
    addTearDown(state.dispose);

    state.setCoverFrame(1800);
    state.toggleEnhancement();

    expect(state.coverSelectionMode, CoverSelectionMode.manual);
    expect(state.coverFrame, 1800);
    expect(state.enhancementEnabled, isFalse);
  });

  test('preview position is constrained to the selected live range', () {
    final state = LiveEditorState(asset: asset, mode: CreationMode.liveFrame);
    addTearDown(state.dispose);
    state.setTimeline(1000, 4000);

    state.setCurrentPosition(2500);
    expect(state.currentPosition, 2500);

    state.setCurrentPosition(7000);
    expect(state.currentPosition, 4000);
  });

  test('single-source Studio refuses an invalid collage mode', () {
    final state = LiveEditorState(asset: asset, mode: CreationMode.liveFrame);
    addTearDown(state.dispose);

    state.setMode(CreationMode.motionCollage);

    expect(state.canUseCollage, isFalse);
    expect(state.mode, CreationMode.liveFrame);
  });

  test('Studio mode switching recalculates the shared editing window', () {
    const short = MediaAsset(
      uri: 'content://video/short',
      name: 'short.mp4',
      durationMs: 2400,
      width: 1920,
      height: 1080,
      rotation: 0,
    );
    final state = LiveEditorState(
      asset: asset,
      assets: const [asset, short],
      mode: CreationMode.liveFrame,
    );
    addTearDown(state.dispose);

    state.setMode(CreationMode.motionCollage);
    expect(state.canUseCollage, isTrue);
    expect(state.duration, 2400);
    expect(state.endTime, 2400);

    state.setMode(CreationMode.liveFrame);
    expect(state.duration, asset.durationMs);
    expect(state.endTime, 6000);
  });
}
