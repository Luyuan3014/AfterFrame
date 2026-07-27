param(
    [Parameter(Mandatory = $true)] [string] $BundleDirectory,
    [string] $RemoteUrl = "https://gitee.com/luyuan567/after_frame_update.git",
    [string] $Branch = "master",
    [string] $Message = "Publish AfterFrame update",
    [switch] $Push
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$bundleRoot = [IO.Path]::GetFullPath((Join-Path $projectRoot $BundleDirectory))
$requiredFiles = @(
    "update.json",
    "app-arm64-v8a-release.apk",
    "app-arm64-v8a-release.apk.sha1",
    "app-armeabi-v7a-release.apk",
    "app-armeabi-v7a-release.apk.sha1",
    "app-x86_64-release.apk",
    "app-x86_64-release.apk.sha1"
)
$metadataFiles = @(
    "update.json",
    "app-arm64-v8a-release.apk.sha1",
    "app-armeabi-v7a-release.apk.sha1",
    "app-x86_64-release.apk.sha1"
)
$repositoryApkFiles = @(
    "app-arm64-v8a-release.apk",
    "app-armeabi-v7a-release.apk",
    "app-x86_64-release.apk"
)

foreach ($fileName in $requiredFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $bundleRoot $fileName) -PathType Leaf)) {
        throw "Incomplete update bundle. Missing: $fileName"
    }
}

$manifest = Get-Content -LiteralPath (Join-Path $bundleRoot "update.json") -Raw -Encoding UTF8 | ConvertFrom-Json
if ($manifest.schemaVersion -ne 1 -or $manifest.packageName -ne "com.example.after_frame") {
    throw "Unexpected update manifest schema or package name"
}
$expectedBaseUrl = "https://gitee.com/luyuan567/after_frame_update/raw/$Branch"
foreach ($abi in @("arm64-v8a", "armeabi-v7a", "x86_64")) {
    $asset = $manifest.assets.$abi
    $apkUri = if ($asset) { [Uri]$asset.apkUrl } else { $null }
    if (-not $asset -or $apkUri.Scheme -ne "https" -or $apkUri.Host -ne "gitee.com" -or
        $apkUri.AbsolutePath -notmatch "/luyuan567/after_frame_update/releases/download/[^/]+/app-$([regex]::Escape($abi))-release\.apk$" -or
        $asset.sha1Url -ne "$expectedBaseUrl/app-$abi-release.apk.sha1") {
        throw "Manifest URLs do not match the production Gitee channel for ABI $abi"
    }
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$checkout = Join-Path $projectRoot "build/gitee-publish-$timestamp"
git clone $RemoteUrl $checkout
if ($LASTEXITCODE -ne 0) { throw "Unable to clone the Gitee update repository" }

$remoteHeads = git -C $checkout ls-remote --heads origin $Branch
if ($LASTEXITCODE -ne 0) { throw "Unable to inspect the Gitee branch" }
if (-not $remoteHeads) {
    git -C $checkout symbolic-ref HEAD "refs/heads/$Branch"
} else {
    git -C $checkout checkout $Branch
    if ($LASTEXITCODE -ne 0) { throw "Unable to check out $Branch" }
}

foreach ($fileName in $metadataFiles) {
    Copy-Item -LiteralPath (Join-Path $bundleRoot $fileName) -Destination (Join-Path $checkout $fileName) -Force
}
Copy-Item -LiteralPath (Join-Path $projectRoot "docs/gitee-update-repository.README.md") -Destination (Join-Path $checkout "README.md") -Force
# APKs live on Gitee Release attachments, not in the Git tree. Only remove
# legacy repository APKs if a previous publish still left them tracked.
foreach ($fileName in $repositoryApkFiles) {
    $repositoryApk = Join-Path $checkout $fileName
    if (Test-Path -LiteralPath $repositoryApk -PathType Leaf) {
        git -C $checkout rm -f -- $fileName
        if ($LASTEXITCODE -ne 0) { throw "Unable to remove legacy repository APK: $fileName" }
    }
}

# Stage only root metadata. Do not pathspec the APK names when they are absent —
# `git add` fails with "pathspec did not match any files" on a clean Release-only repo.
git -C $checkout add -- README.md @metadataFiles
if ($LASTEXITCODE -ne 0) { throw "Unable to stage the update bundle" }
git -C $checkout diff --cached --check
if ($LASTEXITCODE -ne 0) { throw "The staged update bundle failed Git checks" }
git -C $checkout commit -m $Message
if ($LASTEXITCODE -ne 0) { throw "Unable to commit the update bundle. Configure your Git user.name and user.email." }

if ($Push) {
    git -C $checkout push origin $Branch
    if ($LASTEXITCODE -ne 0) { throw "Gitee push failed. Check your Gitee credentials or SSH configuration." }
    Write-Host "Published atomically to $RemoteUrl ($Branch)."
} else {
    Write-Host "Dry run complete. The committed checkout is: $checkout"
    Write-Host "Inspect it, then rerun with -Push to publish to Gitee."
}
