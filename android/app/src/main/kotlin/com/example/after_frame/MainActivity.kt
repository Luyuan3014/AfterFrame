package com.example.after_frame

import android.Manifest
import android.content.pm.PackageManager
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.util.Size
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val channelName = "com.afterframe/media_engine"
    private val permissionRequest = 4108
    private val executor = Executors.newSingleThreadExecutor()
    private var pendingPermission: MethodChannel.Result? = null
    private lateinit var renderEngine: Media3RenderEngine
    private lateinit var exportService: ExportService
    private lateinit var exportIndex: ExportIndex
    private lateinit var updateManager: AppUpdateManager

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        exportIndex = ExportIndex(this)
        renderEngine = Media3RenderEngine(this)
        exportService = ExportService(this, executor, renderEngine, exportIndex)
        updateManager = AppUpdateManager(applicationContext)
        updateManager.reconcileDownload()
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result -> handle(call, result) }
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "requestVideoAccess" -> requestVideoAccess(result)
            "listVideos" -> background(result) { listVideos() }
            "inspectVideo" -> background(result) { inspect(Uri.parse(call.argument<String>("uri")!!)) }
            "videoThumbnail" -> background(result) {
                thumbnail(Uri.parse(call.argument<String>("uri")!!))
            }
            "extractFrame" -> background(result) {
                extractFrame(
                    Uri.parse(call.argument<String>("uri")!!),
                    call.argument<Number>("timeMs")!!.toLong(),
                )
            }
            "listExports" -> background(result) { exportIndex.listAndReconcile() }
            "deleteExport" -> background(result) {
                exportIndex.delete(
                    liveUri = call.argument<String>("liveUri")!!,
                    coverPathHint = call.argument<String>("coverPath"),
                    displayNameHint = call.argument<String>("displayName"),
                )
                // MethodChannel's StandardMessageCodec cannot encode kotlin.Unit.
                // Always return null for void operations.
                null
            }
            "exportLive", "exportMotion" -> exportService.export(call, result)
            "shareMedia" -> {
                try {
                    exportService.share(
                        Uri.parse(call.argument<String>("uri")!!),
                        call.argument<String>("mimeType")!!,
                        call.argument<String>("title") ?: "分享 AfterFrame",
                    )
                    result.success(null)
                } catch (error: Exception) {
                    result.error("SHARE_FAILED", error.message, null)
                }
            }
            "getAppLanguage" -> result.success(
                getSharedPreferences("afterframe_settings", MODE_PRIVATE)
                    .getString("app_language", "zh"),
            )
            "setAppLanguage" -> {
                val language = call.argument<String>("language")
                if (language != "zh" && language != "en") {
                    result.error("INVALID_LANGUAGE", "Unsupported language", null)
                } else {
                    getSharedPreferences("afterframe_settings", MODE_PRIVATE)
                        .edit()
                        .putString("app_language", language)
                        .apply()
                    result.success(null)
                }
            }
            "getUpdateState" -> {
                updateManager.reconcileDownload()
                result.success(updateManager.currentState())
            }
            "checkForUpdate" -> background(result) {
                updateManager.check(call.argument<String>("manifestUrl")!!)
            }
            "startUpdateDownload" -> result.success(updateManager.startDownload())
            "installVerifiedUpdate" -> background(result) { updateManager.install() }
            else -> result.notImplemented()
        }
    }

    override fun onResume() {
        super.onResume()
        if (::updateManager.isInitialized) updateManager.resumePendingInstall()
    }

    private fun requestVideoAccess(result: MethodChannel.Result) {
        if (hasVideoAccess()) {
            result.success(true)
            return
        }
        if (pendingPermission != null) {
            result.error("PERMISSION_IN_PROGRESS", "正在请求视频访问权限", null)
            return
        }
        pendingPermission = result
        ActivityCompat.requestPermissions(this, videoPermissions(), permissionRequest)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != permissionRequest) return
        pendingPermission?.success(hasVideoAccess())
        pendingPermission = null
    }

    private fun videoPermissions(): Array<String> =
        AndroidMediaPolicy.videoPermissions(Build.VERSION.SDK_INT)

    private fun hasVideoAccess(): Boolean {
        if (Build.VERSION.SDK_INT >= 34 && ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED,
            ) == PackageManager.PERMISSION_GRANTED
        ) return true
        return videoPermissions().any {
            ContextCompat.checkSelfPermission(this, it) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun listVideos(): List<Map<String, Any>> {
        if (!hasVideoAccess()) throw SecurityException("需要视频访问权限才能显示媒体库")
        val collection = MediaStore.Video.Media.EXTERNAL_CONTENT_URI
        val projection = arrayOf(
            MediaStore.Video.Media._ID,
            MediaStore.Video.Media.DISPLAY_NAME,
            MediaStore.Video.Media.DURATION,
            MediaStore.Video.Media.WIDTH,
            MediaStore.Video.Media.HEIGHT,
            MediaStore.Video.Media.SIZE,
            MediaStore.Video.Media.DATE_ADDED,
        )
        val videos = mutableListOf<Map<String, Any>>()
        contentResolver.query(
            collection,
            projection,
            "${MediaStore.Video.Media.DURATION} > 0",
            null,
            "${MediaStore.Video.Media.DATE_ADDED} DESC",
        )?.use { cursor ->
            val idColumn = cursor.getColumnIndexOrThrow(MediaStore.Video.Media._ID)
            val nameColumn = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.DISPLAY_NAME)
            val durationColumn = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.DURATION)
            val widthColumn = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.WIDTH)
            val heightColumn = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.HEIGHT)
            val sizeColumn = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.SIZE)
            val dateColumn = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.DATE_ADDED)
            while (cursor.moveToNext()) {
                val uri = Uri.withAppendedPath(collection, cursor.getLong(idColumn).toString())
                videos += mapOf(
                    "uri" to uri.toString(),
                    "name" to cursor.getString(nameColumn),
                    "durationMs" to cursor.getLong(durationColumn),
                    "width" to cursor.getInt(widthColumn),
                    "height" to cursor.getInt(heightColumn),
                    "rotation" to 0,
                    "sizeBytes" to cursor.getLong(sizeColumn),
                    "dateAdded" to cursor.getLong(dateColumn),
                )
            }
        }
        return videos
    }

    private fun inspect(uri: Uri): Map<String, Any> {
        val name = runCatching {
            contentResolver.query(
                    uri,
                    arrayOf(MediaStore.MediaColumns.DISPLAY_NAME),
                    null,
                    null,
                    null,
                )?.use { if (it.moveToFirst()) it.getString(0) else null }
        }.getOrNull() ?: uri.lastPathSegment ?: "memory.mp4"
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(this, uri)
            val rotation = metadataLong(
                retriever,
                MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION,
            ).toInt()
            var width = metadataLong(
                retriever,
                MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH,
            ).toInt()
            var height = metadataLong(
                retriever,
                MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT,
            ).toInt()
            if (rotation == 90 || rotation == 270) {
                width = height.also { height = width }
            }
            mapOf(
                "uri" to uri.toString(),
                "name" to name,
                "durationMs" to metadataLong(
                    retriever,
                    MediaMetadataRetriever.METADATA_KEY_DURATION,
                ),
                "width" to width,
                "height" to height,
                "rotation" to rotation,
            )
        } finally {
            retriever.release()
        }
    }

    private fun thumbnail(uri: Uri): String {
        val directory = File(cacheDir, "afterframe/thumbnails").apply { mkdirs() }
        // Keep this above MediaEngine's in-memory path cache (96 entries). A
        // smaller disk cache leaves Flutter holding paths that were already
        // deleted and presents those tiles as black until the process restarts.
        pruneCache(directory, 160)
        val file = File(directory, "${uri.hashCode()}.jpg")
        if (file.exists() && file.length() > 0L) return file.absolutePath
        if (Build.VERSION.SDK_INT >= 29) {
            return saveBitmap(contentResolver.loadThumbnail(uri, Size(512, 512), null), file, 86)
        }
        return extractFrameNative(uri, 0, file, closest = false)
    }

    private fun extractFrame(uri: Uri, timeMs: Long): String {
        val directory = File(cacheDir, "afterframe/frames").apply { mkdirs() }
        pruneCache(directory, 128)
        val file = File(directory, "${uri.hashCode()}_$timeMs.jpg")
        if (file.exists() && file.length() > 0L) return file.absolutePath
        return extractFrameNative(uri, timeMs, file, closest = true)
    }

    private fun extractFrameNative(uri: Uri, timeMs: Long, file: File, closest: Boolean): String {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(this, uri)
            val option = if (closest) {
                MediaMetadataRetriever.OPTION_CLOSEST
            } else {
                MediaMetadataRetriever.OPTION_CLOSEST_SYNC
            }
            val bitmap = retriever.getFrameAtTime(timeMs * 1_000L, option)
                ?: throw IllegalStateException("Unable to decode the video frame at ${timeMs}ms")
            saveBitmap(bitmap, file, 92)
        } finally {
            retriever.release()
        }
    }

    private fun saveBitmap(bitmap: android.graphics.Bitmap, file: File, quality: Int): String {
        val pending = File(file.parentFile, ".${file.name}.${System.nanoTime()}.tmp")
        try {
            FileOutputStream(pending).use { output ->
                check(bitmap.compress(android.graphics.Bitmap.CompressFormat.JPEG, quality, output)) {
                    "Unable to encode the video frame"
                }
            }
            check(pending.length() > 0L && pending.renameTo(file)) {
                "Unable to save the video frame"
            }
            return file.absolutePath
        } finally {
            pending.delete()
            bitmap.recycle()
        }
    }

    private fun metadataLong(retriever: MediaMetadataRetriever, key: Int): Long =
        retriever.extractMetadata(key)?.toLongOrNull() ?: 0L

    private fun pruneCache(directory: File, limit: Int) {
        val files = directory.listFiles()?.filter(File::isFile)?.sortedBy(File::lastModified) ?: return
        files.take((files.size - limit).coerceAtLeast(0)).forEach(File::delete)
    }

    private fun background(result: MethodChannel.Result, operation: () -> Any?) {
        executor.execute {
            try {
                val value = operation()
                runOnUiThread { result.success(value) }
            } catch (error: Exception) {
                runOnUiThread {
                    result.error("MEDIA_ENGINE_FAILED", error.message ?: error.javaClass.simpleName, null)
                }
            }
        }
    }

    override fun onDestroy() {
        if (::exportService.isInitialized) exportService.cancel()
        if (::exportIndex.isInitialized) exportIndex.close()
        executor.shutdown()
        super.onDestroy()
    }
}
