# AfterFrame · 余帧

一个将视频中的珍贵瞬间转化为动态记忆的影像创作 App。

当前版本：`0.4.0`

## 当前版本

这是面向 Android 的 Flutter + FFmpeg Native Media Engine MVP，已经打通：

1. 与产品视觉一致的应用内视频媒体库（MediaStore）
2. 原生解析时长、尺寸、旋转信息
3. 原生批量抽取时间轴画面与精确封面帧
4. 选择 Live 起止区间、封面、声音和循环属性
5. Live 单帧与 2～3 素材 Motion Collage 同步合成
6. 使用 FFmpeg filter graph 进行帧准确裁剪、速度调整、轻量增强与 MP4 导出
7. 封装并发布 Android Motion Photo（JPEG + XMP + MP4）
8. Live Studio 内真实视频预览、播放与选区循环
9. 中英文全局切换与偏好持久化
10. Motion Photo 自动保存到系统 `AfterFrame` 相册
11. SQLite 作品索引与 MediaStore 启动恢复
12. 系统“减少动态效果”与中英文资源完整性校验

## Motion Photo 输出

当前 Android 主输出遵循 Motion Photo 1.0 结构：

```text
memoryMP.jpg
├── JPEG 主图
├── XMP Motion Photo 元数据
└── 追加的 MP4 动态区间
```

Android 公共导出位置：

```text
DCIM/AfterFrame/          # 系统相册可见的 Motion Photo JPEG
App files/afterframe/     # 分享用 MP4、持久封面与 SQLite 索引
```

## 架构

```text
Flutter Product UI
  ├── AppLanguageScope (zh/en)
  ├── video_player (content URI preview)
  └── MediaEngine (MethodChannel)
      └── Android Media Engine
          ├── MediaStore Video Library + Album Publisher
          ├── FFprobe 媒体解析
          ├── FFmpeg 抽帧 + filter graph 合成
          ├── Motion Photo Packager
          └── SQLite ExportIndex
```

Flutter 负责交互、应用内视频选择、编排和作品状态；Kotlin 负责 MediaStore、FFprobe 解析、FFmpeg 精确抽帧/裁剪/合成和 Motion Photo 封装。视频统一输出为 30fps MP4：优先通过 Android `MediaCodec` 编码 H.264，硬件编码不可用时自动回退到软件 MPEG-4；当前 AAR 覆盖 `armeabi-v7a`、`arm64-v8a`、`x86` 与 `x86_64`。

## 运行

```bash
flutter pub get
flutter run -d <android-device>
```

Release APK 可直接按 Flutter 默认 ABI 拆分：

```bash
flutter build apk --release --split-per-abi
```

## 下一阶段建议

- 补充 FFmpeg 导出进度、后台恢复以及 HDR/色彩空间策略
- 增加草稿持久化与作品删除/清理
- 为多视频拼图增加独立时间轴偏移与实时组合预览
- 提供 GIF/静态图兼容导出
- 补充后台任务、导出进度、取消、存储清理和低内存保护
- 将 applicationId 从示例包名迁移为正式品牌域名

> 说明：当前探测、抽帧、裁剪、变速、增强和多素材合成均由 FFmpeg 负责。为保证非关键帧入点准确，导出会解码所选范围并重新编码，而不是做关键帧对齐的流复制。导出优先使用 Android MediaCodec H.264；设备硬件编码器不可用时会自动改用 FFmpeg 内置 MPEG-4 软件编码，避免任务直接失败。所用 `ffmpeg-kit-full` 不启用 GPL 编码器；若改用包含 `libx264` 的 Full-GPL 包，整个应用的分发许可也必须相应评估。
