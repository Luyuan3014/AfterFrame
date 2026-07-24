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
}
