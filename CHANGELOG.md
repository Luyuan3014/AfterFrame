# Changelog

## 0.5.0 - 2026-07-25

- 按“Media3 负责看、FFmpeg 负责创造”重构：新增 `Media3PreviewEngine` 只读预览边界，将原生后端拆成 `FfmpegRenderEngine` 与 `ExportService`。
- Flutter Motion Editor 只提交冻结的画布参数；FFmpeg 负责裁剪、变速、多路合成、音频、MP4 以及 GIF/WebP 动画编码；Export Service 负责任务互斥、发布、索引与分享。
- Motion Canvas 的 MP4、GIF、animated WebP 选项由占位状态升级为真实可选导出，并分别写入 `Movies/AfterFrame` 或 `Pictures/AfterFrame`。
- Motion Photo 打包器独立化，继续使用 Android Motion Photo 1.0 单 JPEG、XMP Container Directory 与 trailing MP4；运行时测试会校验 XMP 视频长度和尾部 MP4 字节。
- `flutter build apk --release --split-per-abi` 成功生成 armeabi-v7a、arm64-v8a、x86_64 三个 release APK，且每包检查到目标 ABI 的 FFmpeg/FFprobe JNI 库。
- arm64-v8a 与 x86_64 包内全部 FFmpeg 相关 ELF LOAD segment 均为 `0x4000` 对齐；armeabi-v7a 为 `0x1000`。
- x86_64 Android 16 模拟器实际通过 FFmpeg 编码、FFprobe、抽帧、GIF、animated WebP 和 Motion Photo 打包测试；两种 ARM 构建通过，仍需对应 ARM 真机运行矩阵。
- 版本提升到 `0.5.0+5`。

## 0.4.1 - 2026-07-25

- Android 媒体后端由 Media3 完整迁移到 FFmpeg/FFprobe：媒体解析、缩略图、精确抽帧、裁剪、变速、增强、音轨和多素材合成使用同一引擎。
- 多素材导出开始实际消费布局、独立入出点、裁剪焦点、音轨来源和转场参数；输出统一为 30fps MediaCodec H.264/AAC MP4，并用 FFprobe 拒绝无视频轨的空壳文件。
- 保留并修正 Motion Photo 打包层，变速作品的 presentation timestamp 会同步换算。
- 使用 FFmpeg 8.1.1 Android 包，覆盖 armeabi-v7a/arm64-v8a/x86/x86_64；当前输出优先使用 MediaCodec H.264，但依赖 POM 同时声明 LGPL/GPL，发布前必须完成许可证清单审计。
- 移除与 Flutter `--split-per-abi` 冲突的手动 `ndk.abiFilters`，原始 release 拆包命令可直接构建三种默认 ABI。
- 新增设备端 FFmpeg 编码、FFprobe 解析与 JPEG 抽帧运行时测试。

## 0.4.0 - 2026-07-25

### Motion Canvas（动态记忆画布）

- Live 拼图入口改为独立的 `MotionCanvasPage`，不再复用单张 Live 的播放器卡片编辑页。
- 新增一个 24px 圆角、`antiAlias` 裁剪的连续画布；Clip 内部不使用卡片、间距或可见边框。
- 预览背景复制当前视频，以 1.3 倍缩放、动态模糊和 30% 透明度形成沉浸背景。
- 新增 `MotionCanvasController` 作为作品状态源，统一管理素材顺序、独立裁剪范围、焦点、模板、风格、转场、主时间轴和导出状态。
- 新增 Master Timeline：多路 `VideoPlayerController` 同步播放，以首路为时钟，每 400ms 检查一次漂移，超过 85ms 自动纠偏。
- 新增 Travel Diary、Sunset Story、Film Strip、Minimal Memory 四套可编辑模板。
- 新增 Soft Blur Blend、Soft Fade、Light Leak、Blur、Film Grain 五类预览转场语言，默认 Soft Blur Blend。
- 新增素材轨道：点击进入 Clip 双手柄范围编辑，长按拖拽排序；工具区重组为 Layout、Style、Transition、Music、Export。
- 主操作改为 `Create Memory`，一键应用模板的构图焦点、风格与默认柔焦融合后执行导出。

### 裁剪与导出协议

- 新增 `VideoCropEngine`，按 1080px 画布宽度与素材比例计算高度并限制在 360～1120px；焦点模型可由后续 ML 主体检测直接替换。
- Android MethodChannel 增加每段素材的 `collageStartMs` / `collageEndMs`、裁剪焦点和转场声明字段。
- Motion Canvas 导出统一使用最短 Clip 作为主时间轴长度，允许各 Clip 使用不同素材入点。
- Media3 原生合成器移除左右分栏和主次网格，所有素材改为全宽纵向连续布局。
- 保留标准 Android Motion Photo 与聊天兼容 MP4 的双交付：相册写入单文件 XMP + trailing MP4，私有目录保留可分享 MP4。

### 验证

- `flutter analyze --no-pub`：通过，0 issue。
- `flutter test --no-pub`：通过，20 tests。
- 新增 Motion Canvas 控制器测试，覆盖最短时间轴、模板焦点、独立裁剪、拖拽排序与混合比例高度约束。

### 当前边界

- 预览层已提供构图启发式 Smart Crop；人脸/人物/天空/显著性检测尚未接入 ML Kit、MediaPipe 或 OpenCV。
- 原生最终合成仍使用仓库现有 Media3 Transformer；FFmpeg 二进制、导出级动态模糊/转场、GIF/WebP 编码尚未接入。
- Motion Photo 与 MP4 可用；iOS Live Photo、GIF、WebP 仅保留格式模型，不在 UI 中伪装为已支持。
- HDR 元数据保真、OEM 相册播放以及微信/抖音接收仍需真机矩阵验证。

## 0.3.2 - 2026-07-25

- 修复作品删除后 Kotlin `Unit` 经 MethodChannel 返回导致的 Android 主线程崩溃。
- 作品索引升级为可恢复、幂等的 SQLite 删除流程。

## 0.3.0 - 2026-07-24

- 使用 Media3 Transformer 实现多素材同步合成与标准 Android Motion Photo 输出。
- 增加聊天兼容的私有 MP4 与 FileProvider 分享链路。

## 0.1.0 - 2026-07-24

- 建立 Flutter + Android Native Media Engine 的 AfterFrame MVP。
