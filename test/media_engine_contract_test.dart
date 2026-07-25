import 'package:after_frame/src/models/media_asset.dart';
import 'package:after_frame/src/services/media_engine.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.afterframe/media_engine');
  const asset = MediaAsset(
    uri: 'content://video/1',
    name: 'one.mp4',
    durationMs: 5000,
    width: 1080,
    height: 1920,
    rotation: 0,
  );
  const second = MediaAsset(
    uri: 'content://video/2',
    name: 'two.mp4',
    durationMs: 4500,
    width: 1080,
    height: 1920,
    rotation: 0,
  );

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('exportLive forwards speed, enhancement and collage strategy', () async {
    MethodCall? captured;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          captured = call;
          return {
            'liveUri': 'content://image/1',
            'galleryUri': 'content://video/1',
            'coverUri': 'content://image/1',
            'coverPath': '/files/cover.jpg',
            'displayName': 'memory',
            'albumName': 'AfterFrame',
          };
        });

    await const MediaEngine().exportLive(
      asset: asset,
      startMs: 200,
      endMs: 4200,
      coverMs: 1800,
      coverPath: '/cache/cover.jpg',
      keepAudio: true,
      loop: true,
      playbackSpeed: 1.5,
      enhancementEnabled: true,
      collageAssets: const [asset, second],
      collageLayout: 2,
      collageAudioSourceIndex: 1,
      collageStartMs: const [200, 400],
      collageEndMs: const [4200, 4000],
      motionTransition: 2,
      cropFocusX: const [.5, .44],
      cropFocusY: const [.35, .52],
    );

    expect(captured?.method, 'exportLive');
    final arguments = captured?.arguments as Map<Object?, Object?>;
    expect(arguments['playbackSpeed'], 1.5);
    expect(arguments['enhancementEnabled'], isTrue);
    expect(arguments['collageUris'], [asset.uri, second.uri]);
    expect(arguments['collageLayout'], 2);
    expect(arguments['collageAudioSourceIndex'], 1);
    expect(arguments['collageStartMs'], [200, 400]);
    expect(arguments['collageEndMs'], [4200, 4000]);
    expect(arguments['motionTransition'], 2);
  });

  test('deleteExport forwards the durable work identity', () async {
    MethodCall? captured;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          captured = call;
          return null;
        });
    final export = LiveExport(
      path: 'content://images/7',
      createdAt: DateTime.fromMillisecondsSinceEpoch(1),
      coverPath: '/files/cover.jpg',
    );

    await const MediaEngine().deleteExport(export);

    expect(captured?.method, 'deleteExport');
    expect(captured?.arguments, {
      'liveUri': export.path,
      'coverPath': export.coverPath,
      'displayName': export.displayName,
    });
  });
}
