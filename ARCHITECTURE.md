# AfterFrame 架构说明

## 产品与页面目标

AfterFrame 将视频素材转化为可反复观看的动态记忆。Live 编辑页以“发现精彩瞬间 → 选择封面 → 生成 Live 作品”为核心路径。当前版本由 Flutter 集中状态编排 Android Media3，实现单素材 Live 与 2～3 素材 Motion Collage 的真实导出。

## 应用级语言

`AppLanguageController` 是语言偏好的单一状态源，`AppLanguageScope` 将当前语言发布给全部路由。页面通过 `context.l10n` 读取同一份中英文资源，不在组件中维护语言分支。

```text
SharedPreferences (zh/en)
└── AppLanguageController
    └── AppLanguageScope
        └── Home / Picker / Live Studio / Works / Profile
```

语言切换先更新内存状态并立即重建 UI，再通过 MethodChannel 写入 Android SharedPreferences。持久化失败不会阻断当前会话的语言切换。

## 模块结构

```text
HomeShell
├── VideoPickerScreen
│   ├── thumbnail path cache            路径存活检查、失败重试
│   └── MediaPreviewSheet               素材 content URI 循环预览
├── Works
│   ├── MediaPreviewSheet               私有 MP4 Live 预览
│   └── preview / share / delete         作品生命周期操作
└── LiveEditorPage
    ├── LiveEditorState                 单一状态源
    ├── MediaEngine                     原生媒体能力边界
    └── LiveEditorScope                 向组件发布状态
        ├── LivePreviewCard             video_player、选区播放、AFTER LIVE 动效
        ├── SourceSelector              多素材来源切换
        ├── CreationModeSelector        Live Frame / Motion Collage 卡片
        ├── CoverSelector               确定性候选与手动封面选择
        ├── CollageLayoutSelector       拼图布局与主音轨选择
        ├── TimelineEditor              时间、长度、范围、封面与最佳时刻
        ├── AdvancedSettings            声音、循环、速度、增强效果
        └── GenerateButton              生成状态与点击反馈
```

目录职责：

```text
lib/src/live_editor/
├── live_editor_page.dart               页面组合、异步生命周期、导出编排
├── live_editor_scope.dart              InheritedNotifier 状态作用域
├── formatters.dart                     编辑器显示格式化
├── models/live_editor_state.dart       状态、约束、派生值与意图方法
└── components/                         无业务编排的功能组件
```

## 状态模型

`LiveEditorState` 继承 `ChangeNotifier`，是 Live 工作区的单一状态源。组件只从 `LiveEditorScope` 读取它，并通过公开的意图方法更新状态，组件之间不直接互相调用。

核心状态分为四组：

- 媒体：`asset`、`videoPath`、`duration`、`frames`、`activeAssetIndex`
- 时间：`currentPosition`、`startTime`、`endTime`、`coverFrame`、`liveLength`
- 创作：`mode`、`coverSelectionMode`、`selectedSuggestion`、`collageLayout`、`collageAudioSourceIndex`
- 设置与任务：`audioEnabled`、`loopEnabled`、`playbackSpeed`、`enhancementEnabled`、`generateStatus`

时间状态始终遵循以下约束：

```text
0 <= startTime < endTime <= duration
endTime - startTime >= 500ms
startTime <= coverFrame/currentPosition <= endTime
```

切换预览素材时会重置该素材的帧、封面候选与生成状态，但保留创作模式、拼图布局和主音轨。Motion Collage 的公共时间范围以最多三段输入中的最短时长为上限。

## 封面候选策略

当前没有接入真实画面分析或 AI 模型。三个候选入口只在已经抽取的时间轴帧中选择稳定、可复现的时间位置，并统一写回 `coverFrame` 与 `currentPosition`；它们不生成亮度、清晰度或构图分数。用户拖动封面控件时，状态自动切换到手动选择。

真实画面分析服务及其候选模型按当前范围暂缓。未来若重新立项，UI 仍应通过 `LiveEditorState` 消费结果，不把推理逻辑放进组件。

## Motion Collage

Flutter 仅提交声明式合成参数，Android 使用 Media3 `Composition` 创建并行 `EditedMediaItemSequence`：

```text
2～3 个素材 URI
├── 公共 startMs/endMs（以最短素材为上限）
├── CollageLayout：左右 / 上下 / 主次网格
├── collageAudioSourceIndex：唯一保留的主音轨
└── playbackSpeed + enhancementEnabled
    └── Transformer → 单路 MP4 → Motion Photo
```

多个序列从同一媒体时间起点开始，输出时间戳由相同速度参数统一变换。非主音轨序列只启用视频轨，避免混音削波与不可预测的声音叠加。

## 导出边界

`LiveEditorPage` 是 UI 与 `MediaEngine` 之间唯一的导出编排层。生成流程保持为：

1. 按 `coverFrame` 调用 `extractFrame` 获取精确封面。
2. 使用既有字段调用 `exportLive`。
3. Kotlin 将 MP4/JPG 发布到 `DCIM/AfterFrame`，将 `.live` 发布到 `Downloads/AfterFrame`。
4. Flutter 接收 `PublishedLive`，显示相册成功反馈并向上一页面返回 `LiveExport`。

