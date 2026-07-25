# AfterFrame（余帧）

AfterFrame 是 Android 优先的 Flutter 动态记忆编辑器：从相册视频选择片段，挑选封面，裁切为短视频，生成标准 Android Motion Photo，并提供适合微信、抖音等聊天场景分享的 MP4。它也支持最多三段视频的同步 Live 拼图。

## 当前能力

- MediaStore 应用内视频选择、顺序多选和显式完成确认
- 原生视频信息读取、缩略图和精确封面抽帧
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
  ├─ MediaStore / MediaMetadataRetriever（选择、解析、抽帧）
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
