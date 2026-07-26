import 'package:flutter/services.dart';

const _defaultManifestUrl =
    'https://gitee.com/luyuan567/after_frame_update/raw/master/update.json';

/// Can be overridden without editing source:
/// --dart-define=AFTERFRAME_UPDATE_MANIFEST_URL=https://gitee.com/.../update.json
const afterFrameUpdateManifestUrl = String.fromEnvironment(
  'AFTERFRAME_UPDATE_MANIFEST_URL',
  defaultValue: _defaultManifestUrl,
);

enum AppUpdateStatus {
  idle,
  noUpdate,
  available,
  downloading,
  verifying,
  ready,
  error;

  static AppUpdateStatus parse(String? value) => switch (value) {
    'no_update' => noUpdate,
    'available' => available,
    'downloading' => downloading,
    'verifying' => verifying,
    'ready' => ready,
    'error' => error,
    _ => idle,
  };
}

class AppUpdateState {
  const AppUpdateState({
    required this.status,
    required this.currentVersionName,
    required this.currentVersionCode,
    required this.abi,
    this.versionName,
    this.versionCode,
    this.notes,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
    this.errorCode,
  });

  factory AppUpdateState.fromMap(Map<Object?, Object?> map) => AppUpdateState(
    status: AppUpdateStatus.parse(map['status'] as String?),
    currentVersionName: map['currentVersionName'] as String? ?? '',
    currentVersionCode: (map['currentVersionCode'] as num?)?.toInt() ?? 0,
    abi: map['abi'] as String? ?? '',
    versionName: map['versionName'] as String?,
    versionCode: (map['versionCode'] as num?)?.toInt(),
    notes: map['notes'] as String?,
    downloadedBytes: (map['downloadedBytes'] as num?)?.toInt() ?? 0,
    totalBytes: (map['totalBytes'] as num?)?.toInt() ?? 0,
    errorCode: map['errorCode'] as String?,
  );

  final AppUpdateStatus status;
  final String currentVersionName;
  final int currentVersionCode;
  final String abi;
  final String? versionName;
  final int? versionCode;
  final String? notes;
  final int downloadedBytes;
  final int totalBytes;
  final String? errorCode;

  double? get progress =>
      totalBytes > 0 ? (downloadedBytes / totalBytes).clamp(0.0, 1.0) : null;
}

class AppUpdateService {
  const AppUpdateService();

  static const _channel = MethodChannel('com.afterframe/media_engine');

  bool get isConfigured => afterFrameUpdateManifestUrl.isNotEmpty;

  Future<AppUpdateState> state() async => _invoke('getUpdateState');

  Future<AppUpdateState> check() {
    if (!isConfigured) {
      throw StateError('AFTERFRAME_UPDATE_MANIFEST_URL is not configured');
    }
    return _invoke('checkForUpdate', {
      'manifestUrl': afterFrameUpdateManifestUrl,
    });
  }

  Future<AppUpdateState> download() => _invoke('startUpdateDownload');

  Future<String> install() async {
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'installVerifiedUpdate',
    );
    return result?['status'] as String? ?? 'installer_opened';
  }

  Future<AppUpdateState> _invoke(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      method,
      arguments,
    );
    if (result == null) throw StateError('Missing native update state');
    return AppUpdateState.fromMap(result);
  }
}