导出协议传递起止时间、封面时间、声音、循环、速度、增强和拼图策略。速度使用 Media3 `SpeedProvider` 同时调整音视频时间戳；增强是固定的轻量 HSL 调整（饱和度 +8、亮度 +2），不使用内容识别。循环不复制视频样本，而作为 `AfterFrame:Loop` 写入 Motion Photo XMP 播放意图。

Android 10 及以上使用 MediaStore `RELATIVE_PATH` 与 `IS_PENDING`，完成写入后才公开媒体；任一发布步骤失败都会删除本次已经插入的项目。Android 9 及以下写入公共目录后通过 MediaScanner 建立系统索引。

## 缓存与作品索引

`MediaEngine` 用共享、限长的 Future 缓存合并相同 URI/时间戳的并发缩略图和抽帧请求，失败项立即移除以允许重试。缓存命中后还会确认本地文件仍存在，防止上层 Future 保存已经被原生淘汰的路径。Android 缩略图磁盘缓存保留 160 项，高于 Flutter 的 96 项路径缓存；生成结果通过“临时文件 → 完整编码 → 重命名”发布，UI 不会观察到半写入 JPEG。解码或文件读取失败时，素材卡会删除失效缓存并重新生成。

每次发布成功后，`ExportIndex` 使用 Android `SQLiteOpenHelper` 原子记录 Live URI、分享 URI、持久封面、名称、时间和 MIME 类型。App 启动时先读取 SQLite，再扫描 `DCIM/AfterFrame/*MP.jpg` 补回数据库缺失作品；恢复时读取 XMP `Item:Length`，从 Motion Photo 文件尾部重建私有 MP4 预览/聊天分享副本，并回写或升级 SQLite 索引。若第三方 Motion Photo 缺少该标准字段，仍保留 JPEG 原文件，但明确提示无法 Live 预览。

作品删除以 `liveUri` 作为稳定身份，并采用持久化两阶段语义：SQLite v2 先把 `deleting` 标记设为 1，再删除 App 拥有的 MediaStore Motion Photo、`files/afterframe/exports` 中的预览/分享 MP4、`files/afterframe/covers` 中的封面，最后移除 SQLite 行。每一步均把“不存在”视为已完成，因此同一请求可以安全重复。若进程中断，`listAndReconcile` 在下次启动先完成带删除标记的任务；没有标记但 Live URI 已失效的旧索引也会连同私有文件一起清除。只有原生返回可编码的 `null` 成功结果后 Flutter 才移除卡片；异常时重新读取索引，以原生真实状态覆盖内存列表。

## 视频预览边界

`LivePreviewCard` 持有并释放 `VideoPlayerController`，根据素材 URI 初始化 Android content URI 播放器。播放器负责画面、播放状态与进度；`LiveEditorState` 继续负责选区、声音、循环、速度和当前时间。

- 点击预览按钮播放或暂停。
- 播放到 `endTime` 时暂停，开启循环时跳回 `startTime`。
- 封面或选区变化会在安全状态下 seek，不改变导出时间语义。
- 播放位置以节流方式写回 `currentPosition`，避免高频刷新整个创作面板。

`MediaPreviewSheet` 是素材库和作品页共享的轻量预览边界。它自行持有并释放 `VideoPlayerController`，支持 `content://` 与文件 URI，用户明确打开后自动循环播放，并提供暂停、进度拖动与静音。素材卡的选择手势与预览入口分离，避免预览时意外改变拼图顺序。作品页优先播放导出时保留的私有 MP4；系统相册恢复项会先从标准 Motion Photo 尾部重建同类副本。只有缺少标准视频长度元数据的外部文件才提示暂不可预览，不会把 JPEG 错交给视频解码器。

## 视觉与动效层

- 颜色由 `AfterFrameColors` 统一提供，页面遵循黑色为主、灰色为辅、绿色点睛的比例。
- 玻璃面板由半透明表面色、细边框、背景模糊和柔和阴影组合，不引入高饱和霓虹或电竞视觉。
- 页面主体使用可滚动 Sliver 结构，预览与创作面板在小屏上仍可完整访问。
- 页面、卡片、模式切换、按钮和 Live 标识仅使用短时、低幅动效；`MediaQuery.disableAnimations` 为真时关闭位移、缩放和呼吸动画。

## 测试边界

- Dart 状态测试覆盖时间约束、拼图布局/主音轨、素材切换和生成状态。
- Widget 测试覆盖 320×568 小屏、模式切换、More Settings、生成反馈与按钮语义。
- MethodChannel 契约测试锁定速度、增强、多素材、布局和主音轨字段。
- Android instrumentation 契约测试覆盖 API 28、29、33、34 的权限与 Scoped MediaStore 策略分支；发布前仍需在对应设备矩阵执行真实相册回归。

## 扩展原则

- 新模式先扩展 `CreationMode` 和独立组件，再由页面决定组合关系。
- 未来的画面分析、滤镜和增强能力通过服务/配置模型接入，不在 Widget 中实现业务算法。
- 原生协议升级时集中修改 `MediaEngine` 与页面编排层，并补充契约测试。
- 状态继续增长时，可拆分 timeline、cover、export 子模型，但对组件保持统一作用域接口。
