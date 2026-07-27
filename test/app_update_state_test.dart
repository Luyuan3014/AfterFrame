import 'package:after_frame/src/services/app_update_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses the production Gitee manifest by default', () {
    expect(
      afterFrameUpdateManifestUrl,
      'https://gitee.com/luyuan567/after_frame_update/raw/master/update.json',
    );
  });

  test('maps native download progress without exceeding one', () {
    final state = AppUpdateState.fromMap({
      'status': 'downloading',
      'currentVersionName': '0.6.0',
      'currentVersionCode': 6,
      'abi': 'arm64-v8a',
      'versionName': '0.7.0',
      'versionCode': 7,
      'downloadedBytes': 120,
      'totalBytes': 100,
    });

    expect(state.status, AppUpdateStatus.downloading);
    expect(state.progress, 1);
    expect(state.abi, 'arm64-v8a');
    expect(state.versionCode, 7);
  });

  test('unknown native state is safely treated as idle', () {
    final state = AppUpdateState.fromMap({
      'status': 'future_state',
      'currentVersionName': '0.6.0',
      'currentVersionCode': 6,
      'abi': 'x86_64',
    });

    expect(state.status, AppUpdateStatus.idle);
    expect(state.progress, isNull);
  });

  test('maps native verification failure details', () {
    final state = AppUpdateState.fromMap({
      'status': 'error',
      'currentVersionName': '0.7.3',
      'currentVersionCode': 2011,
      'abi': 'arm64-v8a',
      'errorCode': 'VERIFY_FAILED',
      'errorDetail': 'APK has no signing certificate',
    });

    expect(state.status, AppUpdateStatus.error);
    expect(state.errorCode, 'VERIFY_FAILED');
    expect(state.errorDetail, 'APK has no signing certificate');
  });
}
