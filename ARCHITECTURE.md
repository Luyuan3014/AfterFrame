# AfterFrame Architecture

## 产品边界

AfterFrame 是 Android 优先的视频转动态记忆工具。单张 Live 与 Motion Canvas 是两条独立创作路径：

- Live Frame：从单个视频选择封面和时间范围，生成 Motion Photo。
- Motion Canvas：让 2～3 段视频在同一主时间轴上组成一张连续、会呼吸的动态照片。

Motion Canvas 不把视频当作网格卡片。模板只初始化可编辑参数，用户始终拥有素材顺序、范围、焦点、风格和转场的控制权。

## 分层

```text
Flutter UI
  MotionCanvasPage
  ├── MotionCanvasRenderer        连续画布、动态背景、多路预览
  ├── MotionClipTrack             选择、长按排序
  └── CreativeToolDock            Layout / Style / Transition / Music / Export
            │
Motion Canvas Engine
  MotionCanvasController          单一状态源 + Master Timeline
  MotionClip                      素材、独立入点/出点、焦点、主体语义
  MotionCanvasLayout              1080px 画布与高度约束
  VideoCropEngine                 可替换的主体焦点规划边界
  TransitionEngine                预览转场语言
            │
Export Orchestration
  MotionCanvasExportService       冻结作品参数、提取封面、调用平台适配器
            │
Platform Media Adapter
  MediaEngine / MethodChannel com.afterframe/media_engine
            │
Android Media Engine
  FfmpegMediaEngine              当前可运行后端
  ├── FFprobe                     时长、尺寸、旋转与音轨探测
  ├── FFmpeg filter graph         独立裁剪、速度、焦点裁剪、合成与效果
  ├── h264_mediacodec + AAC        30fps MP4 编码
  └── Motion Photo Packager       JPEG XMP + trailing MP4
```

FFmpeg Engine 位于 Platform Media Adapter 之后，Flutter 只提交冻结的作品参数，不拼装命令。Android 端把 `content://` 转为 FFmpeg SAF 输入，统一完成媒体探测、精确抽帧、逐帧裁剪、变速、等比焦点裁剪、多路布局、音轨选择、效果和编码，再复用独立的 Motion Photo 打包与 MediaStore 发布层。

## 目录

```text
lib/src/features/motion_canvas/
├── controllers/
│   └── motion_canvas_controller.dart
├── export/
│   └── export_service.dart
├── models/
│   ├── motion_canvas_layout.dart
│   └── motion_clip.dart
├── renderer/
│   ├── motion_canvas_renderer.dart
│   ├── transition_engine.dart
│   └── video_crop_engine.dart
├── widgets/
│   ├── clip_track.dart
│   └── creative_tools.dart
└── motion_canvas_page.dart
```

## Master Timeline

`MotionCanvasController.durationMs` 永远取所有 Clip 有效范围的最短值，并限制在 500～6000ms。每段素材拥有自己的 `trimStartMs`，实际预览位置为：

```text
clipPosition = clip.trimStartMs + masterPosition
```

第一路播放器作为预览时钟。播放中每约 90ms 更新 UI 位置，每 400ms 检查其他播放器；漂移超过 85ms 时 seek 到期望位置。导出时每段的结束点冻结为 `trimStartMs + masterDuration`，因此输入范围不同但输出长度一致。

## Smart Crop

布局先计算自然高度：

```text
naturalHeight = canvasWidth / sourceAspectRatio
canvasWidth = 1080
clipHeight = clamp(naturalHeight, 360, 1120)
```

`CropFocus(x, y, confidence)` 是裁剪契约。当前 `VideoCropEngine` 根据模板槽位与横竖比例给出稳定、可解释的初始焦点，例如 Sunset Story 的第一段偏向天空、第二段偏向环境、第三段偏向人物。它是构图启发式，不宣称做人脸或显著性识别。

未来主体检测器只负责输出候选框/焦点：人脸与人物优先，其次太阳/天空，再其次显著区域。控制器负责接受结果，Renderer 和 Export Service 不依赖具体 ML SDK。

## 连续画布与背景

- 外部只有一个 `ClipRRect(radius: 24, clipBehavior: antiAlias)`。
- Clip 使用全宽纵向流和轻微视觉重叠，不绘制独立圆角或分隔线。
- 当前选中视频同时作为背景，`scale=1.3`、`opacity=.30`，预览使用 20 logical px 高斯模糊（目标导出参数为 40px @ 1080p）。
- 绿色只用于选择焦点、时间轴拇指和主操作；主体空间保持 `#0B0B0D`。
- 状态动画统一 200～400ms、`easeInOutCubic`，并遵守系统减少动态效果偏好。

## 模板与转场

模板不是预渲染文件：

| 模板 | 初始叙事 | 风格 |
| --- | --- | --- |
| Travel Diary | 景色 → 人物 → 细节 | Cinematic |
| Sunset Story | 天空 → 环境 → 剪影 | Dusk |
| Film Strip | 连续片段与暖颗粒 | Film |
| Minimal Memory | 留白与克制构图 | Clean |

默认转场是 Soft Blur Blend。FFmpeg 导出已消费 Soft Fade、Light Leak 色调、Blur 与 Film Grain 参数；复杂的移动漏光、40px 动态模糊背景和 Gradient Blend 仍需进一步建立逐帧视觉回归后才能称为完全所见即所得。

## 导出与格式真实性

当前可交付：

- Android Motion Photo：单个 JPEG 文件，XMP 声明 Motion Photo 与视频长度，JPEG EOI 后紧随 MP4。
- MP4：保存在 app 私有目录，通过 FileProvider 分享，避免在相册产生重复视频。

当前不可交付：

- Apple Live Photo：需要 JPEG/HEIC + MOV 的 Apple 资产标识与 iOS Photos 写入链路，Android-only 工程不能等同支持。
- GIF/WebP：格式枚举已存在，但 UI 标为 Soon 且不可选，避免输出伪格式。
- HDR 原始色彩保证：当前 H.264/yuv420p 输出明确是 SDR 兼容路径；HDR tone mapping、10-bit 输出和元数据保留必须另建策略并逐设备验证。

## 测试边界

自动化验证覆盖 Dart 静态分析、状态约束、时间轴、模板焦点、排序、裁剪与 MethodChannel 参数。Gradle 编译验证 Kotlin 契约。以下结论不能由编译推导：OEM 相册能否识别、真实设备多路预览性能、微信/抖音接收效果、HDR 色彩与 FFmpeg 输出一致性。
