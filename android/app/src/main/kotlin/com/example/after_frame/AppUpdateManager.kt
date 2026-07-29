package com.example.after_frame

import android.app.DownloadManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import androidx.core.app.NotificationCompat
import androidx.core.content.FileProvider
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.File
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL
import java.security.MessageDigest
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.zip.ZipFile

internal class AppUpdateManager(private val context: Context) {
    private val preferences = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private val downloadManager = context.getSystemService(DownloadManager::class.java)
    private val verifier = Executors.newSingleThreadExecutor()
    private val verificationScheduled = AtomicBoolean(false)

    fun currentState(): Map<String, Any?> {
        var status = preferences.getString(KEY_STATUS, STATUS_IDLE) ?: STATUS_IDLE
        val remoteCode = preferences.getLong(KEY_VERSION_CODE, 0L)
        if (remoteCode > 0L && status in ACTIVE_UPDATE_STATES &&
            !UpdatePolicy.isUpgrade(versionCode(currentPackage()), remoteCode)
        ) {
            preferences.getString(KEY_LOCAL_PATH, null)?.let { File(it).delete() }
            preferences.edit().clear().putString(KEY_STATUS, STATUS_NO_UPDATE).apply()
            status = STATUS_NO_UPDATE
        }
        val state = mutableMapOf<String, Any?>(
            "status" to status,
            "currentVersionName" to currentPackage().versionName.orEmpty(),
            "currentVersionCode" to versionCode(currentPackage()),
            "abi" to installedAbi(),
            "versionName" to preferences.getString(KEY_VERSION_NAME, null),
            "versionCode" to preferences.getLong(KEY_VERSION_CODE, 0L),
            "notes" to preferences.getString(KEY_NOTES, null),
            "errorCode" to preferences.getString(KEY_ERROR_CODE, null),
            "errorDetail" to preferences.getString(KEY_ERROR_DETAIL, null),
        )
        val downloadId = preferences.getLong(KEY_DOWNLOAD_ID, -1L)
        if (status == STATUS_DOWNLOADING && downloadId >= 0) {
            downloadManager.query(DownloadManager.Query().setFilterById(downloadId))?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val downloaded = cursor.getLong(
                        cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR),
                    )
                    val total = cursor.getLong(
                        cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES),
                    )
                    state["downloadedBytes"] = downloaded.coerceAtLeast(0L)
                    state["totalBytes"] = total.coerceAtLeast(0L)
                }
            }
        }
        return state
    }

    fun check(manifestUrl: String): Map<String, Any?> {
        UpdatePolicy.requireTrustedGiteeUrl(manifestUrl)
        val manifest = JSONObject(UpdatePolicy.normalizeMetadata(readHttps(manifestUrl, MAX_MANIFEST_BYTES)))
        require(manifest.getInt("schemaVersion") == 1) { "Unsupported update manifest" }
        require(manifest.getString("packageName") == context.packageName) {
            "Update manifest package does not match this app"
        }
        val current = currentPackage()
        val currentCode = versionCode(current)
        val remoteName = manifest.getString("versionName").trim()
        require(remoteName.isNotEmpty()) { "Invalid remote version" }
        val abi = installedAbi()
        val asset = manifest.getJSONObject("assets").optJSONObject(abi)
            ?: throw IllegalStateException("No update APK for installed ABI $abi")
        // Flutter split APKs intentionally use ABI-specific Android version
        // codes (for example 1007/2007/4007). Compare only the code read from
        // the asset for the ABI that is actually installed.
        val remoteCode = asset.getLong("versionCode")
        require(remoteCode > 0) { "Invalid APK version code" }
        if (!UpdatePolicy.isUpgrade(currentCode, remoteCode)) {
            preferences.edit().clear().putString(KEY_STATUS, STATUS_NO_UPDATE).apply()
            return currentState()
        }
        val apkUrl = asset.getString("apkUrl")
        val sha1Url = asset.getString("sha1Url")
        val fileName = asset.optString("fileName", Uri.parse(apkUrl).lastPathSegment.orEmpty())
        require(fileName == "app-$abi-release.apk") {
            "Manifest APK filename does not match installed ABI"
        }
        UpdatePolicy.requireTrustedGiteeUrl(apkUrl)
        UpdatePolicy.requireTrustedGiteeUrl(sha1Url)
        val expectedSha1 = UpdatePolicy.parseSha1(
            readHttps(sha1Url, MAX_SHA1_BYTES),
            fileName,
        )
        preferences.edit()
            .clear()
            .putString(KEY_STATUS, STATUS_AVAILABLE)
            .putString(KEY_MANIFEST_URL, manifestUrl)
            .putString(KEY_VERSION_NAME, remoteName)
            .putLong(KEY_VERSION_CODE, remoteCode)
            .putString(KEY_NOTES, manifest.optString("notes", ""))
            .putString(KEY_ABI, abi)
            .putString(KEY_APK_URL, apkUrl)
            .putString(KEY_FILE_NAME, fileName)
            .putString(KEY_SHA1, expectedSha1)
            .putLong(KEY_SIZE, asset.optLong("size", -1L))
            .apply()
        return currentState()
    }

    fun startDownload(): Map<String, Any?> {
        require(preferences.getString(KEY_STATUS, null) == STATUS_AVAILABLE) {
            "No verified update is available"
        }
        val remoteCode = preferences.getLong(KEY_VERSION_CODE, 0L)
        require(UpdatePolicy.isUpgrade(versionCode(currentPackage()), remoteCode)) {
            "The selected update is no longer newer than the installed app"
        }
        val abi = installedAbi()
        require(abi == preferences.getString(KEY_ABI, null)) { "Installed ABI changed" }
        val apkUrl = preferences.getString(KEY_APK_URL, null) ?: error("Missing APK URL")
        UpdatePolicy.requireTrustedGiteeUrl(apkUrl)
        val updates = File(
            context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS),
            "updates",
        ).apply { mkdirs() }
        val destination = File(updates, "afterframe-$remoteCode-$abi.apk")
        if (destination.exists()) destination.delete()
        val request = DownloadManager.Request(Uri.parse(apkUrl))
            .setTitle("AfterFrame ${preferences.getString(KEY_VERSION_NAME, "")}")
            .setDescription("正在后台下载安全更新")
            .setMimeType(APK_MIME)
            .setAllowedOverMetered(true)
            .setAllowedOverRoaming(false)
            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE)
            .setDestinationUri(Uri.fromFile(destination))
        val id = downloadManager.enqueue(request)
        preferences.edit()
            .putString(KEY_STATUS, STATUS_DOWNLOADING)
            .putLong(KEY_DOWNLOAD_ID, id)
            .putString(KEY_LOCAL_PATH, destination.absolutePath)
            .remove(KEY_ERROR_CODE)
            .apply()
        return currentState()
    }

    fun handleDownloadComplete(downloadId: Long) {
        if (downloadId != preferences.getLong(KEY_DOWNLOAD_ID, -1L)) return
        val downloadStatus = downloadStatus(downloadId)
        if (downloadStatus == DownloadManager.STATUS_RUNNING ||
            downloadStatus == DownloadManager.STATUS_PENDING ||
            downloadStatus == DownloadManager.STATUS_PAUSED
        ) {
            return
        }
        if (downloadStatus != DownloadManager.STATUS_SUCCESSFUL) {
            fail("DOWNLOAD_FAILED")
            return
        }
        syncLocalPathFromDownloadManager(downloadId)
        preferences.edit().putString(KEY_STATUS, STATUS_VERIFYING).apply()
        runCatching { verifyDownloadedApk() }
            .onSuccess {
                preferences.edit()
                    .putString(KEY_STATUS, STATUS_READY)
                    .remove(KEY_ERROR_CODE)
                    .remove(KEY_ERROR_DETAIL)
                    .apply()
                showReadyNotification()
            }
            .onFailure { fail("VERIFY_FAILED", it) }
    }

    fun reconcileDownload() {
        val status = preferences.getString(KEY_STATUS, null)
        if (status == STATUS_VERIFYING) {
            scheduleVerification(preferences.getLong(KEY_DOWNLOAD_ID, -1L))
            return
        }
        if (status != STATUS_DOWNLOADING) return
        val id = preferences.getLong(KEY_DOWNLOAD_ID, -1L)
        if (id < 0) return
        when (downloadStatus(id)) {
            DownloadManager.STATUS_SUCCESSFUL -> scheduleVerification(id)
            DownloadManager.STATUS_FAILED -> fail("DOWNLOAD_FAILED")
        }
    }

    private fun scheduleVerification(downloadId: Long) {
        if (downloadId < 0L || !verificationScheduled.compareAndSet(false, true)) return
        verifier.execute {
            try {
                handleDownloadComplete(downloadId)
            } finally {
                verificationScheduled.set(false)
            }
        }
    }

    fun install(): Map<String, Any?> {
        verifyDownloadedApk()
        preferences.edit().putString(KEY_STATUS, STATUS_READY).apply()
        if (Build.VERSION.SDK_INT >= 26 && !context.packageManager.canRequestPackageInstalls()) {
            preferences.edit().putBoolean(KEY_PENDING_INSTALL, true).apply()
            val intent = Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:${context.packageName}"),
            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
            return mapOf("status" to "permission_required")
        }
        preferences.edit().putBoolean(KEY_PENDING_INSTALL, false).apply()
        launchInstaller()
        return mapOf("status" to "installer_opened")
    }

    fun resumePendingInstall() {
        if (!preferences.getBoolean(KEY_PENDING_INSTALL, false)) return
        if (Build.VERSION.SDK_INT >= 26 && !context.packageManager.canRequestPackageInstalls()) return
        // Launch failures must not flip the update into STATUS_ERROR: Android
        // 14–16 often block one-shot installer starts, and the verified APK is
        // still good for a manual retry.
        runCatching {
            verifyDownloadedApk()
            preferences.edit()
                .putString(KEY_STATUS, STATUS_READY)
                .putBoolean(KEY_PENDING_INSTALL, false)
                .apply()
            launchInstaller()
        }
    }

    private fun verifyDownloadedApk() {
        val downloadId = preferences.getLong(KEY_DOWNLOAD_ID, -1L)
        if (downloadId >= 0L) syncLocalPathFromDownloadManager(downloadId)
        val file = File(preferences.getString(KEY_LOCAL_PATH, null) ?: error("Missing update APK"))
        require(file.isFile && file.length() > 0L) { "Downloaded APK is missing" }
        val expectedSize = preferences.getLong(KEY_SIZE, -1L)
        require(expectedSize <= 0L || file.length() == expectedSize) {
            "APK size mismatch: expected $expectedSize, got ${file.length()}"
        }
        val expectedSha1 = preferences.getString(KEY_SHA1, null) ?: error("Missing SHA-1")
        require(digest(file, "SHA-1") == expectedSha1) { "APK SHA-1 mismatch" }

        val archive = packageArchive(file) ?: error("Downloaded file is not a valid APK")
        require(archive.packageName == context.packageName) { "APK package name mismatch" }
        val expectedCode = preferences.getLong(KEY_VERSION_CODE, 0L)
        require(versionCode(archive) == expectedCode) { "APK version differs from manifest" }
        require(UpdatePolicy.isUpgrade(versionCode(currentPackage()), versionCode(archive))) {
            "APK would not upgrade the currently installed version"
        }
        require(archive.versionName == preferences.getString(KEY_VERSION_NAME, null)) {
            "APK version name differs from manifest"
        }
        val expectedAbi = preferences.getString(KEY_ABI, null) ?: error("Missing ABI")
        require(expectedAbi == installedAbi()) { "Installed ABI changed" }
        require(apkAbis(file) == setOf(expectedAbi)) { "APK contains the wrong ABI" }
        require(signatures(archive, file) == signatures(currentPackage())) {
            "APK signing certificate does not match the installed app"
        }
    }

    private fun downloadStatus(downloadId: Long): Int? =
        downloadManager.query(DownloadManager.Query().setFilterById(downloadId))?.use { cursor ->
            if (!cursor.moveToFirst()) return null
            cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))
        }

    private fun syncLocalPathFromDownloadManager(downloadId: Long) {
        if (downloadId < 0L) return
        downloadManager.query(DownloadManager.Query().setFilterById(downloadId))?.use { cursor ->
            if (!cursor.moveToFirst()) return
            val localUri = cursor.getString(
                cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_LOCAL_URI),
            ) ?: return
            val path = Uri.parse(localUri).path ?: return
            val file = File(path)
            if (file.isFile) {
                preferences.edit().putString(KEY_LOCAL_PATH, file.absolutePath).apply()
            }
        }
    }

    private fun launchInstaller() {
        val file = File(preferences.getString(KEY_LOCAL_PATH, null) ?: error("Missing update APK"))
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
        val intent = Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, APK_MIME)
            .addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP,
            )
        // Explicit grants remain necessary on some Android 14–16 builds even
        // with FLAG_GRANT_READ_URI_PERMISSION on the intent.
        val installers = context.packageManager.queryIntentActivities(
            intent,
            PackageManager.MATCH_DEFAULT_ONLY,
        )
        for (resolve in installers) {
            context.grantUriPermission(
                resolve.activityInfo.packageName,
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION,
            )
        }
        context.startActivity(intent)
    }

    private fun installedAbi(): String {
        val info = context.applicationInfo
        val packaged = sequenceOf(info.sourceDir)
            .plus(info.splitSourceDirs?.asSequence() ?: emptySequence())
            .map(::File)
            .filter(File::isFile)
            .flatMap { apkAbis(it).asSequence() }
            .toSet()
        val runtimeAbi = when (File(info.nativeLibraryDir.orEmpty()).name) {
            "arm64", "arm64-v8a" -> "arm64-v8a"
            "arm", "armeabi-v7a" -> "armeabi-v7a"
            "x86_64" -> "x86_64"
            else -> ""
        }
        if (runtimeAbi in packaged) return UpdatePolicy.requireSupportedAbi(runtimeAbi)
        val selected = Build.SUPPORTED_ABIS.firstOrNull { it in packaged }
            ?: throw IllegalStateException("Cannot determine installed APK ABI")
        return UpdatePolicy.requireSupportedAbi(selected)
    }

    private fun apkAbis(file: File): Set<String> = ZipFile(file).use { zip ->
        zip.entries().asSequence().mapNotNull { entry ->
            Regex("^lib/([^/]+)/libapp\\.so$").matchEntire(entry.name)?.groupValues?.get(1)
        }.filter { it in UpdatePolicy.supportedAbis }.toSet()
    }

    private fun currentPackage(): PackageInfo =
        if (Build.VERSION.SDK_INT >= 33) {
            context.packageManager.getPackageInfo(
                context.packageName,
                PackageManager.PackageInfoFlags.of(packageFlags().toLong()),
            )
        } else {
            @Suppress("DEPRECATION")
            context.packageManager.getPackageInfo(context.packageName, packageFlags())
        }

    @Suppress("DEPRECATION")
    private fun packageArchive(file: File): PackageInfo? {
        // API 33+ prefers PackageInfoFlags, but several Android 13–16 builds
        // return empty signing fields for that overload on uninstalled APKs.
        // Always try the legacy int overload too and keep the richer result.
        val flags = packageFlags()
        val viaFlags = if (Build.VERSION.SDK_INT >= 33) {
            context.packageManager.getPackageArchiveInfo(
                file.absolutePath,
                PackageManager.PackageInfoFlags.of(flags.toLong()),
            )
        } else {
            null
        }
        val viaInt = context.packageManager.getPackageArchiveInfo(file.absolutePath, flags)
        val info = selectRicherPackageInfo(viaFlags, viaInt)
        // Some platform builds leave these null for archive parses; later
        // PackageManager calls may need an explicit on-disk path.
        info?.applicationInfo?.let { applicationInfo ->
            applicationInfo.sourceDir = file.absolutePath
            applicationInfo.publicSourceDir = file.absolutePath
        }
        return info
    }

    @Suppress("DEPRECATION")
    private fun selectRicherPackageInfo(first: PackageInfo?, second: PackageInfo?): PackageInfo? {
        fun score(info: PackageInfo?): Int {
            if (info == null) return -1
            var value = 0
            if (Build.VERSION.SDK_INT >= 28 && !info.signingInfo?.apkContentsSigners.isNullOrEmpty()) {
                value += 2
            }
            if (!info.signatures.isNullOrEmpty()) value += 1
            return value
        }
        return if (score(first) >= score(second)) first else second
    }

    @Suppress("DEPRECATION")
    private fun packageFlags(): Int {
        // getPackageArchiveInfo often leaves signingInfo null on API 28–29
        // (and some OEM builds) when only GET_SIGNING_CERTIFICATES is set.
        // Always request the legacy GET_SIGNATURES flag as a fallback source.
        var flags = PackageManager.GET_SIGNATURES
        if (Build.VERSION.SDK_INT >= 28) {
            flags = flags or PackageManager.GET_SIGNING_CERTIFICATES
        }
        return flags
    }

    @Suppress("DEPRECATION")
    private fun versionCode(info: PackageInfo): Long =
        if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()

    @Suppress("DEPRECATION")
    private fun signatures(info: PackageInfo, archiveFile: File? = null): Set<String> {
        val fromSigningInfo = if (Build.VERSION.SDK_INT >= 28) {
            info.signingInfo?.apkContentsSigners?.map { it.toByteArray() }.orEmpty()
        } else {
            emptyList()
        }
        val certificates = fromSigningInfo.ifEmpty {
            info.signatures?.map { it.toByteArray() }.orEmpty()
        }
        if (certificates.isNotEmpty()) {
            return certificates.map { bytes ->
                MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
            }.toSet()
        }
        // v2/v3-only APKs frequently yield empty PackageManager signing fields
        // for archives on Android 16; read the APK Signing Block directly.
        val fromApk = archiveFile?.let(ApkSigningCerts::sha256Digests).orEmpty()
        require(fromApk.isNotEmpty()) { "APK has no signing certificate" }
        return fromApk
    }

    private fun digest(file: File, algorithm: String): String {
        val digest = MessageDigest.getInstance(algorithm)
        file.inputStream().buffered().use { input ->
            val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    private fun readHttps(source: String, maxBytes: Int): String {
        var current = source
        repeat(MAX_REDIRECTS + 1) {
            UpdatePolicy.requireTrustedGiteeUrl(current)
            val connection = URL(current).openConnection() as HttpURLConnection
            connection.instanceFollowRedirects = false
            connection.connectTimeout = 12_000
            connection.readTimeout = 12_000
            connection.setRequestProperty("Accept", "application/json,text/plain,*/*")
            connection.setRequestProperty("User-Agent", "AfterFrame-Android-Updater/1")
            try {
                val code = connection.responseCode
                if (code in 300..399) {
                    current = URI(current).resolve(connection.getHeaderField("Location") ?: error("Invalid redirect")).toString()
                    return@repeat
                }
                require(code in 200..299) { "Gitee returned HTTP $code" }
                connection.inputStream.buffered().use { input ->
                    val output = ByteArrayOutputStream()
                    val buffer = ByteArray(4096)
                    while (output.size() <= maxBytes) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        output.write(buffer, 0, count)
                    }
                    require(output.size() <= maxBytes) { "Remote metadata is too large" }
                    return output.toString(Charsets.UTF_8.name())
                }
            } finally {
                connection.disconnect()
            }
        }
        error("Too many redirects")
    }

    private fun fail(code: String, error: Throwable? = null) {
        preferences.edit()
            .putString(KEY_STATUS, STATUS_ERROR)
            .putString(KEY_ERROR_CODE, code)
            .putString(KEY_ERROR_DETAIL, error?.message)
            .apply()
        preferences.getString(KEY_LOCAL_PATH, null)?.let { File(it).delete() }
    }

    private fun showReadyNotification() {
        val manager = context.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "应用更新", NotificationManager.IMPORTANCE_HIGH),
            )
        }
        preferences.edit().putBoolean(KEY_PENDING_INSTALL, true).apply()
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            ?.putExtra(EXTRA_RESUME_INSTALL, true)
        val pending = PendingIntent.getActivity(
            context,
            0,
            launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        manager.notify(
            NOTIFICATION_ID,
            NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(context.applicationInfo.icon)
                .setContentTitle("AfterFrame 更新已就绪")
                .setContentText("校验通过，点按通知继续安装")
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setAutoCancel(true)
                .setContentIntent(pending)
                .build(),
        )
    }

    companion object {
        private const val PREFS = "afterframe_update"
        private const val KEY_STATUS = "status"
        private const val KEY_MANIFEST_URL = "manifest_url"
        private const val KEY_VERSION_NAME = "version_name"
        private const val KEY_VERSION_CODE = "version_code"
        private const val KEY_NOTES = "notes"
        private const val KEY_ABI = "abi"
        private const val KEY_APK_URL = "apk_url"
        private const val KEY_FILE_NAME = "file_name"
        private const val KEY_SHA1 = "sha1"
        private const val KEY_SIZE = "size"
        private const val KEY_DOWNLOAD_ID = "download_id"
        private const val KEY_LOCAL_PATH = "local_path"
        private const val KEY_ERROR_CODE = "error_code"
        private const val KEY_ERROR_DETAIL = "error_detail"
        private const val KEY_PENDING_INSTALL = "pending_install"
        private const val STATUS_IDLE = "idle"
        private const val STATUS_NO_UPDATE = "no_update"
        private const val STATUS_AVAILABLE = "available"
        private const val STATUS_DOWNLOADING = "downloading"
        private const val STATUS_VERIFYING = "verifying"
        private const val STATUS_READY = "ready"
        private const val STATUS_ERROR = "error"
        private const val APK_MIME = "application/vnd.android.package-archive"
        private const val CHANNEL_ID = "afterframe_updates"
        private const val NOTIFICATION_ID = 4607
        private const val MAX_MANIFEST_BYTES = 64 * 1024
        private const val MAX_SHA1_BYTES = 1024
        private const val MAX_REDIRECTS = 4
        const val EXTRA_RESUME_INSTALL = "afterframe_resume_install"
        private val ACTIVE_UPDATE_STATES = setOf(
            STATUS_AVAILABLE,
            STATUS_DOWNLOADING,
            STATUS_VERIFYING,
            STATUS_READY,
        )
    }
}
