import 'package:after_frame/src/models/media_asset.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Live photos keep a stable library identity after extraction', () {
    final listed = MediaAsset.fromMap(const {
      'uri': 'content://images/7',
      'name': 'MVIMG_001.jpg',
      'durationMs': 0,
      'width': 1080,
      'height': 1920,
      'rotation': 0,
      'kind': 'motionPhoto',
      'libraryUri': 'content://images/7',
      'stillUri': 'content://images/7',
    });
    final playable = MediaAsset.fromMap(const {
      'uri': 'file:///cache/7.mp4',
      'name': 'MVIMG_001.jpg',
      'durationMs': 2800,
      'width': 1080,
      'height': 1920,
      'rotation': 0,
      'kind': 'motionPhoto',
      'libraryUri': 'content://images/7',
      'stillUri': 'content://images/7',
    });

    expect(listed.isMotionPhoto, isTrue);
    expect(listed.durationLabel, 'LIVE');
    expect(listed.identity, playable.identity);
    expect(playable.thumbnailUri, 'content://images/7');
    expect(playable.uri, 'file:///cache/7.mp4');
    expect(playable.durationLabel, '00:02');
  });

  test('ordinary videos keep backward-compatible maps', () {
    const asset = MediaAsset(
      uri: 'content://video/1',
      name: 'clip.mp4',
      durationMs: 5400,
      width: 1920,
      height: 1080,
      rotation: 0,
    );

    expect(asset.kind, MediaKind.video);
    expect(asset.identity, asset.uri);
    expect(asset.thumbnailUri, asset.uri);
    expect(asset.durationLabel, '00:05');
  });
}
