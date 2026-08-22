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
    private lateinit var temporaryCache: TemporaryCacheManager

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        exportIndex = ExportIndex(this)
        renderEngine = Media3RenderEngine(this)
        exportService = ExportService(this, executor, renderEngine, exportIndex)
        updateManager = AppUpdateManager(applicationContext)
        temporaryCache = TemporaryCacheManager(cacheDir)
        updateManager.reconcileDownload()
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result -> handle(call, result) }
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "requestVideoAccess" -> requestVideoAccess(result)
            "listVideos" -> background(result) { listLibrary() }
            "inspectVideo" -> background(result) { inspect(Uri.parse(call.argument<String>("uri")!!)) }
            "resolvePlayableSource" -> background(result) {
                resolvePlayable(Uri.parse(call.argument<String>("uri")!!))
            }
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
            "getTemporaryCacheUsage" -> background(result) { temporaryCache.usage() }
            "clearTemporaryCache" -> background(result) {
                temporaryCache.clear()
                null
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

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.getBooleanExtra(AppUpdateManager.EXTRA_RESUME_INSTALL, false) &&
            ::updateManager.isInitialized
        ) {
            updateManager.resumePendingInstall()
        }
    }

    private fun requestVideoAccess(result: MethodChannel.Result) {
        if (hasVideoAccess()) {
            result.success(true)
            return
        }
        if (pendingPermission != null) {
            result.error("PERMISSION_IN_PROGRESS", "正在请求媒体访问权限", null)
            return
        }
        pendingPermission = result
        ActivityCompat.requestPermissions(this, libraryPermissions(), permissionRequest)
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

    private fun libraryPermissions(): Array<String> =
        AndroidMediaPolicy.libraryPermissions(Build.VERSION.SDK_INT)

    private fun hasVideoAccess(): Boolean {
        if (Build.VERSION.SDK_INT >= 34 && ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED,
            ) == PackageManager.PERMISSION_GRANTED
        ) return true
        return libraryPermissions().any {
            ContextCompat.checkSelfPermission(this, it) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun listLibrary(): List<Map<String, Any>> {
        if (!hasVideoAccess()) throw SecurityException("需要媒体访问权限才能显示素材库")
        val items = mutableListOf<Map<String, Any>>()
        items += listVideos()
        items += listMotionPhotos()
        return items.sortedByDescending { (it["dateAdded"] as? Number)?.toLong() ?: 0L }
    }

    private fun listVideos(): List<Map<String, Any>> {
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
                videos += libraryItem(
                    uri = uri,
                    name = cursor.getString(nameColumn) ?: "memory.mp4",
                    durationMs = cursor.getLong(durationColumn),
                    width = cursor.getInt(widthColumn),
                    height = cursor.getInt(heightColumn),
                    rotation = 0,
                    sizeBytes = cursor.getLong(sizeColumn),
                    dateAdded = cursor.getLong(dateColumn),
                    kind = "video",
                )
            }
        }
        return videos
    }

    private fun listMotionPhotos(): List<Map<String, Any>> {
        return runCatching { queryMotionPhotos(includeMotionColumn = Build.VERSION.SDK_INT >= 34) }
            .getOrElse { queryMotionPhotos(includeMotionColumn = false) }
    }

    private fun queryMotionPhotos(includeMotionColumn: Boolean): List<Map<String, Any>> {
        val collection = MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        val projection = mutableListOf(
            MediaStore.Images.Media._ID,
            MediaStore.Images.Media.DISPLAY_NAME,
            MediaStore.Images.Media.WIDTH,
            MediaStore.Images.Media.HEIGHT,
            MediaStore.Images.Media.SIZE,
            MediaStore.Images.Media.DATE_ADDED,
            MediaStore.Images.Media.MIME_TYPE,
            MediaStore.Images.Media.ORIENTATION,
        )
        if (includeMotionColumn) {
            projection += IS_MOTION_PHOTO_COLUMN
        }
        val photos = mutableListOf<Map<String, Any>>()
        var peeks = 0
        contentResolver.query(
            collection,
            projection.toTypedArray(),
            null,
            null,
            "${MediaStore.Images.Media.DATE_ADDED} DESC",
        )?.use { cursor ->
            val idColumn = cursor.getColumnIndexOrThrow(MediaStore.Images.Media._ID)
            val nameColumn = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.DISPLAY_NAME)
            val widthColumn = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.WIDTH)
            val heightColumn = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.HEIGHT)
            val sizeColumn = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.SIZE)
            val dateColumn = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.DATE_ADDED)
            val mimeColumn = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.MIME_TYPE)
            val orientationColumn = cursor.getColumnIndex(MediaStore.Images.Media.ORIENTATION)
            val motionColumn = if (includeMotionColumn) {
                cursor.getColumnIndex(IS_MOTION_PHOTO_COLUMN)
            } else {
                -1
            }
            while (cursor.moveToNext()) {
                val name = cursor.getString(nameColumn) ?: continue
                val mime = cursor.getString(mimeColumn) ?: "image/jpeg"
                val flagged = motionColumn >= 0 && !cursor.isNull(motionColumn) &&
                    cursor.getInt(motionColumn) == 1
                val named = MotionPhotoSource.looksLikeMotionName(name)
                val candidateMime = mime.startsWith("image/")
                if (!candidateMime) continue
                val uri = Uri.withAppendedPath(collection, cursor.getLong(idColumn).toString())
                val confirmed = when {
                    flagged || named -> true
                    peeks >= MAX_MOTION_PEEKS -> false
                    else -> {
                        peeks += 1
                        peekMotionPhoto(uri)
                    }
                }
                if (!confirmed) continue
                photos += libraryItem(
                    uri = uri,
                    name = name,
                    durationMs = 0,
                    width = cursor.getInt(widthColumn),
                    height = cursor.getInt(heightColumn),
                    rotation = if (orientationColumn >= 0) cursor.getInt(orientationColumn) else 0,
                    sizeBytes = cursor.getLong(sizeColumn),
                    dateAdded = cursor.getLong(dateColumn),
                    kind = "motionPhoto",
                    stillUri = uri.toString(),
                    libraryUri = uri.toString(),
                )
            }
        }
        return photos
    }

    private fun peekMotionPhoto(uri: Uri): Boolean {
        return runCatching {
            contentResolver.openInputStream(uri)?.use { input ->
                val header = ByteArray(65_536)
                val read = input.read(header)
                if (read <= 0) return false
                MotionPhotoSource.headerSuggestsMotion(header.copyOf(read))
            } ?: false
        }.getOrDefault(false)
    }

    private fun libraryItem(
        uri: Uri,
        name: String,
        durationMs: Long,
        width: Int,
        height: Int,
        rotation: Int,
        sizeBytes: Long,
        dateAdded: Long,
        kind: String,
        stillUri: String? = null,
        libraryUri: String = uri.toString(),
    ): Map<String, Any> {
        val values = mutableMapOf<String, Any>(
            "uri" to uri.toString(),
            "name" to name,
            "durationMs" to durationMs,
            "width" to width,
            "height" to height,
            "rotation" to rotation,
            "sizeBytes" to sizeBytes,
            "dateAdded" to dateAdded,
            "kind" to kind,
            "libraryUri" to libraryUri,
        )
        if (stillUri != null) values["stillUri"] = stillUri
        return values
    }

    private fun resolvePlayable(uri: Uri): Map<String, Any> {
        if (isImageUri(uri)) {
            val extracted = MotionPhotoSource.extract(this, uri, cacheDir)
            val playable = Uri.fromFile(extracted)
            val meta = inspectMedia(playable)
            val name = displayName(uri) ?: meta["name"] as String
            return meta + mapOf(
                "uri" to playable.toString(),
                "name" to name,
                "kind" to "motionPhoto",
                "libraryUri" to uri.toString(),
                "stillUri" to uri.toString(),
            )
        }
        return inspectMedia(uri) + mapOf(
            "kind" to "video",
            "libraryUri" to uri.toString(),
        )
    }

    private fun inspect(uri: Uri): Map<String, Any> {
        if (isImageUri(uri)) return resolvePlayable(uri)
        return inspectMedia(uri) + mapOf(
            "kind" to if (uri.scheme == "file") "motionPhoto" else "video",
            "libraryUri" to uri.toString(),
        )
    }

    private fun inspectMedia(uri: Uri): Map<String, Any> {
        val name = displayName(uri) ?: uri.lastPathSegment ?: "memory.mp4"
        val retriever = MediaMetadataRetriever()
        return try {
            if (uri.scheme == "file") {
                retriever.setDataSource(uri.path)
            } else {
                retriever.setDataSource(this, uri)
            }
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
            // Keep encoded width/height. Flutter orients with [rotation] once;
            // swapping here and again in Dart would invert portrait Live clips.
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
        if (isImageUri(uri) && Build.VERSION.SDK_INT >= 29) {
            return saveBitmap(contentResolver.loadThumbnail(uri, Size(512, 512), null), file, 86)
        }
        if (Build.VERSION.SDK_INT >= 29 && uri.scheme != "file") {
            return saveBitmap(contentResolver.loadThumbnail(uri, Size(512, 512), null), file, 86)
        }
        val playable = playableUri(uri)
        return extractFrameNative(playable, 0, file, closest = false)
    }

    private fun extractFrame(uri: Uri, timeMs: Long): String {
        val directory = File(cacheDir, "afterframe/frames").apply { mkdirs() }
        pruneCache(directory, 128)
        val file = File(directory, "${uri.hashCode()}_$timeMs.jpg")
        if (file.exists() && file.length() > 0L) return file.absolutePath
        return extractFrameNative(playableUri(uri), timeMs, file, closest = true)
    }

    private fun playableUri(uri: Uri): Uri {
        if (!isImageUri(uri)) return uri
        return Uri.fromFile(MotionPhotoSource.extract(this, uri, cacheDir))
    }

    private fun isImageUri(uri: Uri): Boolean {
        if (uri.scheme == "file") {
            val path = uri.path.orEmpty().lowercase()
            return path.endsWith(".jpg") || path.endsWith(".jpeg") ||
                path.endsWith(".heic") || path.endsWith(".heif")
        }
        val mime = contentResolver.getType(uri) ?: return uri.toString().contains("/images/")
        return mime.startsWith("image/")
    }

    private fun displayName(uri: Uri): String? = runCatching {
        contentResolver.query(
            uri,
            arrayOf(MediaStore.MediaColumns.DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { if (it.moveToFirst()) it.getString(0) else null }
    }.getOrNull()

    private fun extractFrameNative(uri: Uri, timeMs: Long, file: File, closest: Boolean): String {
        val retriever = MediaMetadataRetriever()
        return try {
            if (uri.scheme == "file") {
                retriever.setDataSource(uri.path)
            } else {
                retriever.setDataSource(this, uri)
            }
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

    private companion object {
        const val MAX_MOTION_PEEKS = 250
        const val IS_MOTION_PHOTO_COLUMN = "is_motion_photo"
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
