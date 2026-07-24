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
      'liveFrame': 'Live 单帧',
      'liveFrameDetail': '视频 · 封面 · 动态',
      'motionCollage': 'Live 拼图',
      'motionCollageDetail': '多格 · 同步 · 叙事',
      'newMemory': '新的记忆',
      'startFromVideo': '从视频开始',
      'startFromVideoDetail': '选择一段视频，捕捉你的动态记忆',
      'importVideo': '导入视频',
      'tipTitle': '余帧提示',
      'tipBody': '2～6 秒的片段，最适合做成动态记忆。',
      'myWorks': '我的余帧',
      'workCount': '{count} 个动态记忆',
      'emptyWorks': '还没有被留下的瞬间',
      'emptyWorksHint': '从相册选一段视频开始吧',
      'createFirst': '创建第一张余帧',
      'profileTitle': '我的',
      'collector': '记忆收藏家',
      'settings': '设置',
      'appLanguage': 'App 语言',
      'languageHint': '切换后全局立即生效',
      'chinese': '中文',
      'english': 'English',
      'exportQuality': '导出画质',
      'originalQuality': '原始画质',
      'liveContainer': 'Live 容器',
      'about': '关于余帧',
      'album': '作品相册',
      'albumValue': 'AfterFrame',
      'pickVideo': '选择视频',
      'pickCollageVideos': '选择拼图视频',
      'pickHint': '按选择顺序添加，可多选',
      'selectedCount': '已选择 {count} 段视频',
      'libraryEmpty': '媒体库里还没有视频',
      'libraryEmptyHint': '拍摄或保存视频后，它会出现在这里',
      'selectedInOrder': '已按顺序选择 {count} 段',
      'addCount': '添加 ({count})',
      'doneCount': '完成 ({count})',
      'allowVideos': '允许访问你的视频',
      'permissionDetail': 'AfterFrame 只读取你选择用于创作的视频，不会上传媒体库内容。',
      'continuePermission': '继续授权',
      'studioSubtitle': '创造你的动态瞬间',
      'export': '导出',
      'readingVideo': '正在读懂这段视频…',
      'momentSaved': '这一刻，留下了',
      'savedToAlbum': '已保存到手机相册 · AfterFrame',
      'shareToChat': '发送到微信 / 抖音（视频）',
      'shareMotionOriginal': '分享动态照片原文件',
      'shareCompatibilityHint': '聊天应用通常不会保留动态照片元数据；发送视频才能确保对方看到动态和声音。',
      'done': '完成',
      'createMode': '创作模式',
      'shapeMemory': '塑造你的动态记忆',
      'liveFrameDescription': '一个瞬间，一段记忆',
      'collageDescription': '多个瞬间自然流动',
      'coverMoment': '封面瞬间',
      'chooseCover': '选择封面瞬间',
      'aiRecommended': 'AI 推荐',
      'manualSelect': '手动选择',
      'bestLight': '光线最佳',
      'sharpest': '最清晰',
      'bestComposition': '构图最佳',
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
      'chooseLayout': '选择拼图布局',
      'collageMvp': '当前版本使用同一视频的不同时间切片；多视频同步将在下一阶段开放。',
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
      'liveFrame': 'Live Frame',
      'liveFrameDetail': 'Video · Cover · Motion',
      'motionCollage': 'Motion Collage',
      'motionCollageDetail': 'Frames · Sync · Story',
      'newMemory': 'NEW MEMORY',
      'startFromVideo': 'Start with video',
      'startFromVideoDetail': 'Choose a video and capture a living memory',
      'importVideo': 'Import Video',
      'tipTitle': 'AfterFrame Tip',
      'tipBody': 'A 2–6 second clip works best as a living memory.',
      'myWorks': 'My Moments',
      'workCount': '{count} living moments',
      'emptyWorks': 'No moments have been kept yet',
      'emptyWorksHint': 'Choose a video from your gallery to begin',
      'createFirst': 'Create Your First Moment',
      'profileTitle': 'Profile',
      'collector': 'Memory Collector',
      'settings': 'Settings',
      'appLanguage': 'App Language',
      'languageHint': 'Changes apply across the app immediately',
      'chinese': '中文',
      'english': 'English',
      'exportQuality': 'Export Quality',
      'originalQuality': 'Original',
      'liveContainer': 'Live Container',
      'about': 'About AfterFrame',
      'album': 'Saved Album',
      'albumValue': 'AfterFrame',
      'pickVideo': 'Choose Video',
      'pickCollageVideos': 'Choose Collage Videos',
      'pickHint': 'Add in selection order · Multiple selection supported',
      'selectedCount': '{count} videos selected',
      'libraryEmpty': 'No videos in your library',
      'libraryEmptyHint': 'Videos you capture or save will appear here',
      'selectedInOrder': '{count} selected in order',
      'addCount': 'Add ({count})',
      'doneCount': 'Done ({count})',
      'allowVideos': 'Allow access to your videos',
      'permissionDetail':
          'AfterFrame only reads videos you choose for creation and never uploads your library.',
      'continuePermission': 'Continue',
      'studioSubtitle': 'Create your living moment',
      'export': 'Export',
      'readingVideo': 'Understanding your video…',
      'momentSaved': 'Your moment lives on',
      'savedToAlbum': 'Saved to your gallery · AfterFrame',
      'shareToChat': 'Send to WeChat / Douyin (video)',
      'shareMotionOriginal': 'Share Motion Photo file',
      'shareCompatibilityHint':
          'Chat apps may remove Motion Photo metadata. Send the video to preserve motion and sound.',
      'done': 'Done',
      'createMode': 'CREATE MODE',
      'shapeMemory': 'Shape your memory',
      'liveFrameDescription': 'One moment, one memory',
      'collageDescription': 'Multiple moments flow together',
      'coverMoment': 'COVER MOMENT',
      'chooseCover': 'Choose Cover Moment',
      'aiRecommended': 'AI Recommended',
      'manualSelect': 'Manual Select',
      'bestLight': 'Best Light',
      'sharpest': 'Sharpest',
      'bestComposition': 'Best Composition',
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
      'chooseLayout': 'Choose Collage Layout',
      'collageMvp':
          'This version uses moments from one video. Multi-video sync is coming next.',
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
