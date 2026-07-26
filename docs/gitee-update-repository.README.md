# AfterFrame Update Channel

这是 AfterFrame Android 客户端的公开更新通道，不是应用源码仓库。

`master` 分支根目录必须始终同时包含：

- `update.json`
- `app-arm64-v8a-release.apk.sha1`
- `app-armeabi-v7a-release.apk.sha1`
- `app-x86_64-release.apk.sha1`

三个 APK 必须上传为同一 Gitee Release 的公开附件；Gitee 会阻止未登录用户匿名下载仓库中的大文件，因此 APK 不得作为普通仓库文件。清单和 SHA-1 必须由 AfterFrame 主项目的 `tool/prepare_gitee_update.ps1` 生成，并通过一次 Git commit 原子更新。不要手工编辑 SHA-1 或 `update.json`。

APK 必须始终使用同一份长期保存的正式签名密钥。Android 会拒绝签名不同或版本号没有提高的覆盖安装。

项目主页：https://github.com/Luyuan3014/AfterFrame
