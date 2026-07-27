# Changelog

## 0.7.3 - 2026-07-27

- 取消“创作模式”这一概念：作品形态改为由素材数量派生，不再由用户在 Studio 内选择。1 段素材是保留原始画幅的 Live 单帧，2～3 段素材是 Adaptive Canvas 自动版式的 Live 拼图，其余规则（封面瞬间、编辑窗口、播放语义、导出通道）完全共用。
- 移除 Studio 编辑区的创作模式双卡片选择器和多素材来源选择器，释放约 230px 垂直空间；模式选择器原本在单段素材下永远只能展示一个禁用卡片加一行错误提示。
- 素材选择页底部改为“形态预告条”：用真实 `AdaptiveCanvasPlan` 渲染与成片一致的迷你版式（含 Smart Crop 默认取景与选择顺序编号），并写明将生成的形态与说明，选择数量变化时版式会平滑重排。玻璃面板与 Studio 底部编辑区统一视觉层。
- 修复形态预告条撑满整屏、盖住顶栏与素材网格并吞掉全部点击，导致选中一段素材后只能点“进入 Studio”、无法继续多选的问题：条内文案 `Column` 缺少 `MainAxisSize.min`，而 `Scaffold.bottomNavigationBar` 传入的是整屏高度的宽松约束，于是文案列直接占满屏幕。新增 `test/video_picker_screen_test.dart` 断言预告条始终贴底、素材库保持可见可选，防止回归。
- 形态预告条补充剩余可选数量（“还可再加 N 段”），并在出现与收起时用 `AnimatedSize` 平滑改变素材网格高度；文案全部可省略，按钮设上限宽度，避免长文案或大字号挤压排版。
- 超过 3 段上限时的提示改为同步弹出，不再依赖 `addPostFrameCallback`，且不再为一次被拒绝的点击触发 `setState`。
- Studio 顶栏副标题改为陈述当前形态（`Live 单帧 · 保留原始画幅` / `Live 拼图 · N 格`），预览徽章统一为 `AFTER LIVE`，拼图追加格数。
- 改变形态的唯一方式变为改变素材：拼图素材轨每段增加移除入口，删到 1 段时 Studio 自动回到单帧规则并按需重新抽取时间轴，移除操作可通过 SnackBar 撤销。
- 将 `maxLiveSources`、`minLiveDurationMs`、`maxLiveDurationMs`、`LiveComposition` 和 `LiveDefaults` 收敛到 `lib/src/models/live_rules.dart`，布局器、单帧状态和拼图控制器不再各自硬编码 3 / 500 / 6000。
- 统一播放语义默认值：Live 拼图此前默认循环开启、增强关闭，与 Live 单帧相反；现在两者共用 `LiveDefaults`（声音开、单次播放、增强开），改变素材数量不会静默改变导出行为，形态变化时也会带走用户已调整的设置。
- 修复拼图缩略图按下标写入导致的错配风险，改为按 clip id 寻址；修复素材数量变化后 `MotionCanvasRenderer` 未同步播放器生命周期而残留已移除素材播放器的问题。
- 删除 `CreationMode`、`CreationModeSelector`、`SourceSelector`、废弃的 `StudioScreen` 别名以及 20 个与双模式相关的文案键。
- 修复两路 720p 横屏素材错误选择 Film Strip、导致预览和导出出现大面积上下黑边与过宽中缝的问题：装饰性 Film Strip 不再参与自动候选，所有自动布局必须首格贴画布起边、末格贴画布终边，默认分隔缩小到最多 4px。
- Adaptive Canvas 评分新增未覆盖画布面积惩罚，禁止以“多保留源像素”为由牺牲成片占比；两路横屏素材现在使用铺满画布的纵向时间流。
- Frame、Smart Crop 起点和裁剪尺寸全部量化为整数像素；导出协议新增 `collagePixelRects`、`sourceCropPixelRects` 和 `collageSourceSizes`，原生层优先消费整数数据并要求裁剪纹理与 Frame 尺寸完全一致，不再容忍 1px 浮点误差，消除上下边缘抖动风险。
- 将 Live 拼图完整重构为 Canvas First：布局只生成画布像素尺寸与 Frame 像素矩形，不再要求素材适配槽位；Adaptive Canvas 会在纵向时间流、横向时间流、Pinterest 和网格候选中综合裁剪保留率、画面平衡、输出分辨率与画布覆盖率选择排版。
- 建立严格的 1:1 像素契约：每个 Smart Crop 窗口的像素宽高必须与目标 Frame 完全一致，素材本身不执行 Fit、Fill、Stretch 或逐素材缩放；素材尺寸不足时缩小整张画布，而不是缩放单个素材。
- Flutter 编辑预览改为先在源空间应用 Smart Crop，再仅缩放最终整张画布用于屏幕显示；编辑页可选择 Frame、直接拖动微调取景，并可恢复基于构图安全区的智能初始焦点。
- 导出协议新增 `canvasWidth`、`canvasHeight` 和 `sourceCropRects`。Media3 1.10.1 原生层移除拼图素材的 `LAYOUT_SCALE_TO_FIT_WITH_CROP`，改用 `Crop` 保留裁剪后的原始像素尺寸，再由 `VideoCompositorSettings` 按 Frame 中心定位。
- 编辑器、沉浸预览和导出共享同一份 `AdaptiveCanvasPlan`；归一化 Frame 与 Smart Crop 参数在冻结导出时一并传入 Android，避免各层重复推导几何。
- Live 拼图的 Motion Photo 静态封面和作品索引封面改为从最终合成 MP4 的同一时间点抽帧，不再错误沿用第一路素材封面。
- 增加 Canvas First 几何、Smart Crop 边界与 MethodChannel 新协议测试；`flutter analyze --no-pub`、Live 拼图相关 Flutter 测试和 `:app:compileDebugKotlin` 均通过。
- Android 16 x86_64 模拟器使用原问题中的两段 1280×720 昆虫视频完成实机链路复测：编辑预览无外围黑边、分隔线保持窄且固定，Media3 Motion Photo/MP4 导出成功，循环播放时上下 Frame 边界保持稳定。

