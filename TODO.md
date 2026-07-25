# AfterFrame TODO

## 已完成

- [x] 移除 FFmpegKit、FFprobe、native ABI 打包规则和运行时测试。
- [x] 使用 Media3 1.10.1 Transformer 输出 H.264/AAC MP4。
- [x] 使用 Composition + VideoCompositorSettings 实现最多三路同步 Live 拼图。
- [x] 保留每路独立裁切、焦点裁剪、统一变速和指定主音轨。
- [x] 保留标准 Android Motion Photo 封装和聊天兼容 MP4 分享。
- [x] 将导出格式聚焦为 Motion Photo 与 MP4。

## 下一步

- [ ] 用 Media3 CompositionPlayer 统一多路预览与导出 Composition，减少预览/成片偏差。
- [ ] 为 Soft Fade、Film Grain 和动态漏光实现自定义 GL effect，并建立逐帧视觉回归。
- [ ] 增加真实视频 fixture 的 Media3 instrumentation export 测试。
- [ ] 增加导出进度事件、后台恢复和系统资源不足提示。
- [ ] 明确 HDR 保留与 SDR tone mapping 产品策略。
- [ ] 在 Pixel、Samsung、小米及高通/联发科设备执行相册、MediaCodec、微信和抖音矩阵验证。
