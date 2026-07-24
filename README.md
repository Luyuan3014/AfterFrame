# AfterFrame · 余帧

一个将视频中的珍贵瞬间转化为动态记忆的影像创作 App。

## 当前版本

这是面向 Android 的 Flutter + Native Media Engine MVP，已经打通：

1. 系统相册选择视频（支持持久 URI 权限）
2. 原生解析时长、尺寸、旋转信息
3. 原生批量抽取时间轴画面与精确封面帧
4. 选择 Live 起止区间、封面、声音和循环属性
5. Live 单帧 / Live 拼图创作入口与布局预览
6. 使用 `MediaExtractor + MediaMuxer` 无损截取 MP4 轨道
7. 封装并导出 AfterFrame `.live` 开放容器
8. 本次会话内作品库展示

## `.live` 容器规范 v1

`.live` 是 ZIP 兼容容器，不依赖厂商私有 Live Photo 格式：

```text
memory.live
├── manifest.json   # 版本、尺寸、时长、封面时间、音频与循环属性
├── cover.jpg       # 静态封面
└── motion.mp4      # 所选动态区间
```

Android 导出目录：

```text
Android/data/com.example.after_frame/files/Movies/AfterFrame/
```

## 架构

```text
Flutter Product UI
  └── MediaEngine (MethodChannel)
      └── Android Native Engine
          ├── ACTION_OPEN_DOCUMENT
          ├── MediaMetadataRetriever
          ├── MediaExtractor / MediaMuxer
          └── AfterFrame Live Packager
```

Flutter 负责交互、编排和作品状态；Kotlin 负责 URI、帧提取、轨道裁剪和容器封装。后续可将 Native Engine 内部替换为 Media3 Transformer 或 FFmpeg，而不改创作层 API。

## 运行

```bash
flutter pub get
flutter run -d <android-device>
```

## 下一阶段建议

- 引入 Media3 ExoPlayer，提供工作台内准确动态预览
- 引入 Media3 Transformer，实现非关键帧精确裁剪、HDR/色彩空间与编码兼容
- 使用 Room/SQLite 持久化作品索引和草稿
- 实现多视频拼图合成、同步策略和独立时间轴
- 通过 Android Sharesheet 分享 `.live`，并提供 MP4/GIF/静态图兼容导出
- 补充后台任务、导出进度、取消、存储清理和低内存保护
- 将 applicationId 从示例包名迁移为正式品牌域名

> 说明：MVP 的 MP4 裁剪从所选区间前一个关键帧开始，这是无转码方案的正常行为；需要帧级精确起点时，应在下一阶段启用 Media3 Transformer 转码。
