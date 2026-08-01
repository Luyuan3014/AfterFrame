# AfterFrame Gitee 更新发布手册

## 1. Gitee 仓库配置

生产仓库：`https://gitee.com/luyuan567/after_frame_update.git`

需要保持：

- 仓库为公开仓库。
- 更新分支固定为 `master`。
- 根目录只存放 `update.json` 和三份 `.sha1`。
- 三个 APK 上传到同一个公开 Gitee Release，不能作为仓库普通文件。Gitee 对大 raw 文件的匿名请求返回 403。
- 不启用 Git LFS；LFS 指针也不是可安装 APK。

不需要在 App 中配置 Access Token、Webhook、Gitee Pages 或流水线。发布者需要使用 Gitee Release 页面上传 APK；App 通过公开 Release 附件下载，不携带账号凭据。

## 2. 首次发布前固定正式签名

同一个 Android applicationId 的所有后续更新必须使用同一份私钥。密钥丢失或更换后，Android 会拒绝覆盖安装，无法由更新代码绕过。

在项目根目录执行并按提示设置强密码：

```powershell
New-Item -ItemType Directory -Force android/keystores
keytool -genkeypair -v -keystore android/keystores/afterframe-release.jks -keyalg RSA -keysize 4096 -validity 10000 -alias afterframe
Copy-Item android/key.properties.example android/key.properties
```

编辑 `android/key.properties`，把两个密码占位值替换为刚才设置的密码。`key.properties` 和 `.jks` 已被 `.gitignore` 排除。

至少制作两份离线备份，并记录：

- `afterframe-release.jks`
- store password
- alias（默认 `afterframe`）
- key password

不要把密钥、密码或 `key.properties` 上传到 GitHub/Gitee、聊天工具或更新仓库。

## 3. 从 0.7.0 迁移到修复版

0.7.0 存在两个已确认问题：PowerShell 生成的 `update.json` 带 UTF-8 BOM；Gitee raw 会重定向到 `raw.giteeusercontent.com`，但 0.7.0 的域名白名单误拒绝该官方域名。另外，仓库普通 APK raw URL对匿名用户返回 403。

这些问题发生在解析清单之前，无法只靠修改远端清单修复已安装的 0.7.0。必须使用相同签名手动安装一次 0.7.1。不要卸载 0.7.0，直接覆盖安装可以保留应用数据。

### Android 16：从 0.7.5 及更早版本迁移到 0.7.6

0.7.5 及更早版本在 Android 16 上会把 **v2-only** 更新包误判为“无签名证书”并显示“更新未完成”。缺陷在已安装客户端内，发布新的 `update.json` 无法修好旧客户端。Android 16 用户需手动覆盖安装一次同签名的 0.7.6；Android 11 等仍能读到 archive 签名字段的机型不受影响，可继续走 App 内更新到 0.7.6。

构建 0.7.1：

```powershell
flutter build apk --release --split-per-abi
```

在 Gitee 仓库创建 Release：Tag 填 `v0.7.1`，目标分支 `master`，然后上传三个 0.7.1 APK。取得 ReleaseId：

```powershell
$releaseId = (Invoke-RestMethod https://gitee.com/api/v5/repos/luyuan567/after_frame_update/releases/latest).id
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tool\prepare_gitee_update.ps1 -ReleaseId $releaseId -Notes "修复 Gitee 更新检查与下载"
```

先执行不带 `-Push` 的预演：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tool\publish_gitee_update.ps1 -BundleDirectory build/app/outputs/flutter-apk/gitee-update-0.7.1
```

检查输出路径中的提交后，再执行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tool\publish_gitee_update.ps1 -BundleDirectory build/app/outputs/flutter-apk/gitee-update-0.7.1 -Push
```

脚本会从仓库根目录删除旧的三个普通 APK，并一次提交新版清单、SHA-1 和 README。推送可能要求登录 Gitee；不要把密码或 Token 写入脚本/仓库 URL。

## 4. 后续版本发布顺序

1. 先提升 `pubspec.yaml`，例如从当前 `1.0.0+15` 改为 `1.0.1+16`。`+` 后面的 build number 必须递增。
2. 使用原始分 ABI release 命令构建 APK：`flutter build apk --release --split-per-abi`。
3. 创建对应 Gitee Release，上传三个 APK 附件。
4. 用公开 API 读取 ReleaseId：`$releaseId = (Invoke-RestMethod https://gitee.com/api/v5/repos/luyuan567/after_frame_update/releases/latest).id`
，再带 `-ReleaseId` 运行 `prepare_gitee_update.ps1`：`powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tool\prepare_gitee_update.ps1 -ReleaseId $releaseId -Notes "修复 Gitee 更新检查与下载"`。脚本会验证三个 APK、Release 附件以及真实 versionCode，再生成 SHA-1 与无 BOM 清单。
5. 运行不带 `-Push` 的 `publish_gitee_update.ps1` 预演：`powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tool\publish_gitee_update.ps1 -BundleDirectory build/app/outputs/flutter-apk/gitee-update-1.0.1`。
6. 确认后带 `-Push` 原子更新清单和 SHA-1：`powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tool\publish_gitee_update.ps1 -BundleDirectory build/app/outputs/flutter-apk/gitee-update-1.0.1 -Push`。
7. 打开 raw `update.json` 并在低一版真机检查更新。

必须先上传完整 Release 附件，最后才提交 `update.json`。不要降低或复用 build number。

## 5. 仓库根目录结构

```text
README.md
update.json
app-arm64-v8a-release.apk.sha1
app-armeabi-v7a-release.apk.sha1
app-x86_64-release.apk.sha1
```

三个 APK 位于 Gitee Release 附件列表，不在 Git 树中。

Flutter split APK 会生成 ABI 特有的 Android versionCode。例如 1.0.0 的 build number 为 `15` 时，三个包应分别是 `2015`、`1015`、`4015`。不要手工统一这些值；App 会先确定当前安装 ABI，再比较对应资产的真实 versionCode。

## 6. 发布后验证清单

- 当前版本检查：显示“当前已是最新版本”。
- 低版本检查：只选择与已安装包相同的 ABI。
- 下载中切后台或结束进程：系统下载继续，重开后恢复进度/校验；下载完成且校验通过后前台应自动进入系统安装器。
- 错误 SHA-1、错误大小、错误包名、错误 ABI、错误签名、同版本和低版本：全部必须拒绝安装。
- 首次侧载授权：授权未知来源安装后返回 App，系统安装页自动继续打开。
- 三类 ABI 至少各验证一次；x86_64 通常用于模拟器，arm64-v8a/armeabi-v7a 需对应真机。
- 回归：低版本真机点“后台下载”后，进度走满不得再显示“更新未完成”；应出现系统安装确认页或“允许安装未知应用”设置页。
- Android 16 / API 36 真机或模拟器至少复测一次：正式包为 v2-only 签名时，客户端必须能从 APK Signing Block 读出证书并打开安装器。

普通应用无法静默绕过 Android 系统安装确认，这是平台安全边界，不属于失败。
