# Changelog

## 0.1.0 - 2026-07-24

### Changed

- 将原 `StudioScreen` 单文件编辑页重构为 `LiveEditorPage` Live 创作工作台。
- 引入集中式 `LiveEditorState`，统一管理媒体、时间区间、封面、模式、声音、循环和生成状态。
- 拆分预览、创作模式、封面、时间轴、高级设置和生成按钮等独立组件。
- 将高级设置调整为默认折叠，并预留播放速度设置接口。
- 保留 `StudioScreen` 兼容入口，现有调用方可渐进迁移。

### Preserved

- 原生 `MediaEngine` 及 Android 视频处理实现未修改。
- 导出仍按“精确提取封面帧 → 调用 `exportLive`”的顺序执行。
- 导出的起止时间、封面时间、声音与循环参数语义保持不变。

### Added

- 为 Live Frame、Motion Collage 及未来 AI Story 建立可扩展的模式模型边界。
- 生成按钮支持 `idle`、`processing`、`success`、`failed` 四种状态。
- 新增状态模型测试，覆盖初始化、时间范围约束和媒体切换重置。
- 新增 `ARCHITECTURE.md` 与 `TODO.md`。
