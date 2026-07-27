import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum AppLanguage {
  chinese('zh'),
  english('en');

  const AppLanguage(this.code);
  final String code;

  static AppLanguage fromCode(String? value) =>
      value == english.code ? english : chinese;
}

class AppLanguageController extends ChangeNotifier {
  AppLanguageController(this.language);

  static const _channel = MethodChannel('com.afterframe/media_engine');
  AppLanguage language;

  static Future<AppLanguage> load() async {
    try {
      final code = await _channel.invokeMethod<String>('getAppLanguage');
      return AppLanguage.fromCode(code);
    } catch (_) {
      return AppLanguage.chinese;
    }
  }

  Future<void> setLanguage(AppLanguage value) async {
    if (language == value) return;
    language = value;
    notifyListeners();
    try {
      await _channel.invokeMethod<void>('setAppLanguage', {
        'language': value.code,
      });
    } catch (_) {
      // The in-memory preference still applies when persistence is unavailable.
    }
  }
}

class AppLanguageScope extends InheritedNotifier<AppLanguageController> {
  const AppLanguageScope({
    super.key,
    required AppLanguageController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppLanguageController controllerOf(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<AppLanguageScope>();
    assert(scope != null, 'AppLanguageScope is missing above this widget.');
    return scope!.notifier!;
  }

  static AppLocalizations of(BuildContext context) =>
      AppLocalizations(controllerOf(context).language);
}

class AppLocalizations {
  const AppLocalizations(this.language);

  final AppLanguage language;
  bool get isChinese => language == AppLanguage.chinese;

  @visibleForTesting
  static Set<String> keysFor(AppLanguage language) =>
      _translations[language]!.keys.toSet();

  @visibleForTesting
  static Map<String, Set<String>> placeholdersFor(AppLanguage language) =>
      _translations[language]!.map(
        (key, value) => MapEntry(
          key,
          RegExp(
            r'\{([^}]+)\}',
          ).allMatches(value).map((match) => match.group(1)!).toSet(),
        ),
      );

  String text(String key, [Map<String, Object> values = const {}]) {
    var value =
        (_translations[language] ?? _translations[AppLanguage.chinese]!)[key] ??
        key;
    for (final entry in values.entries) {
      value = value.replaceAll('{${entry.key}}', '${entry.value}');
    }
    return value;
  }

  static const _translations = <AppLanguage, Map<String, String>>{
    AppLanguage.chinese: {
      'navCreate': '创作',
      'navWorks': '余帧',
      'navProfile': '我的',
      'brandCn': '余帧',
      'heroTitle': '让过去的某一帧，\n重新发生。',
      'heroSubtitle': '从一段视频里，拾起值得反复观看的瞬间。',
      'createWays': '创作方式',
      'createWaysHint': '把一刻，做成作品',
      'studioEntryTitle': 'AfterFrame Studio',
      'studioEntryDetail': '选 1 段做单帧，选 2～3 段自动排成拼图',
      'newMemory': '新的记忆',
      'startFromVideo': '从视频开始',
      'startFromVideoDetail': '选择一段视频，捕捉你的动态记忆',
      'importVideo': '导入视频',
      'tipTitle': '余帧提示',
      'tipBody': '2～6 秒的片段，最适合做成动态记忆。',
      'myWorks': '我的余帧',
      'previewWork': 'Live 预览',
      'previewMaterial': '预览素材',
      'loopPreview': '循环预览',
      'mute': '静音',
      'unmute': '开启声音',
      'retryThumbnail': '重新加载缩略图',
      'previewUnavailable': '此恢复作品缺少可播放的视频副本',
      'deleteWorkTitle': '删除这张余帧？',
      'deleteWorkDetail': '将同时删除 AfterFrame 相册中的动态照片和应用内预览文件，此操作无法撤销。',
      'cancel': '取消',
      'delete': '删除',
      'workDeleted': '余帧已删除',
      'deletingWork': '正在删除余帧',
      'errorDelete': '删除失败，请重试',
      'workCount': '{count} 个动态记忆',
      'emptyWorks': '还没有被留下的瞬间',
      'emptyWorksHint': '从相册选一段视频开始吧',
      'createFirst': '创建第一张余帧',
      'profileTitle': '我的',
      'collector': '记忆收藏家',
      'settings': '设置',
      'appLanguage': 'App 语言',
      'languageHint': '切换后全局立即生效',
      'checkUpdates': '检查更新',
      'installUpdate': '安装更新',
      'loadingVersion': '正在读取当前版本',
      'alreadyLatest': '当前已是最新版本',
      'newVersionReady': '发现新版本',
      'updateNotes': '本次更新',
      'updateSafetyHint': '将严格匹配当前 ABI，并在安装前校验版本、包名、签名与 SHA-1。',
      'downloadInBackground': '后台下载',
      'later': '稍后',
      'downloadStarted': '已转入后台下载，你可以继续使用 AfterFrame',
      'updateDownloading': '正在后台下载更新',
      'updateVerifying': '正在执行安全校验',
      'updateReadyToInstall': '校验通过，正在打开系统安装器',
      'updateAvailable': '有新版本可下载',
      'updateInterrupted': '更新未完成，点按重新检查',
      'updateCheckFailed': '检查更新失败，请确认网络和 Gitee 发布清单',
      'updateDownloadFailed': '无法开始下载，请稍后重试',
      'updateVerifyFailed': '更新包未通过安全校验，已拒绝安装',
      'allowInstallHint': '请允许 AfterFrame 安装更新，返回后会自动继续',
      'updateNotConfigured': '尚未配置 Gitee 更新清单地址',
      'chinese': '中文',
      'english': 'English',
      'exportQuality': '导出画质',
      'originalQuality': '原始画质',
      'liveContainer': 'Live 容器',
      'about': '关于余帧',
      'album': '作品相册',
      'albumValue': 'AfterFrame',
      'pickVideo': '选择视频',
      'pickStudioVideos': '选择创作素材',
      'pickHint': '选 1 段做单帧，选 2～3 段自动排成拼图',
      'sourceLimit': '一张余帧最多 3 段素材',
      'selectedCount': '已选择 {count} 段视频',
      'libraryEmpty': '媒体库里还没有视频',
      'libraryEmptyHint': '拍摄或保存视频后，它会出现在这里',
      'willCreate': '将生成',
      'roomForMore': '还可再加 {count} 段',
      'enterStudio': '进入 Studio',
      'singleFrameSummary': 'Live 单帧 · 保留原始画幅',
      'canvasSummary': 'Live 拼图 · {count} 格',
      'singleFrameDetail': '封面 · 时间轴 · 动态导出',
      'canvasDetail': '按选择顺序自动排版 · 同步播放',
      'allowVideos': '允许访问你的视频',
      'permissionDetail': 'AfterFrame 只读取你选择用于创作的视频，不会上传媒体库内容。',
      'continuePermission': '继续授权',
      'fullscreenExitHint': '下滑退出全屏',
      'export': '导出',
      'readingVideo': '正在读懂这段视频…',
      'momentSaved': '这一刻，留下了',
      'savedToAlbum': '已保存到手机相册 · AfterFrame',
      'shareToChat': '发送到微信 / 抖音（视频）',
      'shareMotionOriginal': '分享动态照片原文件',
      'shareCompatibilityHint': '聊天应用通常不会保留动态照片元数据；发送视频才能确保对方看到动态和声音。',
      'done': '完成',
      'undo': '撤销',
      'canvasPreviewBadge': 'AFTER LIVE · {count} 格',
      'canvasTrackHint': '点按裁剪，长按拖动排序，× 移除；版式随素材比例自动优化，只剩 1 段时回到单帧。',
      'removeSource': '移除这段素材',
      'sourceRemoved': '已移除 1 段素材',
      'editCollageClip': '裁剪素材 {index}',
      'editCollageClipHint': '每段素材独立取景，最终按最短有效时长同步播放。',
      'smartCropHint': '在画布中拖动当前画面，微调 Smart Crop 取景；素材保持 1:1 像素倍率。',
      'resetSmartCrop': '恢复智能取景',
      'coverMoment': '封面瞬间',
      'chooseCover': '选择封面瞬间',
      'suggestedCovers': '时间候选',
      'manualSelect': '手动选择',
      'laterMoment': '稍晚时刻',
      'middleMoment': '中间时刻',
      'earlierMoment': '稍早时刻',
      'momentTimeline': '瞬间时间轴',
      'findMoment': '发现精彩瞬间',
      'currentTime': '当前时间',
      'liveLength': 'Live 长度',
      'bestMoment': '最佳瞬间',
      'liveRange': 'LIVE 范围',
      'moreSettings': '更多设置',
      'soundOn': '声音开启',
      'muted': '已静音',
      'loop': '循环',
      'once': '单次',
      'sound': '声音',
      'enhance': '增强',
      'speed': '速度',
      'createLive': '生成 AfterFrame Live',
      'creatingLive': '正在生成动态记忆…',
      'createdLive': 'AfterFrame Live 已生成',
      'retryCreate': '重新生成',
      'livingMoment': '动态瞬间',
      'previewLoading': '正在准备视频预览…',
      'previewFailed': '视频预览暂时不可用',
      'unnamedVideo': '未命名视频',
      'errorPermission': '无法获取视频访问权限',
      'errorLibrary': '无法读取视频媒体库',
      'errorInspect': '无法读取视频信息',
      'errorThumbnail': '无法生成视频缩略图',
      'errorFrame': '封面提取失败',
      'errorExport': 'Live 导出失败，请重试',
      'errorShare': '无法打开分享面板，请重试',
      'errorGeneric': '操作失败，请重试',
    },
    AppLanguage.english: {
      'navCreate': 'Create',
      'navWorks': 'Moments',
      'navProfile': 'Profile',
      'brandCn': 'AfterFrame',
      'heroTitle': 'Let one frame from the past\nhappen again.',
      'heroSubtitle': 'Find a moment worth reliving inside every video.',
      'createWays': 'Ways to create',
      'createWaysHint': 'Turn a moment into a work',
      'studioEntryTitle': 'AfterFrame Studio',
      'studioEntryDetail':
          'Pick 1 clip for a single frame, or 2–3 for an auto collage',
      'newMemory': 'NEW MEMORY',
      'startFromVideo': 'Start with video',
      'startFromVideoDetail': 'Choose a video and capture a living memory',
      'importVideo': 'Import Video',
      'tipTitle': 'AfterFrame Tip',
      'tipBody': 'A 2–6 second clip works best as a living memory.',
      'myWorks': 'My Moments',
      'previewWork': 'Live preview',
      'previewMaterial': 'Preview video',
      'loopPreview': 'Looping preview',
      'mute': 'Mute',
      'unmute': 'Unmute',
      'retryThumbnail': 'Reload thumbnail',
      'previewUnavailable':
          'No playable video copy is available for this recovered work',
      'deleteWorkTitle': 'Delete this moment?',
      'deleteWorkDetail':
          'This removes the Motion Photo from the AfterFrame album and its in-app preview files. This cannot be undone.',
      'cancel': 'Cancel',
      'delete': 'Delete',
      'workDeleted': 'Moment deleted',
      'deletingWork': 'Deleting moment',
      'errorDelete': 'Unable to delete this moment. Please try again.',
      'workCount': '{count} living moments',
      'emptyWorks': 'No moments have been kept yet',
      'emptyWorksHint': 'Choose a video from your gallery to begin',
      'createFirst': 'Create Your First Moment',
      'profileTitle': 'Profile',
      'collector': 'Memory Collector',
      'settings': 'Settings',
      'appLanguage': 'App Language',
      'languageHint': 'Changes apply across the app immediately',
      'checkUpdates': 'Check for Updates',
      'installUpdate': 'Install Update',
      'loadingVersion': 'Reading installed version',
      'alreadyLatest': 'You already have the latest version',
      'newVersionReady': 'A New Version Is Ready',
      'updateNotes': "What's New",
      'updateSafetyHint':
          'The ABI is matched exactly, then version, package, signature, and SHA-1 are verified before installation.',
      'downloadInBackground': 'Download in Background',
      'later': 'Later',
      'downloadStarted':
          'Downloading in the background. You can keep using AfterFrame.',
      'updateDownloading': 'Downloading update in the background',
      'updateVerifying': 'Running security checks',
      'updateReadyToInstall': 'Verified. Opening the system installer',
      'updateAvailable': 'A new version is available',
      'updateInterrupted': 'Update did not finish. Tap to check again',
      'updateCheckFailed': 'Unable to check Gitee for updates',
      'updateDownloadFailed': 'Unable to start the download. Try again later.',
      'updateVerifyFailed':
          'The update failed security checks and was rejected',
      'allowInstallHint':
          'Allow AfterFrame to install updates. Installation continues when you return.',
      'updateNotConfigured': 'The Gitee update manifest URL is not configured',
      'chinese': '中文',
      'english': 'English',
      'exportQuality': 'Export Quality',
      'originalQuality': 'Original',
      'liveContainer': 'Live Container',
      'about': 'About AfterFrame',
      'album': 'Saved Album',
      'albumValue': 'AfterFrame',
      'pickVideo': 'Choose Video',
      'pickStudioVideos': 'Choose Studio Material',
      'pickHint': 'Pick 1 clip for a single frame, or 2–3 for an auto collage',
      'sourceLimit': 'A moment holds up to 3 clips',
      'selectedCount': '{count} videos selected',
      'libraryEmpty': 'No videos in your library',
      'libraryEmptyHint': 'Videos you capture or save will appear here',
      'willCreate': 'WILL CREATE',
      'roomForMore': 'room for {count} more',
      'enterStudio': 'Enter Studio',
      'singleFrameSummary': 'Live Frame · original framing',
      'canvasSummary': 'Live Collage · {count} frames',
      'singleFrameDetail': 'Cover · timeline · motion export',
      'canvasDetail': 'Auto layout in your order · synced playback',
      'allowVideos': 'Allow access to your videos',
      'permissionDetail':
          'AfterFrame only reads videos you choose for creation and never uploads your library.',
      'continuePermission': 'Continue',
      'fullscreenExitHint': 'Swipe down to exit full screen',
      'export': 'Export',
      'readingVideo': 'Understanding your video…',
      'momentSaved': 'Your moment lives on',
      'savedToAlbum': 'Saved to your gallery · AfterFrame',
      'shareToChat': 'Send to WeChat / Douyin (video)',
      'shareMotionOriginal': 'Share Motion Photo file',
      'shareCompatibilityHint':
          'Chat apps may remove Motion Photo metadata. Send the video to preserve motion and sound.',
      'done': 'Done',
      'undo': 'Undo',
      'canvasPreviewBadge': 'AFTER LIVE · {count} FRAMES',
      'canvasTrackHint':
          'Tap to trim, hold to reorder, × to remove. Layout adapts to source ratios, and one remaining clip returns to a single frame.',
      'removeSource': 'Remove this clip',
      'sourceRemoved': 'Clip removed',
      'editCollageClip': 'Trim clip {index}',
      'editCollageClipHint':
          'Each clip keeps its own range; playback syncs to the shortest active range.',
      'smartCropHint':
          'Drag the active frame on the canvas to refine Smart Crop. Source pixels remain at 1:1 scale.',
      'resetSmartCrop': 'Reset Smart Crop',
      'coverMoment': 'COVER MOMENT',
      'chooseCover': 'Choose Cover Moment',
      'suggestedCovers': 'Time Suggestions',
      'manualSelect': 'Manual Select',
      'laterMoment': 'Later Moment',
      'middleMoment': 'Middle Moment',
      'earlierMoment': 'Earlier Moment',
      'momentTimeline': 'MOMENT TIMELINE',
      'findMoment': 'Find the moment',
      'currentTime': 'CURRENT TIME',
      'liveLength': 'LIVE LENGTH',
      'bestMoment': 'Best Moment',
      'liveRange': 'LIVE RANGE',
      'moreSettings': 'More Settings',
      'soundOn': 'Sound on',
      'muted': 'Muted',
      'loop': 'Loop',
      'once': 'Once',
      'sound': 'Sound',
      'enhance': 'Enhance',
      'speed': 'Speed',
      'createLive': 'Create AfterFrame Live',
      'creatingLive': 'Creating your living moment…',
      'createdLive': 'AfterFrame Live Created',
      'retryCreate': 'Try Creating Again',
      'livingMoment': 'A living moment',
      'previewLoading': 'Preparing video preview…',
      'previewFailed': 'Video preview is unavailable',
      'unnamedVideo': 'Untitled Video',
      'errorPermission': 'Unable to access your videos',
      'errorLibrary': 'Unable to read the video library',
      'errorInspect': 'Unable to read video details',
      'errorThumbnail': 'Unable to create a video thumbnail',
      'errorFrame': 'Unable to extract the cover frame',
      'errorExport': 'Live export failed. Please try again.',
      'errorShare': 'Unable to open the share sheet. Please try again.',
      'errorGeneric': 'Something went wrong. Please try again.',
    },
  };
}

extension AppLocalizationContext on BuildContext {
  AppLocalizations get l10n => AppLanguageScope.of(this);
}
