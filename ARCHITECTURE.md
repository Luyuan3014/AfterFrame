# AfterFrame Architecture

## 产品边界

AfterFrame 是 Android 优先的视频转动态记忆工具。单张 Live 与 Motion Canvas 是两条独立创作路径：

- Live Frame：从单个视频选择封面和时间范围，生成 Motion Photo。
- Motion Canvas：让 2～3 段视频在同一主时间轴上组成一张连续、会呼吸的动态照片。

Motion Canvas 不把视频当作网格卡片。模板只初始化可编辑参数，用户始终拥有素材顺序、范围、焦点、风格和转场的控制权。

## 0.5 分层

```text
Flutter / Motion Editor
  MotionCanvasPage + MotionCanvasController
                    │
Motion Canvas Engine
  MotionClip + Layout + Crop + Transition + Master Timeline
                    │
        ┌───────────┴───────────┐
        │                       │
Preview Engine             Render Engine
Media3PreviewEngine        FfmpegRenderEngine
video_player_android       FFmpeg filter graph + FFprobe
        │                       │
        └───────────┬───────────┘
                    │
Export Service
MotionCanvasExportService → MethodChannel → Android ExportService
                    │
        ┌───────────┴──────────────────┐
        │                              │
Android Motion Photo             MP4 / GIF / WebP
JPEG + XMP + trailing MP4        MediaStore publication
```

边界是强制的：`Media3PreviewEngine` 只创建、同步和销毁 Android Media3 ExoPlayer 播放器；它不生成文件。`FfmpegRenderEngine` 只把冻结的编辑参数渲染成 MP4/GIF/WebP 字节；它不拥有 UI 和 MediaStore。Android `ExportService` 独占任务互斥、临时目录、Motion Photo 打包、系统媒体库发布、作品索引和分享。

`video_player_android` 是 Flutter 官方 endorsed Android 实现，当前版本使用 Media3 ExoPlayer。因此预览仍保持 Flutter 纹理合成能力，同时明确满足“Media3 负责看”。封面精确抽帧属于作品生成输入，系统缩略图优先走 MediaStore，罕见编码回退才进入 FFmpeg。

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
├── preview/
│   └── preview_engine.dart        Media3 只读预览边界
├── renderer/
│   ├── motion_canvas_renderer.dart
│   ├── transition_engine.dart
│   └── video_crop_engine.dart
├── widgets/
│   ├── clip_track.dart
│   └── creative_tools.dart
└── motion_canvas_page.dart

android/app/src/main/kotlin/com/example/after_frame/
├── FfmpegRenderEngine.kt          FFmpeg 合成和动画编码
├── ExportService.kt               导出任务、发布和 Motion Photo 打包
├── ExportIndex.kt                 可恢复作品索引
└── MainActivity.kt                MethodChannel 适配器
```

## 导出格式

| 格式 | 创建引擎 | 发布结果 |
| --- | --- | --- |
| Android Motion Photo | FFmpeg MP4 + `MotionPhotoPackager` | `DCIM/AfterFrame/*MP.jpg`，同时保留聊天兼容私有 MP4 |
| MP4 | FFmpeg H.264/AAC | `Movies/AfterFrame/*.mp4` |
| GIF | FFmpeg palettegen/paletteuse | `Pictures/AfterFrame/*.gif` |
| animated WebP | FFmpeg `libwebp_anim` | `Pictures/AfterFrame/*.webp` |

这里的 Live 图指 Android Motion Photo，不冒充 Apple Live Photo。Apple Live Photo 仍需要 iOS 端 JPEG/HEIC + MOV 资产配对和 Photos 写入。

## ABI 与运行验证

release 使用 Flutter 原生 `--split-per-abi` 生成 `armeabi-v7a`、`arm64-v8a`、`x86_64` 三包。每包必须包含同 ABI 的 `libffmpegkit.so`、`libavcodec.so`、`libavformat.so`、`libavfilter.so`、`libavutil.so`、`libswscale.so`、`libswresample.so`。最终 arm64-v8a 与 x86_64 包内全部 FFmpeg 相关 ELF 的 LOAD alignment 已核对为 `0x4000`（16KB）；armeabi-v7a 为 `0x1000`。设备端测试执行视频编码、FFprobe、JPEG 抽帧、GIF、animated WebP，并验证 Motion Photo XMP 和尾部 MP4 逐字节一致。

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
- Motion Photo 的聊天兼容 MP4：保存在 app 私有目录，通过 FileProvider 分享，避免相册重复项。
- 独立 MP4：发布到 `Movies/AfterFrame`。
- GIF / animated WebP：由 FFmpeg 编码并发布到 `Pictures/AfterFrame`。

当前不可交付：

- Apple Live Photo：需要 JPEG/HEIC + MOV 的 Apple 资产标识与 iOS Photos 写入链路，Android-only 工程不能等同支持。
- HDR 原始色彩保证：当前 H.264/yuv420p 输出明确是 SDR 兼容路径；HDR tone mapping、10-bit 输出和元数据保留必须另建策略并逐设备验证。

## 测试边界

自动化验证覆盖 Dart 静态分析、状态约束、时间轴、模板焦点、排序、裁剪与 MethodChannel 参数。设备端测试在 x86_64 Android 16 模拟器覆盖 FFmpeg 编码、FFprobe、抽帧、GIF/WebP 与 Motion Photo 结构。以下结论不能由编译或单一模拟器推导：两种 ARM ABI 的真机运行、OEM 相册识别、真实设备多路预览性能、微信/抖音接收效果、HDR 色彩一致性。
