# AfterFrame 架构说明

## 产品与页面目标

AfterFrame 将视频素材转化为可反复观看的动态记忆。Live 编辑页以“发现精彩瞬间 → 选择封面 → 生成 Live 作品”为核心路径。第二阶段只升级展示与交互层，不改变原生视频处理协议。

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
└── LiveEditorPage
    ├── LiveEditorState                 单一状态源
    ├── MediaEngine                     原生媒体能力边界
    └── LiveEditorScope                 向组件发布状态
        ├── LivePreviewCard             video_player、选区播放、AFTER LIVE 动效
        ├── SourceSelector              多素材来源切换
        ├── CreationModeSelector        Live Frame / Motion Collage 卡片
        ├── CoverSelector               AI 候选与手动封面选择
        ├── CollageLayoutSelector       拼图布局入口
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
- 创作：`mode`、`coverSelectionMode`、`selectedInsight`
- 设置与任务：`audioEnabled`、`loopEnabled`、`playbackSpeed`、`enhancementEnabled`、`generateStatus`

时间状态始终遵循以下约束：

```text
0 <= startTime < endTime <= duration
endTime - startTime >= 500ms
startTime <= coverFrame/currentPosition <= endTime
```

切换素材时会重置帧、时间窗口、封面推荐与生成状态，但保留用户选择的创作模式。

## 封面推荐策略

第二阶段没有接入真实 AI 模型。`Best Light`、`Sharpest`、`Best Composition` 会在已经抽取的时间轴帧中选择稳定、可复现的候选位置，并统一写回 `coverFrame` 与 `currentPosition`。用户拖动封面控件时，状态自动切换到 `Manual Select`。

未来接入真实分析服务时，应由独立服务返回带时间戳、分数和标签的不可变候选模型；UI 继续通过 `LiveEditorState` 消费结果，不应把推理逻辑放进组件。

## 导出边界

`LiveEditorPage` 是 UI 与 `MediaEngine` 之间唯一的导出编排层。生成流程保持为：

1. 按 `coverFrame` 调用 `extractFrame` 获取精确封面。
2. 使用既有字段调用 `exportLive`。
3. Kotlin 将 MP4/JPG 发布到 `DCIM/AfterFrame`，将 `.live` 发布到 `Downloads/AfterFrame`。
4. Flutter 接收 `PublishedLive`，显示相册成功反馈并向上一页面返回 `LiveExport`。

本阶段仍传递起止时间、封面时间、声音和循环设置。`playbackSpeed` 与 `enhancementEnabled` 只存在于 UI/状态层，尚未写入原生导出协议，避免视觉优化意外改变成片行为。

Android 10 及以上使用 MediaStore `RELATIVE_PATH` 与 `IS_PENDING`，完成写入后才公开媒体；任一发布步骤失败都会删除本次已经插入的项目。Android 9 及以下写入公共目录后通过 MediaScanner 建立系统索引。

## 视频预览边界

`LivePreviewCard` 持有并释放 `VideoPlayerController`，根据素材 URI 初始化 Android content URI 播放器。播放器负责画面、播放状态与进度；`LiveEditorState` 继续负责选区、声音、循环、速度和当前时间。

- 点击预览按钮播放或暂停。
- 播放到 `endTime` 时暂停，开启循环时跳回 `startTime`。
- 封面或选区变化会在安全状态下 seek，不改变导出时间语义。
- 播放位置以节流方式写回 `currentPosition`，避免高频刷新整个创作面板。

## 视觉与动效层

- 颜色由 `AfterFrameColors` 统一提供，页面遵循黑色为主、灰色为辅、绿色点睛的比例。
- 玻璃面板由半透明表面色、细边框、背景模糊和柔和阴影组合，不引入高饱和霓虹或电竞视觉。
- 页面主体使用可滚动 Sliver 结构，预览与创作面板在小屏上仍可完整访问。
- 页面、卡片、模式切换、按钮和 Live 标识仅使用短时、低幅动效；不参与业务状态判定。

## 扩展原则

- 新模式先扩展 `CreationMode` 和独立组件，再由页面决定组合关系。
- AI、滤镜和增强能力通过服务/配置模型接入，不在 Widget 中实现业务算法。
- 原生协议升级时集中修改 `MediaEngine` 与页面编排层，并补充契约测试。
- 状态继续增长时，可拆分 timeline、cover、export 子模型，但对组件保持统一作用域接口。
