# AfterFrame 媒体架构

## App Update 模块

更新链路独立于媒体引擎，但暂时复用现有 MethodChannel：Flutter 的 `AppUpdateService` 负责展示状态，Android 的 `AppUpdateManager` 是唯一安全决策点，`DownloadManager` 负责可跨进程存续的后台下载，`UpdateDownloadReceiver` 在下载完成后触发校验。

生产清单固定为 `https://gitee.com/luyuan567/after_frame_update/raw/master/update.json`。清单和 SHA-1 位于 `master`，大 APK 使用公开 Gitee Release 的稳定 `/releases/download/{tag}/{filename}` 路由；先完整上传 Release，最后原子提交清单，避免客户端看见半成品。

状态机为 `idle/no_update → available → downloading → verifying → ready → system installer`，失败统一进入 `error`。状态与下载 ID 持久化在 SharedPreferences；App 重启时会查询 DownloadManager 并恢复下载或重新执行校验。安装新版本后，如果持久化目标版本已不再高于当前版本，旧状态和 APK 会自动清理。

安全边界如下：

- Gitee 清单、APK 和 SHA-1 只接受 HTTPS Gitee 及官方 `raw.giteeusercontent.com` 内容域名；清单包名必须等于当前 `applicationId`。元数据解析会显式剥离 UTF-8 BOM。
- 每个 ABI 资产自己的实际 `versionCode` 是升级顺序的唯一依据。Flutter split APK 会产生不同的 ABI versionCode，因此选定当前 ABI 后才比较，并在检查、下载前和安装前重复执行严格大于判断。
- 当前 ABI 从已安装 APK 的 `lib/<abi>/libapp.so` 和运行时 native library 目录交叉确定；下载 APK 必须只含同一个目标 ABI。
- SHA-1 按用户发布文件校验，同时用 Android PackageManager 比对 APK 包名、版本和签名证书。SHA-1 不承担发布者身份认证，签名匹配才是防止第三方替换 APK 的核心保护。
- Android 系统安装器是最终安装边界；未知来源授权和安装确认不可由普通应用静默绕过。

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
├─ 首页统一创作入口与 1–3 段有序多选
├─ 素材选择页按已选数量预告作品形态（真实 Adaptive Canvas 迷你版式）
├─ AfterFrame Studio
│  ├─ Live 单帧状态、封面和时间轴
│  └─ Motion Canvas 拼图控制器、渲染器和工具区
├─ Studio 预览、素材增删和作品页面
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
│  ├─ Canvas First：Adaptive Canvas + Smart Crop 1:1 像素布局
│  └─ H.264/AAC MP4
└─ ExportService
   ├─ Motion Photo XMP + trailing MP4
   ├─ MediaStore 发布
   └─ ExportIndex 对账和删除
