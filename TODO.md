# AfterFrame TODO

## 0.7.1 应用更新修复

- [x] 复现并修复 `update.json` UTF-8 BOM 导致 Android JSON 解析失败。
- [x] 允许 Gitee raw 官方重定向域名 `raw.giteeusercontent.com`，仍拒绝非 Gitee 主机。
- [x] 发布清单强制 UTF-8 无 BOM，并增加 BOM 回归测试。
- [x] 识别 Gitee 仓库大 raw APK 匿名下载 403，改用公开 Release 附件作为 APK 源。
- [x] 发布工具要求 ReleaseId、验证三个附件，并禁止默认生成不可用的仓库 raw APK URL。
- [x] 创建并上传 `v0.7.1` Gitee Release，发布修复清单；0.7.0 用户需手动覆盖安装一次。

## 0.7.0 应用更新

- [x] 增加 Gitee `update.json` 检查、严格 `versionCode` 升级判断和同 ABI 资源选择。
- [x] 使用 Android DownloadManager 后台下载，并持久化下载、校验、待安装状态。
- [x] 安装前校验 APK 大小、SHA-1、包名、版本、ABI 和签名证书。
- [x] 增加现代化更新底部面板、后台进度、校验状态和系统安装授权衔接。
- [x] 增加发布脚本，自动从实际 split APK 生成 `.sha1` 和 `update.json`。
- [x] 配置 Gitee 公开仓库 `luyuan567/after_frame_update` 的生产 raw 清单地址和 `master` 更新通道。
- [x] 增加 Gitee 原子发布/预演脚本。
- [x] 使用正式签名完成空仓库首次 `master` 提交。
- [ ] 正式首发前创建、离线备份 release keystore，并配置 `android/key.properties`；不得使用 debug 签名上传公开更新。
- [ ] 在 arm64-v8a、armeabi-v7a、x86_64 三类设备/模拟器分别验证下载与安装；至少覆盖断网、进程重启、错误 SHA-1、错误签名和低版本清单。

## 已完成

- [x] 首页合并 Live 单帧/Live 拼图入口，统一有序选择 1～3 段素材并进入 AfterFrame Studio。
- [x] 在 Studio 内完成模式切换；Live 拼图彻底删除布局、风格、转场、音乐工具，统一为单帧的预览、封面、时间轴、更多设置和生成层级。
- [x] 移除 FFmpegKit、FFprobe、native ABI 打包规则和运行时测试。
- [x] 使用 Media3 1.10.1 Transformer 输出 H.264/AAC MP4。
- [x] 使用 Composition + VideoCompositorSettings 实现最多三路同步 Live 拼图。
- [x] 保留每路独立裁切、统一变速和第一路主音轨；声音、循环、增强和变速交互与 Live 单帧一致。
- [x] 按素材比例自动选择裁切损失最小的满版分栏；Flutter `BoxFit.cover` 与 Media3 `LAYOUT_SCALE_TO_FIT_WITH_CROP` 共用槽位并禁止拉伸。
- [x] Live 单帧和 Live 拼图均支持全屏预览，覆盖沉浸式系统栏、显式关闭、返回键、下滑退出和系统 UI 恢复。
- [x] 保留标准 Android Motion Photo 封装和聊天兼容 MP4 分享。
- [x] 将导出格式聚焦为 Motion Photo 与 MP4。

## 下一步

- [ ] 用 Media3 CompositionPlayer 统一多路预览与导出 Composition，减少预览/成片偏差。
- [ ] 若未来重新确认复杂转场为产品需求，再独立评估自定义 GL effect；当前 Studio 不展示转场入口。
- [ ] 增加真实视频 fixture 的 Media3 instrumentation export 测试。
- [ ] 增加导出进度事件、后台恢复和系统资源不足提示。
- [ ] 明确 HDR 保留与 SDR tone mapping 产品策略。
- [ ] 在 Pixel、Samsung、小米及高通/联发科设备执行相册、MediaCodec、微信和抖音矩阵验证。
