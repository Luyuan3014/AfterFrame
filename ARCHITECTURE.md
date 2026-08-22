# AfterFrame 媒体架构

## App Update 模块

更新链路独立于媒体引擎，但暂时复用现有 MethodChannel：Flutter 的 `AppUpdateService` 负责展示状态，Android 的 `AppUpdateManager` 是唯一安全决策点，`DownloadManager` 负责可跨进程存续的后台下载，`UpdateDownloadReceiver` 在下载完成后触发校验。该 Receiver 必须 `exported=true`，否则系统 DownloadManager 发来的 `ACTION_DOWNLOAD_COMPLETE` 会被静默丢弃。

生产清单固定为 `https://gitee.com/luyuan567/after_frame_update/raw/master/update.json`。清单和 SHA-1 位于 `master`，大 APK 使用公开 Gitee Release 的稳定 `/releases/download/{tag}/{filename}` 路由；先完整上传 Release，最后原子提交清单，避免客户端看见半成品。

状态机为 `idle/no_update → available → downloading → verifying → ready → system installer`，失败统一进入 `error`。状态与下载 ID 持久化在 SharedPreferences；App 重启时会查询 DownloadManager 并恢复下载或重新执行校验。前台轮询在 `verifying → ready` 后会自动打开系统安装器；安装新版本后，如果持久化目标版本已不再高于当前版本，旧状态和 APK 会自动清理。

安全边界如下：

- Gitee 清单、APK 和 SHA-1 只接受 HTTPS Gitee 及官方 `raw.giteeusercontent.com` 内容域名；清单包名必须等于当前 `applicationId`。元数据解析会显式剥离 UTF-8 BOM。
- 每个 ABI 资产自己的实际 `versionCode` 是升级顺序的唯一依据。Flutter split APK 会产生不同的 ABI versionCode，因此选定当前 ABI 后才比较，并在检查、下载前和安装前重复执行严格大于判断。
- 当前 ABI 从已安装 APK 的 `lib/<abi>/libapp.so` 和运行时 native library 目录交叉确定；下载 APK 必须只含同一个目标 ABI。
- SHA-1 按用户发布文件校验，同时用 Android PackageManager 比对 APK 包名、版本和签名证书。未安装 APK 的签名读取会同时请求 `GET_SIGNING_CERTIFICATES` 与遗留 `GET_SIGNATURES`，并在二者皆空时（常见于 Android 16 + v2-only APK）直接解析 APK Signing Block 提取证书摘要。SHA-1 不承担发布者身份认证，签名匹配才是防止第三方替换 APK 的核心保护。
- Android 系统安装器是最终安装边界；未知来源授权和安装确认不可由普通应用静默绕过。

## “我的”与本地设置

“我的”页面不是账号中心，不展示不可编辑的人形头像、昵称或假 ID。顶部使用不可点击的 AfterFrame 本地工作区品牌卡，明确“无需账号、数据留在本机”，避免制造登录、同步或编辑身份的错误预期。入口按语义分成“偏好设置 / 作品与导出 / 存储与隐私 / 支持与关于”，不再用“设置”统括导航、说明和支持动作。

页面只暴露已有真实能力，不保存无法兑现的伪设置：作品相册切换到同一 `HomeShell` 的作品索引；导出画质说明 Media3 H.264/AAC 重编码和 Canvas First 整画布缩放边界；Live 容器说明 Motion Photo 相册副本与 MP4 分享副本的职责；关于页从 `AppUpdateManager.currentState()` 读取当前版本与 ABI，并使用 Flutter 许可页展示依赖许可。

隐私与数据入口明确三类存储所有权：MediaStore 中的正式作品属于系统相册，`filesDir/afterframe` 是随 App 卸载移除的持久预览/分享副本，`cacheDir/afterframe` 是可随时重新生成的临时数据（含缩略图、抽帧、未完成导出和从 Live 图抽出的动态）。媒体编辑不上传；网络只用于配置的 Gitee 更新检查与安装包下载。

语言以普通设置卡片进入底部选择器，继续持久化到 `afterframe_settings`。临时缓存通过 MethodChannel 的 `getTemporaryCacheUsage/clearTemporaryCache` 管理；每次切换进入“我的”页都会刷新统计，并用 generation 丢弃过期异步结果。原生 `TemporaryCacheManager` 将删除范围严格限定为 `cacheDir/afterframe`。`filesDir/afterframe` 中的作品封面、MP4 分享副本、`ExportIndex`，其他插件缓存，以及 MediaStore 中的正式作品都不属于该缓存，绝不能随缓存清理删除。原生清理成功后 Flutter 同时清空缩略图/抽帧的内存路径表，防止继续引用已经删除的文件。

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
├─ 首页统一创作入口与 1–3 段有序多选（视频与 Live 图可混选）
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
│  ├─ 权限 / MediaStore 查询（视频 + 图像中的 Live 图）
│  ├─ Live 图动态抽取 / 媒体信息 / 缩略图 / 抽帧
│  ├─ 临时缓存统计 / 安全清理
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
- 改变形态的方式是改变素材：拼图素材轨可移除一段（可撤销），也可以在未满 3 段时继续添加视频或 Live 图。删到 1 段时 Studio 自动回到单帧规则；加到 2 段及以上时自动进入 Adaptive Canvas。

## Live 图导入

素材库不再只列出 `MediaStore.Video`。Android 13+ 同时请求 `READ_MEDIA_VIDEO` 和 `READ_MEDIA_IMAGES`（Android 14 另含用户选定视觉权限）。Live 图来自图像库中的 Motion Photo：