```

`Media3RenderEngine` 只生成工作目录中的 MP4，不发布文件。`ExportService` 独占任务互斥、Motion Photo 打包、MediaStore 发布、作品索引和分享。

## 一套创作规则

AfterFrame 没有“创作模式”这个概念。Studio 编辑的是一个**有序素材列表**，作品形态由素材数量派生，用户永远不需要、也无法直接选择形态。规则集中在 `lib/src/models/live_rules.dart`：

- `LiveComposition.forSourceCount`：1 段 → `singleFrame`（满画布，保留原始画幅，不裁剪）；2–3 段 → `adaptiveCanvas`（自动版式，同步播放）。
- `maxLiveSources = 3`、`minLiveDurationMs = 500`、`maxLiveDurationMs = 6000`：布局器、单帧状态和拼图控制器共用同一批常量。
- `LiveDefaults`：声音、循环、增强和变速的默认值对所有形态一致，因此改变素材数量不会静默改变播放语义。
- 形态在素材选择页就已确定：底部条用真实 `AdaptiveCanvasPlan` 渲染迷你版式，并写明“将生成”的形态；Studio 顶栏只陈述形态，不提供切换控件。
- 改变形态的唯一方式是改变素材：在拼图素材轨上移除一段即可，删到 1 段时 Studio 自动回到单帧规则，且移除可撤销。素材数量的增加需要返回素材库重新选择。

## 拼图规则

- 首页不再暴露独立拼图入口，素材统一进入 AfterFrame Studio。
- Studio 共享顶栏、导出反馈、预览卡片和玻璃面板视觉层；两种形态都遵循“预览 → 封面 → 时间轴 → 更多设置 → 生成”。拼图业务状态仍由独立 `MotionCanvasController` 管理，不与单帧时间轴状态混写；素材列表变化时通过 `LiveEditorState.syncSources` 和 `adoptSettings` 单向对齐。
- 拼图支持 2–3 路视频，每一路保留独立裁切区间；公共时长取最短有效区间，防止某路提前结束后出现空帧。
- “布局 / 风格 / 转场 / 音乐”不是当前产品能力，也不在 UI、控制器或导出协议中保留伪入口。声音、循环、增强和变速使用与 Live 单帧相同的设置语义；需要音频时只添加第一路主音轨序列。
- Live 拼图采用 Canvas First。`MotionCanvasLayout` 的产物是 `AdaptiveCanvasPlan`：画布像素尺寸、按时间顺序排列的 Frame 像素矩形，以及每路素材在源空间中的 Smart Crop 窗口。布局不得返回任何逐素材缩放参数。
- Adaptive Canvas 以 9:16 目标比例和最多三路素材为输入，在纵向时间流、横向时间流、Pinterest 和网格候选中评分。评分包含素材保留率、各 Frame 保留率差异、有效画布分辨率、未覆盖画布面积和版式节奏；素材顺序始终等于用户选择/重排后的时间顺序。带装饰性上下留白的 Film Strip 不参与自动候选，避免为了源像素保留率生成大片黑边。
- 自动布局必须满足外边缘闭合：首行/首列贴画布起边，末行/末列贴画布终边；默认 Frame 间隔为 4 个输出像素，自动方案不得产生额外外围黑边。
- 1:1 不变量定义在导出画布像素空间：`cropPixelWidth == framePixelWidth` 且 `cropPixelHeight == framePixelHeight`。若某个 Frame 大于源素材，系统等比例缩小整张画布及全部 Frame，绝不单独放大、缩小或拉伸该素材。
- Smart Crop 只改变源空间裁剪窗的 `left/top`。默认焦点采用可解释的构图安全区启发式（人像略偏上、其他居中），用户可在编辑画布拖动当前 Frame 微调并随时恢复默认焦点。人脸/显著性模型仍属于后续可替换的数据源，不影响现有几何协议。
- Flutter 预览先按源像素尺寸摆放视频，再用 Frame 裁剪，最后只为了屏幕显示而缩放完整画布。沉浸预览复用同一 `AdaptiveCanvasPlan`，因此不会重新选择布局或推导裁剪。
- MethodChannel 冻结传递 `canvasWidth/canvasHeight`、整数 `collagePixelRects`、整数 `sourceCropPixelRects` 和 `collageSourceSizes`；归一化矩形仅作为旧协议兼容字段。Media3 对每路素材应用 `Crop`，裁剪结果必须与 Frame 像素宽高完全相等；`VideoCompositorSettings` 只设置输出画布和整数像素 Frame 中心，不使用 `Presentation`、Fit、Fill 或 Stretch。
- 拼图完成后，`ExportService` 从最终 MP4 的封面时间点抽取静态 JPEG，再用于 Motion Photo 主图和作品索引；禁止拿第一路源素材封面代替合成画布。
- Live 单帧和 Live 拼图共用 `FullscreenPreview` 路由规范：280ms 淡入缩放、`immersiveSticky` 系统栏、右上角关闭、系统返回和向下拖拽退出；路由销毁时恢复 `edgeToEdge`，编辑页播放器在全屏期间暂停以避免双音轨。
- 所有素材使用相同目标时长和变速，避免序列提前结束后出现空帧。
- AI 主体识别和跨轨复杂转场明确延期。当前 Smart Crop 是确定性的构图安全区加用户微调，不宣称已经具备人脸或语义主体检测能力。

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
