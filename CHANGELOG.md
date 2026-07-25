# Changelog

本项目的重要变更记录于此。

## 0.3.2 - 2026-07-25

### 删除崩溃与残留修复

- 修复 `deleteExport` 后台任务把不可序列化的 Kotlin `Unit` 交给 `StandardMessageCodec`，导致删除完成后 Android UI 主线程崩溃的问题；void 原生调用现在明确返回 `null`。
- SQLite 作品索引升级到 v2，增加持久化删除标记。删除在修改 MediaStore 前先记录意图，进程若在任一步被终止，下次启动会自动继续清理。
- 删除流程改为幂等：相册项目、封面、私有 MP4 或索引任意一项已经不存在时仍可安全重试；显式删除失败会恢复可操作状态，不会令按钮永久失效。
- 启动恢复会校验每条 Live URI，自动清除“相册文件已不存在但索引仍存在”的幽灵作品；扫描期间遇到已删除或损坏的 Motion Photo 会跳过该项，不再中断整个作品列表。
- Flutter 删除期间锁定对应作品的预览、分享和删除操作并展示进度，防止快速连点；异常后立即重新读取原生索引，以实际文件状态决定显示“删除成功”或“删除失败”。

### 验证

- 已在 Android 16 模拟器复现原崩溃并确认异常为 `Unsupported value: 'kotlin.Unit'`；修复后重新执行静态分析、测试、Android 编译及真实删除回归。

## 0.3.1 - 2026-07-25

### 素材与作品预览

- “选择视频”素材卡新增独立播放入口并支持长按预览；预览页支持自动循环、播放/暂停、拖动进度和静音切换，点击卡片本身仍只负责选择素材。
- “我的余帧”作品卡补齐 Live 预览、分享、删除三项常用操作；点击作品封面可直接预览私有 MP4 副本。
- 删除前增加不可撤销确认，确认后由 Android 同步移除公开 Motion Photo、私有 MP4、持久封面与 SQLite 作品索引。

### 缩略图黑屏修复

- 修复 Flutter 内存缓存保存 96 个路径、Android 磁盘缓存只保留 48 个文件导致的缓存失配；磁盘缓存上限提升到 160，始终覆盖上层路径缓存。
- Flutter 每次复用缓存路径前检查文件是否仍存在，失效项自动移除并重新请求；缩略图加载/解码失败时提供显式重试。
- Android 缩略图先写临时文件，完整编码后再原子重命名，避免 Flutter 在 JPEG 尚未写完时读取到半成品。
- MediaStore 扫描恢复的作品会依据 XMP 视频长度从 Motion Photo 尾部重建私有 MP4 预览副本，并回写/升级 SQLite，保证历史作品也可预览、视频分享和完整删除。

### 验证边界

- 新增 `deleteExport` MethodChannel 参数契约测试。
- Flutter 静态分析、单元测试和 Android Debug 构建结果见本次交付说明；大量视频快速滚动、OEM 解码器和真实删除回归仍需真机矩阵验证。

## 0.3.0 - 2026-07-25

### 原生导出语义

- `MediaEngine.exportLive` 新增播放速度、轻量增强、多素材 URI、拼图布局和主音轨参数。
- Media3 导出实际应用 0.5x/1x/1.5x/2x 速度并保持音画同步；增强使用固定的轻微亮度与饱和度调整，不涉及 AI 推理。
- 循环保持为 Motion Photo 播放意图元数据，不复制 MP4 内容，避免文件体积无意义翻倍。

### Motion Collage

- 拼图布局、主音轨素材与多素材数量纳入 `LiveEditorState`，素材选择限制为 2～3 段。
- 多素材使用相同起止范围并行裁剪，通过 Media3 `Composition` 输出左右、上下或主次网格布局。
- 只保留用户指定素材的音轨，其余输入静音；时间范围以最短素材为上限，避免尾部空帧。

### 缓存、作品与无障碍

- 缩略图和时间轴帧增加共享 Future 内存缓存；原生 JPEG 磁盘缓存增加命中复用与 48/128 项淘汰上限。
- 新增 SQLite 作品索引，保存持久封面、分享 URI 与创建时间；启动时同时扫描 `DCIM/AfterFrame` 补回缺失的 MediaStore 作品。
- 跟随系统“减少动态效果”，关闭页面位移揭示、模式切换、按钮缩放与 `AFTER LIVE` 呼吸动画。

### 测试与质量

- 新增小屏模式切换、More Settings、生成状态与按钮无障碍语义 Widget 测试。
- 新增导出 MethodChannel 参数契约、拼图集中状态、语言键和动态占位符完整性测试。
- 新增 Android 9、10、13、14 权限与 MediaStore 策略 instrumentation 契约测试。
- Flutter/Android Debug 联编与 Kotlin 编译通过。

