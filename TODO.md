# TODO

## Motion Canvas P0 — 导出所见即所得

- [x] 接入 Maven Central 的 FFmpeg 8.1.1 Android 包；AAR 约 67MB，支持 armeabi-v7a/arm64-v8a/x86/x86_64，冷启动与解压成本待真机基准。
- [ ] 定义版本化 `MotionCanvasExportSpec` JSON，包含画布、Clip、裁剪焦点、背景、转场、色彩、音轨和输出格式。
- [ ] 用 FFmpeg filter graph 实现 1080px 连续画布、40px 动态模糊背景、Soft Blur Blend、Soft Fade、Light Leak、Film Grain 与 Gradient Blend。
- [x] Android 导出消费 `cropFocusX/Y`，使用等比放大 + 定位裁剪窗口，禁止非等比拉伸。
- [ ] 增加导出帧与 Flutter 预览关键帧的视觉差异测试。
- [ ] 为导出任务增加进度、取消、后台恢复和磁盘空间预检。

## Motion Canvas P0 — Smart Crop

- [ ] 比较 ML Kit Face Detection、MediaPipe Tasks 与 OpenCV saliency 的延迟、包体和离线能力。
- [ ] 输出版本化 `SubjectDetectionResult`：人脸、人物、太阳/天空、显著区域、置信度和时间稳定性。
- [ ] 对 3～5 个时间采样点做追踪和平滑，避免裁剪焦点随帧跳动。
- [ ] 增加用户拖动构图焦点与恢复 AI 建议的交互。
- [ ] 覆盖横屏、竖屏、方形、旋转元数据、多人和低光素材。

## Motion Canvas P1 — 专业编辑

- [x] 为每个 Clip 增加双手柄范围编辑，支持独立滑动入点/出点。
- [ ] 将当前单张缩略图轨道升级为连续缩略图胶片带。
- [ ] 点击 Clip 进入单独编辑页：构图、速度、色彩、音量、替换素材。
- [ ] 长按交换增加触觉反馈、边缘自动滚动与撤销 Snackbar。
- [ ] Music 接入曲库、节拍检测、ducking 和版权信息，不只保留主素材音轨。
- [ ] 将 AI 优化结果做成可撤销 diff，并显示“调整了什么”。
- [ ] 为折叠屏、平板和横屏提供双栏工作区。

## Motion Canvas P1 — 格式与色彩

- [ ] 实现 GIF 调色板、帧率、循环和尺寸策略。
- [ ] 实现 animated WebP 编码与兼容性测试。
- [ ] 若建立 iOS target，实现真正的 Apple Live Photo 资源配对与 Photos 写入；Android 不显示伪 Live Photo 选项。
- [ ] 建立 SDR / HLG / HDR10 输入矩阵，明确 tone mapping、10-bit 编码和元数据保留策略。
- [ ] 原始色彩模式禁用非必要 HSL effect，并记录色彩空间转换。

## 发布前验证

- [ ] Pixel、Samsung、小米真机验证 2/3 路混合比例视频的同步、温度、内存与掉帧。
- [ ] Pixel / Samsung Gallery / 小米相册验证 Motion Photo 识别与播放。
- [ ] 微信、抖音分别验证 MP4 发送、接收、声音、画幅和二次压缩结果。
- [ ] 验证短于 500ms、超长、损坏、无音轨、可变帧率和 HDR 素材。
- [ ] 验证导出中断、应用退后台、磁盘不足和进程被杀后的恢复行为。
- [ ] 使用 320×568 小屏、常见 Android 尺寸、系统大字体和减少动态效果做视觉回归。

## 已完成

- [x] 独立 Motion Canvas 模块与页面入口。
- [x] 单一连续容器、无卡片边界、沉浸动态背景。
- [x] Master Timeline 多路同步预览与漂移纠正。
- [x] 四套模板、五种转场语言、风格与导出工具分区。
- [x] 点击选中、长按拖拽排序、实时预览和 Create Memory。
- [x] 独立 Clip 入点协议与最短公共输出长度。
- [x] 标准 Android Motion Photo + 聊天兼容 MP4 交付。
- [x] 静态分析、单元/Widget/MethodChannel 测试。
