# AfterFrame TODO

## 1.0.0 正式版

- [x] 将 Flutter/Android 版本提升为 `1.0.0+15`，保持 build number 严格递增。
- [x] 将变更记录、发布手册、README 和更新清单示例同步到 1.0.0。
- [x] 使用长期保存的 release keystore 构建三个 split APK，验证版本分别为 `2015/1015/4015`、ABI 单一、签名一致且非 debug。
- [x] 在 Gitee 创建公开 `v1.0.0` Release 并上传三个已验证 APK 附件。
- [x] 生成、预演并原子推送 1.0.0 `update.json` 与 SHA-1，随后验证匿名下载和低版本真机升级。

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
- [x] 重构“我的”页信息架构：移除不可编辑的假头像/ID，改为本地工作区品牌卡；按偏好、作品与导出、存储与隐私、支持与关于分组，取消“设置”统括全部入口。
- [x] 完整实现“我的”页面所有既有入口：作品相册导航、真实导出能力说明、Motion Photo/MP4 容器说明、运行时版本/ABI/隐私/开源许可，以及带范围保护的临时缓存统计与清理。
- [x] 将 App 语言统一为普通设置卡片与底部选择器；修复“我的”页常驻导致缓存统计不刷新的问题，并以原生单元测试锁定缓存清理边界。
- [x] 增加独立“隐私与数据”入口，说明本地处理、更新联网以及系统相册、私有持久副本和临时缓存的数据归属。
- [x] 取消“创作模式”概念：作品形态由素材数量派生，移除 Studio 内的模式选择器与来源选择器，并在素材选择页用真实 Adaptive Canvas 迷你版式预告形态。
- [x] 将素材上限、时长边界、形态判定和播放默认值收敛到 `live_rules.dart`，统一 Live 单帧与 Live 拼图的播放语义默认值。
- [x] 支持在 Studio 内移除拼图素材并可撤销；删到 1 段自动回到单帧规则。
- [x] 修复同比例不同分辨率（如 1920×1080 Live 静图 + 1280×720 视频）混排时格子大小不一致的问题，改为等格缩放。
- [x] Live 拼图每段可独立选择封面；成片时长不超过最短素材。
- [x] 素材选择页增加筛选、LIVE 徽章和有序已选托盘；Studio 未满 3 段时可继续添加素材。
- [x] 修复两路 720p 横屏素材误选 Film Strip 造成的大面积上下黑边和过宽中缝；自动布局改为外边缘闭合且默认间隔最多 4px。
- [x] 为 Adaptive Canvas 增加未覆盖面积惩罚，禁止自动方案用装饰留白换取源像素保留率。
- [x] 将 Frame/Smart Crop 升级为整数像素协议，并在 Media3 合成前执行零像素误差尺寸校验，避免边缘亚像素采样抖动。
- [x] 在 Android 16 x86_64 模拟器用原问题的两段 1280×720 素材完成编辑、导出和循环播放复测，确认无外围黑边且 Frame 分隔边界稳定。

- [x] 首页合并 Live 单帧/Live 拼图入口，统一有序选择 1～3 段素材并进入 AfterFrame Studio。
- [x] 精简「创作」页：单一导入主卡片，删除重复的 Studio 入口和不可点提示卡。
- [x] Studio 单帧把封面条与时间轴收成一条封面与范围轴；拼图去掉重复封面芯片和只读时间读数，点选素材轨再调当前段封面 / 裁剪。
- [x] 实况播放改为轻微放大、结束后回到封面静帧；编辑、全屏和作品预览共用 `LivePlaybackScale`。
- [x] Live 拼图彻底删除布局、风格、转场、音乐工具；编辑层级为预览、封面与范围（或素材轨）、更多设置，导出只走顶栏。
- [x] 移除 FFmpegKit、FFprobe、native ABI 打包规则和运行时测试。
- [x] 使用 Media3 1.10.1 Transformer 输出 H.264/AAC MP4。
- [x] 使用 Composition + VideoCompositorSettings 实现最多三路同步 Live 拼图。
- [x] 保留每路独立裁切、统一变速和第一路主音轨；声音、循环、增强和变速交互与 Live 单帧一致。
- [x] 将 Live 拼图重构为 Canvas First，统一画布像素尺寸、Frame 像素矩形和源空间 Smart Crop 窗口。
- [x] 实现纵向时间流、横向时间流、Pinterest、网格和 Film Strip 的 Adaptive Canvas 候选评分，保持用户时间顺序。
- [x] 建立 `crop pixels == frame pixels` 的 1:1 不变量；素材不足时缩小完整画布，不对单路素材执行 Fit/Fill/Stretch。
- [x] 支持在编辑画布直接拖动微调 Smart Crop，并可恢复确定性的构图安全区焦点。
- [x] 统一编辑预览、沉浸预览与导出使用同一 `AdaptiveCanvasPlan`；MethodChannel 冻结传递画布、Frame 和裁剪窗。
- [x] Media3 拼图导出改用 `Crop` + 原尺寸 compositor 定位，移除 `LAYOUT_SCALE_TO_FIT_WITH_CROP`。
- [x] 从最终拼图 MP4 抽取 Motion Photo/作品索引封面，保证导出后静态预览与合成画布一致。
- [x] Live 单帧和 Live 拼图均支持全屏预览，覆盖沉浸式系统栏、显式关闭、返回键、下滑退出和系统 UI 恢复。
- [x] 保留标准 Android Motion Photo 封装和聊天兼容 MP4 分享。
- [x] 将导出格式聚焦为 Motion Photo 与 MP4。

## 下一步

- [ ] 在 Android 真机验证“我的”页的大字体/横屏排版、缓存清理后的缩略图自动再生成，以及各 OEM 关于弹窗许可页的可滚动性。
- [ ] 在 Pixel、三星、小米真机验证 Live 图导入：筛选可见、抽出动态可预览、与视频混选拼图、导出 Motion Photo/MP4。
- [ ] 在真机确认实况点按播放会轻微放大、结束后回到封面静帧，并覆盖 Studio 单帧、拼图、全屏和作品预览。
- [ ] 在 ARM64 真机使用横屏、竖屏、旋转元数据和不同分辨率的真实素材逐像素核对 Smart Crop 边界、Frame 定位及预览/导出一致性。
- [ ] 增加 Media3 instrumentation fixture，读取导出 MP4 帧并验证画布尺寸、Frame 边界和 1:1 像素映射；覆盖 OEM 编码器尺寸回退。
- [ ] 评估完全离线、非 AI 云服务的主体显著性/人脸安全区数据源；接入时只更新 `CropFocus`，不得改变 Canvas First 几何契约。

- [ ] 用 Media3 CompositionPlayer 统一多路预览与导出 Composition，减少预览/成片偏差。
- [ ] 若未来重新确认复杂转场为产品需求，再独立评估自定义 GL effect；当前 Studio 不展示转场入口。
- [ ] 增加真实视频 fixture 的 Media3 instrumentation export 测试。
- [ ] 增加导出进度事件、后台恢复和系统资源不足提示。
- [ ] 明确 HDR 保留与 SDR tone mapping 产品策略。
- [ ] 在 Pixel、Samsung、小米及高通/联发科设备执行相册、MediaCodec、微信和抖音矩阵验证。