### 暂缓

- 按当前产品范围，真实画面分析服务、`AiMoment` 模型及其他 AI 能力均未实现。

## 0.2.1 - 2026-07-25

### 全局语言

- 新增应用级中英文资源层，首页、媒体选择器、Live Studio、作品页、个人页和状态提示统一随语言切换。
- 在“我的 / Profile”增加 App 语言设置，切换立即全局生效，并通过 Android SharedPreferences 持久化。
- 中文模式恢复 Live Studio 的完整中文创作语境；品牌名 `AfterFrame`、`AFTER LIVE` 和格式名保持不翻译。

### 视频预览

- 接入 Flutter 官方 `video_player 2.11.1`，使用 Android `content://` 媒体 URI 真实播放导入视频。
- 预览支持播放、暂停、缓冲/进度展示、声音、速度和选区结束处理。
- 播放位置同步至 `LiveEditorState.currentPosition`；开启循环后在 Live 选区内循环。
- 封面图继续作为播放器初始化与异常状态的视觉兜底。

### 系统相册导出

- 导出完成后通过 Android MediaStore 将 MP4 与封面 JPG 发布到公共 `DCIM/AfterFrame` 相册。
- 将开放 `.live` 容器同步发布到公共 `Downloads/AfterFrame`，不再依赖应用私有目录。
- 导出采用 `IS_PENDING` 写入协议，失败时清理已发布项目，避免相册出现半成品。
- 导出结果改为结构化 `PublishedLive`，包含相册 URI、封面 URI、Live URI、作品名和相册名。
- Android 9 及以下补充公共存储写入权限和 MediaScanner 兼容路径。

### 验证

- 新增中英文资源、动态占位符和播放位置约束测试，共 10 项测试通过。
- `flutter analyze` 无问题，Android Debug APK 构建通过。
- 已在 Android 16 模拟器验证中文/英文切换、重启持久化、MediaStore 视频读取、真实预览播放和完整导出。
- MediaStore 实测生成 `DCIM/AfterFrame/*.mp4`、`DCIM/AfterFrame/*.jpg` 与 `Downloads/AfterFrame/*.live`。

## 0.2.0 - 2026-07-25

### Live Studio 视觉升级

- 将顶部标题升级为 `AfterFrame Studio`，增加副标题 `Create your living moment`，并保留返回与导出入口。
- 建立 Dark Cinematic 视觉体系：深黑背景、半透明玻璃面板、大圆角、柔和阴影与克制的品牌绿色强调。
- 将视频预览保持为页面视觉中心；播放按钮缩小约 40%，增加磨砂玻璃质感。
- 将普通 `LIVE` 标识替换为带呼吸动画的品牌标识 `AFTER LIVE`。
- 将创作模式从 Tab 改为 `Live Frame` / `Motion Collage` 双卡片选择，并补充英文说明。
- 将固定底部操作区改为可滚动玻璃创作面板，改善小屏设备的信息密度与可达性。

### 创作体验

- 封面区更名为 `Choose Cover Moment`，提供 `AI Recommended` 与 `Manual Select` 两种入口。
- 新增 `Best Light`、`Sharpest`、`Best Composition` 三类可复现推荐候选；推荐基于当前抽取帧，不依赖远端服务。
- 重塑摄影感时间轴，展示缩略图轨道、当前时间、Live 长度、封面位置、范围边界和 `Best Moment` 标记。
- 将声音、循环、速度、增强效果收纳至默认折叠的 `More Settings`。
- 生成按钮更新为 `Create AfterFrame Live`，高度 72px、圆角 36px，并加入按压缩放和柔光反馈。
- 增加页面淡入、卡片出现、模式切换和控件状态过渡动画。

### 状态与兼容性

- `LiveEditorState` 新增封面选择模式、封面推荐类型、增强效果状态与 Live 长度派生值。
- 保持原有封面精确抽帧与 `exportLive` 调用顺序、起止时间、声音和循环参数语义不变。
- 播放速度与增强效果目前仍是 UI/状态层扩展点，不会改变原生导出结果。
- 新增 AI 候选选择、手动封面模式和增强效果状态测试；静态分析与全部测试通过。

## 0.1.0 - 2026-07-24

### 第一阶段组件化重构

- 将原 `StudioScreen` 单文件编辑页重构为 `LiveEditorPage`。
- 引入集中式 `LiveEditorState`，统一管理媒体、时间区间、封面、模式、声音、循环和生成状态。
- 拆分预览、创作模式、封面、时间轴、设置和生成按钮等独立组件。
- 保留 `StudioScreen` 兼容入口与现有原生 `MediaEngine` 视频处理通道。
- 为状态初始化、时间范围约束和媒体切换重置增加测试。