- API 34 优先读取 `IS_MOTION_PHOTO`；否则用文件名启发式（`MVIMG_`、`_MP.jpg`、`PXL_*MP*` 等）并对最近 JPEG 探查 XMP。
- `MotionPhotoSource` 按 Google Motion Photo 1.0 `Item:Length`、`GCamera:MicroVideoOffset` 抽取尾随 MP4；失败时若容器暴露视频轨，则用 `MediaExtractor`/`MediaMuxer` 复用到缓存文件。
- 抽出的动态位于 `cacheDir/afterframe/motion_sources`，属于临时缓存，清理缓存后下次导入会重新抽取。
- Flutter 侧 `MediaAsset.kind = motionPhoto`，`libraryUri`/`stillUri` 保持相册静态图身份，进入 Studio 前 `resolvePlayableSource` 把 `uri` 换成可播放文件。预览、时间轴、Media3 导出只消费可播放 URI；缩略图优先用静态主图。
- iOS Live Photo 的成对 JPEG+MOV 不是当前 Android 媒体库契约；只有已经转成 Android Motion Photo / 动态照片的项目会出现在 Live 筛选中。

## 拼图规则

- 首页不再暴露独立拼图入口，素材统一进入 AfterFrame Studio。
- Studio 共享顶栏、导出反馈、预览卡片和玻璃面板视觉层；两种形态都遵循“预览 → 封面 → 时间轴 → 更多设置 → 生成”。拼图业务状态仍由独立 `MotionCanvasController` 管理，不与单帧时间轴状态混写；素材列表变化时通过 `LiveEditorState.syncSources` 和 `adoptSettings` 单向对齐。
- 拼图支持 2–3 路视频或 Live 图，每一路保留独立裁切区间和独立封面瞬间；公共时长取各段有效区间与素材时长的最短值，且不超过最短素材，防止某路提前结束后出现空帧。素材轨可继续添加直至上限。
- “布局 / 风格 / 转场 / 音乐”不是当前产品能力，也不在 UI、控制器或导出协议中保留伪入口。声音、循环、增强和变速使用与 Live 单帧相同的设置语义；需要音频时只添加第一路主音轨序列。
- Live 拼图采用 Canvas First。`MotionCanvasLayout` 的产物是 `AdaptiveCanvasPlan`：画布像素尺寸、按时间顺序排列的 Frame 像素矩形，以及每路素材在源空间中的 Smart Crop 窗口。同比例家族（最大/最小宽高比 ≤ 1.12）使用最小原生边作为等格，再把完整取景窗均匀缩放到格子里，避免 1080p Live 静图和 720p 视频叠出一大一小。不同比例仍按原生像素排列，允许细小居中留白，禁止拉伸。
- Adaptive Canvas 以 9:16 目标比例和最多三路素材为输入，在纵向时间流、横向时间流、Pinterest 和网格候选中评分。评分包含素材保留率、各 Frame 保留率差异、有效画布分辨率、未覆盖画布面积和版式节奏；素材顺序始终等于用户选择/重排后的时间顺序。带装饰性上下留白的 Film Strip 不参与自动候选，避免为了源像素保留率生成大片黑边。
- 自动布局必须满足外边缘闭合：首行/首列贴画布起边，末行/末列贴画布终边；默认 Frame 间隔为 4 个输出像素，自动方案不得产生额外外围黑边。
- 1:1 不变量对「格子等于源尺寸」的 Frame 仍然成立：`cropPixelWidth == framePixelWidth`。同比例等格时允许 `crop` 大于 Frame，由 Media3 `Crop` 之后的 `Presentation.createForWidthAndHeight(slot)` 把纹理缩放到格子，合成器仍校验纹理尺寸等于 Frame。若某个 Frame 大于源素材，系统等比例缩小整张画布及全部 Frame，绝不单独拉伸该素材。
- Smart Crop 只改变源空间裁剪窗的 `left/top`。默认焦点采用可解释的构图安全区启发式（人像略偏上、其他居中），用户可在编辑画布拖动当前 Frame 微调并随时恢复默认焦点。人脸/显著性模型仍属于后续可替换的数据源，不影响现有几何协议。
- Flutter 预览按源像素摆放视频，用 Smart Crop 窗口裁切，再把该窗口缩放到 Frame 格子；暂停时各路停在自己的封面时间，播放时从各自 trimStart 同步推进。沉浸预览复用同一 `AdaptiveCanvasPlan`。
- MethodChannel 冻结传递 `canvasWidth/canvasHeight`、整数 `collagePixelRects`、整数 `sourceCropPixelRects`、`collageSourceSizes` 和每段 `collageCoverMs`；归一化矩形仅作为旧协议兼容字段。Media3 对每路素材应用 `Crop`，同比例缩格时再 `Presentation` 到 Frame；`VideoCompositorSettings` 只设置输出画布和整数像素 Frame 中心。
- 拼图完成后，`ExportService` 按各段独立封面从源素材抽帧并合成静图，再用于 Motion Photo 主图和作品索引；禁止只用第一路源素材封面，也禁止用单一成片时间点冒充所有格子的封面。
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
- 从 Pixel / 三星 / 小米相册导入 Live 图后，预览与 Media3 导出是否使用抽出的动态而不是静态主图
- 高通、联发科等设备的多路 MediaCodec 导出稳定性与速度
- HDR 到 SDR/保留 HDR 的色彩表现
- 微信、抖音对 Motion Photo 原件与 MP4 fallback 的真实接收效果
