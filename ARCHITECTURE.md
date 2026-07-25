# AfterFrame 媒体架构

## 设计结论

AfterFrame 的核心是“视频片段 → Motion Photo/MP4”和最多三路视频的同步 Live 拼图。Media3 1.10.1 已覆盖这些能力，不需要 FFmpegKit：

- `Transformer`：裁切、重新编码、H.264/AAC 输出、取消与错误回调
- `EditedMediaItem`：音视频移除、最大帧率、恒定变速和逐素材效果
- `Composition`：多素材时间线、独立视频序列和单独主音轨
- `VideoCompositorSettings`：多路同时画面、分栏/网格/PiP 类布局
- Media3 Effect：裁切、尺寸适配、色彩增强和高斯模糊
- Android 原生 API：MediaStore、MediaMetadataRetriever、MediaExtractor、Bitmap/JPEG

## 边界

```text
Flutter
├─ 媒体选择与有序多选
├─ 编辑状态、预览和作品页面
└─ 冻结导出参数
       │
       ▼
Android MethodChannel
├─ MainActivity
│  ├─ 权限 / MediaStore 查询
│  ├─ 媒体信息 / 缩略图 / 抽帧
│  └─ 分享入口
├─ Media3RenderEngine
│  ├─ 单视频 EditedMediaItem
│  ├─ 多视频 Composition
│  ├─ 焦点裁切和 1080×1920 布局
│  └─ H.264/AAC MP4
└─ ExportService
   ├─ Motion Photo XMP + trailing MP4
   ├─ MediaStore 发布
   └─ ExportIndex 对账和删除
```

`Media3RenderEngine` 只生成工作目录中的 MP4，不发布文件。`ExportService` 独占任务互斥、Motion Photo 打包、MediaStore 发布、作品索引和分享。

## 拼图规则

- 同时支持 1–3 路视频。
- 每一路使用自己的裁切区间和焦点坐标。
- 输出固定为竖屏 1080×1920；横分栏、竖分栏和主次网格由 compositor 定位。
- 每路视频独立静音；需要音频时只添加用户指定的主音轨序列。
- 所有素材使用相同目标时长和变速，避免序列提前结束后出现空帧。
- Media3 当前不支持跨视频/音频轨的 crossfade；Soft Fade/Film Grain 等复杂转场不得标记为完全所见即所得，需后续用自定义 GL effect 和视觉回归补齐。

## 输出

| 格式 | 编码/封装 | 位置与用途 |
| --- | --- | --- |
| Motion Photo | Media3 MP4 + JPEG XMP + trailing MP4 | `DCIM/AfterFrame`，兼容相册 |
| MP4 | Media3 H.264/AAC | `Movies/AfterFrame`，兼容聊天与短视频应用 |

GIF 与 animated WebP 已移除。为非核心格式重新引入 FFmpeg 会恢复大型 native 依赖、ABI 包体、16KB 页面对齐和许可证维护成本，不符合当前产品优先级。

## 验证边界

自动化应覆盖 Dart 分析/测试、Kotlin 编译、APK 构建、方法通道参数以及输出结构。以下结论必须来自真机矩阵，不能由编译推导：

- Pixel、Samsung、小米等相册对 Motion Photo 的识别和播放
- 高通、联发科等设备的多路 MediaCodec 导出稳定性与速度
- HDR 到 SDR/保留 HDR 的色彩表现
- 微信、抖音对 Motion Photo 原件与 MP4 fallback 的真实接收效果
