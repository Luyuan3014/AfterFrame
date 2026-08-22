# AfterFrame（余帧）

当前源码版本：**1.0.0+15**。

## Gitee 应用更新

当前版本提供 Android 同 ABI 安全更新。检查入口位于“我的 → 检查更新”。更新由系统下载服务在后台执行，完成后依次校验：远端 SHA-1、文件大小、APK 可解析性、包名、`versionCode`、`versionName`、当前 ABI 和已安装 App 的签名证书。校验通过后前台会自动打开系统安装器。只有远端 `versionCode` 严格大于当前版本才允许进入下载和安装流程，因此版本名写错、同版本重发和版本回退都会被拒绝。

生产更新仓库已固定为 `https://gitee.com/luyuan567/after_frame_update.git`，App 默认读取：

`https://gitee.com/luyuan567/after_frame_update/raw/master/update.json`

因此正式构建继续使用原始命令，不需要额外 `dart-define`：

```powershell
flutter build apk --release --split-per-abi
```

每次发布先提升 `pubspec.yaml` 中的版本，执行分 ABI 构建，然后在 Gitee 创建对应 Release（当前为 `v1.0.0`）并把三个 APK 上传为 Release 附件。仓库普通 raw 大文件会被 Gitee 对匿名用户返回 403，不能用作 App 下载源。

从 Gitee Release 页面 URL 或公开 API 获取数字 `ReleaseId`，再生成清单：

```powershell
$releaseId = (Invoke-RestMethod https://gitee.com/api/v5/repos/luyuan567/after_frame_update/releases/latest).id
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tool\prepare_gitee_update.ps1 -ReleaseId $releaseId -Notes "本次更新内容"
```

正式发布前必须在 `android/key.properties` 配置长期保存的 release keystore（字段为 `storeFile`、`storePassword`、`keyAlias`、`keyPassword`）。首个公开版本发布后绝不能更换或丢失该密钥，否则 Android 不允许覆盖升级。脚本默认拒绝 Android debug 证书；`-AllowDebugSigning` 只用于本地链路验证，不得用于公开发布。

脚本会读取三个 APK 内的真实包名、版本名、ABI、签名证书和各自的 Android `versionCode`，确认 Release 中存在三个同名附件，然后生成无 BOM 的 `.sha1` 和 `update.json`。仓库根目录只提交清单与三份 SHA-1；APK 只存在于 Release 附件中。

不要在 Gitee 网页中逐个替换文件。使用原子发布脚本先做本地提交检查，确认无误后再带 `-Push` 推送：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tool\publish_gitee_update.ps1 -BundleDirectory build/app/outputs/flutter-apk/gitee-update-1.0.0
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tool\publish_gitee_update.ps1 -BundleDirectory build/app/outputs/flutter-apk/gitee-update-1.0.0 -Push
```

完整的首次初始化、签名备份和日常发布步骤见 [Gitee 更新发布手册](docs/GITEE_UPDATE_RELEASE.md)。

特别说明：0.7.0 错误拒绝了 Gitee raw 的官方重定向域名，同时发布清单带有 BOM，因此已安装的 0.7.0 无法通过远端文件自愈。请手动安装一次 0.7.1；从 0.7.1 起，同版本会正确显示“当前已是最新版本”，后续版本可在 App 内更新。

普通侧载应用无法绕过 Android 的安装安全确认。首次安装更新时，系统可能要求允许 AfterFrame 安装未知来源应用；授权后返回 App 会自动继续打开系统安装页。App 不会申请 root、设备所有者权限或尝试静默替换自身。

AfterFrame 是 Android 优先的 Flutter 动态记忆编辑器：从相册视频或 Live 图选择片段，挑选封面，裁切为短视频，生成标准 Android Motion Photo，并提供适合微信、抖音等聊天场景分享的 MP4。它也支持最多三段视频/Live 图的同步 Live 拼图。

## 当前能力

- MediaStore 应用内素材选择：普通视频与 Android Live 图（动态照片）混选、顺序多选，并在进入 Studio 前预告作品形态
- 一套创作规则：1 段素材生成保留原始画幅的 Live 单帧，2～3 段素材生成 Adaptive Canvas 自动版式的 Live 拼图，无需选择模式；同比例格子等大，每段可独立选封面，时长不超过最短素材
- Studio 内可继续添加素材（最多 3 段），也可移除并撤销；删到 1 段自动回到单帧
- 原生视频信息读取、Live 图动态抽取、缩略图和精确封面抽帧
- 0.5x–2.0x 变速、裁切、静音/保留主素材音频和轻量色彩增强
- Media3 多视频 Composition，支持横向、纵向和主次网格布局及焦点裁切
- Media3 Transformer 输出 H.264/AAC MP4
- 单文件 JPEG + XMP + trailing MP4 的 Android Motion Photo 1.0 封装
- Motion Photo 发布到 `DCIM/AfterFrame`，普通 MP4 发布到 `Movies/AfterFrame`
- Motion Photo 原文件分享和聊天兼容 MP4 分享
- 本地作品索引、删除与 MediaStore 对账

## 媒体架构

```text
Flutter UI / editor state
          │ MethodChannel com.afterframe/media_engine
          ▼
MainActivity
  ├─ MediaStore / MediaMetadataRetriever（视频 + Live 图选择、解析、抽帧）
  ├─ MotionPhotoSource（Motion Photo / MicroVideo / HEIC 动态抽取）
  ├─ Media3RenderEngine（裁切、变速、效果、多路合成、MP4）
  └─ ExportService（Motion Photo 封装、发布、分享、作品索引）
```

项目不再依赖 FFmpegKit。Media3 1.10.1 使用 Android MediaCodec 和 OpenGL，覆盖 AfterFrame 核心的短视频创建与 Live 拼图，同时避免大型 native AAR、ABI/16KB ELF 对齐和额外许可证审计成本。

导出格式聚焦为 Motion Photo 与 MP4。GIF 和 animated WebP 不属于核心 Live 工作流，Media3 Transformer 也不原生编码这两种格式，因此已从产品入口移除。

## 本地验证

```powershell
flutter analyze --no-pub
flutter test --no-pub
cd android
.\gradlew.bat :app:compileDebugKotlin
.\gradlew.bat :app:assembleDebug
```

编译通过不能代替真机验证。正式发布前仍需覆盖主流 OEM 相册 Motion Photo 识别、不同芯片 MediaCodec 多路导出、HDR/色彩一致性，以及微信/抖音实际接收效果。
