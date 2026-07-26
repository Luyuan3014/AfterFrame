param(
    [string] $Owner = "luyuan567",
    [string] $Repository = "after_frame_update",
    [string] $Branch = "master",
    [string] $ApkDirectory = "build/app/outputs/flutter-apk",
    [string] $Notes = "",
    [long] $ReleaseId = 0,
    [switch] $AllowRepositoryApkUrls,
    [switch] $AllowDebugSigning
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$apkRoot = [IO.Path]::GetFullPath((Join-Path $projectRoot $ApkDirectory))
$abis = @("arm64-v8a", "armeabi-v7a", "x86_64")
$apkFiles = @{}
foreach ($abi in $abis) {
    $path = Join-Path $apkRoot "app-$abi-release.apk"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing split APK: $path. Run flutter build apk --release --split-per-abi first."
    }
    $apkFiles[$abi] = Get-Item -LiteralPath $path
}

$localProperties = Get-Content -LiteralPath (Join-Path $projectRoot "android/local.properties")
$sdkLine = $localProperties | Where-Object { $_ -like "sdk.dir=*" } | Select-Object -First 1
if (-not $sdkLine) { throw "android/local.properties does not contain sdk.dir" }
$sdkRoot = ($sdkLine.Substring("sdk.dir=".Length) -replace '\\\\', '\')
$aapt = Get-ChildItem -LiteralPath (Join-Path $sdkRoot "build-tools") -Filter "aapt.exe" -Recurse |
    Sort-Object { [version]$_.Directory.Name } -Descending | Select-Object -First 1
if (-not $aapt) { throw "aapt.exe was not found in Android build-tools" }
$apksigner = Join-Path $aapt.Directory.FullName "apksigner.bat"
if (-not (Test-Path -LiteralPath $apksigner -PathType Leaf)) {
    throw "apksigner.bat was not found beside aapt.exe"
}

$expectedPackage = $null
$expectedVersionName = $null
$versionCodes = @{}
$expectedSignerDigest = $null
foreach ($abi in $abis) {
    $badgingOutput = & $aapt.FullName dump badging $apkFiles[$abi].FullName
    $badging = $badgingOutput | Select-Object -First 1
    if ($LASTEXITCODE -ne 0 -or $badging -notmatch "package: name='([^']+)' versionCode='([0-9]+)' versionName='([^']+)'") {
        throw "Unable to read package metadata from $($apkFiles[$abi].Name)"
    }
    $packageName = $Matches[1]
    $versionCode = [long]$Matches[2]
    $versionName = $Matches[3]
    $nativeCode = $badgingOutput | Where-Object { $_ -like "native-code:*" } | Select-Object -First 1
    if ($nativeCode -ne "native-code: '$abi'") {
        throw "$($apkFiles[$abi].Name) does not contain exactly the expected ABI $abi"
    }
    $signerOutput = & $apksigner verify --print-certs $apkFiles[$abi].FullName
    if ($LASTEXITCODE -ne 0) { throw "APK signature verification failed for $($apkFiles[$abi].Name)" }
    $signerDnLine = $signerOutput | Where-Object { $_ -like "Signer #1 certificate DN:*" } | Select-Object -First 1
    $signerDigestLine = $signerOutput | Where-Object { $_ -like "Signer #1 certificate SHA-256 digest:*" } | Select-Object -First 1
    if (-not $signerDnLine -or -not $signerDigestLine) { throw "Unable to read APK signer certificate" }
    $signerDigest = ($signerDigestLine -split ': ', 2)[1].Trim()
    if ($null -eq $expectedSignerDigest) {
        $expectedSignerDigest = $signerDigest
    } elseif ($signerDigest -ne $expectedSignerDigest) {
        throw "Split APK signing certificates are inconsistent"
    }
    if (-not $AllowDebugSigning -and $signerDnLine -like "*CN=Android Debug*") {
        throw "Refusing to publish APKs signed with the Android debug certificate. Configure android/key.properties with a stable release key."
    }
    if ($null -eq $expectedPackage) {
        $expectedPackage = $packageName
        $expectedVersionName = $versionName
    } elseif ($packageName -ne $expectedPackage -or $versionName -ne $expectedVersionName) {
        throw "Split APK package names or version names are inconsistent"
    }
    $versionCodes[$abi] = $versionCode
}

$safeVersionName = $expectedVersionName -replace '[^0-9A-Za-z._-]', '_'
$releaseRoot = Join-Path $apkRoot "gitee-update-$safeVersionName"
New-Item -ItemType Directory -Path $releaseRoot -Force | Out-Null
$releaseAttachments = $null
if ($ReleaseId -gt 0) {
    $releaseDetailsUrl = "https://gitee.com/api/v5/repos/$Owner/$Repository/releases/$ReleaseId"
    $releaseDetails = Invoke-RestMethod -Method Get -Uri $releaseDetailsUrl
    if (-not $releaseDetails.tag_name) { throw "Gitee Release $ReleaseId has no tag" }
    $releaseTag = [Uri]::EscapeDataString([string]$releaseDetails.tag_name)
    $attachmentsUrl = "https://gitee.com/api/v5/repos/$Owner/$Repository/releases/$ReleaseId/attach_files?per_page=100"
    $releaseAttachments = Invoke-RestMethod -Method Get -Uri $attachmentsUrl
} elseif (-not $AllowRepositoryApkUrls) {
    throw "Gitee blocks anonymous raw downloads for large APK files. Upload all three APKs to a public Gitee Release, then rerun with -ReleaseId <id>."
}
$assets = [ordered]@{}
foreach ($abi in $abis) {
    $fileName = $apkFiles[$abi].Name
    $releaseApk = Join-Path $releaseRoot $fileName
    Copy-Item -LiteralPath $apkFiles[$abi].FullName -Destination $releaseApk -Force
    $hash = (Get-FileHash -LiteralPath $releaseApk -Algorithm SHA1).Hash.ToLowerInvariant()
    Set-Content -LiteralPath "$releaseApk.sha1" -Value "$hash  $fileName" -Encoding ascii
    if ($ReleaseId -gt 0) {
        $attachment = $releaseAttachments | Where-Object { $_.name -eq $fileName } | Select-Object -First 1
        if (-not $attachment -or -not $attachment.id) {
            throw "Gitee Release $ReleaseId is missing attachment $fileName"
        }
        $apkUrl = "https://gitee.com/$Owner/$Repository/releases/download/$releaseTag/$fileName"
    } else {
        $escapedBranch = [Uri]::EscapeDataString($Branch)
        $apkUrl = "https://gitee.com/$Owner/$Repository/raw/$escapedBranch/$fileName"
    }
    $sha1Url = "https://gitee.com/$Owner/$Repository/raw/$([Uri]::EscapeDataString($Branch))/$fileName.sha1"
    $assets[$abi] = [ordered]@{
        fileName = $fileName
        versionCode = $versionCodes[$abi]
        apkUrl = $apkUrl
        sha1Url = $sha1Url
        size = (Get-Item -LiteralPath $releaseApk).Length
    }
}

$manifest = [ordered]@{
    schemaVersion = 1
    packageName = $expectedPackage
    versionName = $expectedVersionName
    publishedAt = [DateTimeOffset]::UtcNow.ToString("o")
    notes = $Notes
    assets = $assets
}
$manifestJson = $manifest | ConvertTo-Json -Depth 6
$utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText(
    (Join-Path $releaseRoot "update.json"),
    $manifestJson + [Environment]::NewLine,
    $utf8WithoutBom
)
Write-Host "Gitee update bundle ready: $releaseRoot"
Write-Host "Package: $expectedPackage  Version: $expectedVersionName"
Write-Host "ABI version codes: arm64-v8a=$($versionCodes['arm64-v8a']), armeabi-v7a=$($versionCodes['armeabi-v7a']), x86_64=$($versionCodes['x86_64'])"
if ($ReleaseId -gt 0) {
    Write-Host "Release APK attachments verified. Commit update.json and the three .sha1 files to the repository root."
} else {
    Write-Warning "Repository raw APK URLs are only for local diagnostics and are not anonymously downloadable on Gitee."
}