## 0.7.2 - 2026-07-26

- 重构首页创作入口：不再提前拆分 Live 单帧与 Live 拼图，统一从素材选择进入 `AfterFrame Studio`，制作模式只在 Studio 内决定。
- 素材选择统一支持 1～3 段有序多选；单段默认 Live 单帧，多段默认 Live 拼图，模式切换会重新约束公共时间轴，单段素材不会进入不可导出的拼图状态。
- 重构 AfterFrame Studio 的 Live 拼图编辑流：彻底移除“布局 / 风格 / 转场 / 音乐”工具坞、模板和伪效果状态，改为与 Live 单帧一致的“预览卡片 → 封面瞬间 → 时间轴 → 更多设置 → 生成”层级。
- Live 拼图的声音、循环、增强和 0.5x–2.0x 变速沿用 Live 单帧交互，参数直接进入 Media3 导出，不再由“音乐”或模板状态间接决定。
- 重做 Live 拼图排版：输出固定为 9:16，按素材横竖比例在横分栏、竖分栏、左主画面和上主画面中自动选择裁切损失最小的方案；每个槽位等比铺满且禁止拉伸，消除大面积黑边和零散小画面。
- Flutter 编辑预览和 Android Media3 导出共用归一化槽位；Media3 使用 `LAYOUT_SCALE_TO_FIT_WITH_CROP`，保证预览与成片采用同一套满版几何语义。
- Live 单帧和 Live 拼图均增加右上角全屏入口；全屏采用淡入缩放路由、沉浸式系统栏、显式关闭、Android 返回键和下滑退出，离开时可靠恢复系统 UI。

## 0.7.1 - 2026-07-26

- 修复 Gitee `update.json` 带 UTF-8 BOM 时 Android `JSONObject` 在版本比较前解析失败，生成端改为 UTF-8 无 BOM，客户端同时兼容历史 BOM。
- 修复安全域名白名单误拒绝 Gitee raw 官方重定向域名 `raw.giteeusercontent.com`，保留 HTTPS 和 Gitee 主机限制。
- 实测确认 Gitee 对仓库普通大 APK 的匿名 raw 请求返回 403；APK 下载源迁移为公开 Gitee Release 附件。
- 发布工具新增 ReleaseId/附件完整性校验，默认禁止生成不可匿名下载的仓库 raw APK URL。
- 原子发布工具显式按 UTF-8 读取无 BOM 清单，避免 Windows PowerShell 使用系统代码页破坏中文更新说明。
- 0.7.0 因在清单解析前失败而无法远端自愈，需手动覆盖安装一次 0.7.1；之后同版本检查和 App 内升级恢复正常。

## 0.7.0 - 2026-07-26

- 增加 Gitee 公开仓库应用更新，使用 `update.json` 明确版本与三种 split APK 资源。
- 仅当远端 `versionCode` 严格大于当前版本时允许更新，并在检查、下载和安装前重复阻止版本回退。
- 从已安装 APK 确认当前 ABI，只下载同类型 APK；安装前同时验证 SHA-1、大小、包名、版本、ABI 和签名证书。
- 使用 Android DownloadManager 后台下载，支持进程退出后的状态恢复、下载完成校验和系统安装器衔接。
- “我的”页增加检查更新、下载进度、校验与安装状态，以及符合 Material 交互的更新说明底部面板。
- 增加 `tool/prepare_gitee_update.ps1`，从实际构建产物生成三份 SHA-1 和发布清单，减少人工发布错误。
- 增加 `key.properties` 正式签名支持，发布工具默认拒绝 debug 签名与三包签名不一致，避免首发后因更换签名无法覆盖升级。
- 接入生产 Gitee 仓库 `luyuan567/after_frame_update`，默认读取 `master/update.json`，无需额外构建参数。
- 增加 Gitee 原子发布预演/推送脚本和独立发布手册，避免网页逐个上传造成清单与 APK 短暂不一致。

## 0.6.0 - Media3-only media engine

- 移除 FFmpegKit/FFprobe、相关 ProGuard/JNI 打包规则和约 67MB native AAR 依赖。
- 新增 `Media3RenderEngine`，使用 Media3 1.10.1 Transformer 输出 H.264/AAC MP4。
- 使用 Composition + VideoCompositorSettings 实现最多三路同步 Live 拼图、焦点裁切和单一主音轨。
- 媒体解析、缩略图和封面抽帧统一使用 Android MediaStore/MediaMetadataRetriever/MediaExtractor。
- 导出格式聚焦为 Motion Photo 与 MP4；移除非核心的 GIF/animated WebP 入口。
- 以下 0.5.x 条目保留为历史记录，不代表当前实现。

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
