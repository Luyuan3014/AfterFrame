@file:androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)

package com.example.after_frame

import android.content.ContentValues
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.media3.common.MediaItem
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.Transformer
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.util.UUID
import java.util.concurrent.ExecutorService
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

/** Frame-accurate export plus MediaStore publishing for the AfterFrame album. */
class Media3ExportEngine(
    private val context: MainActivity,
    private val executor: ExecutorService,
) {
    private var transformer: Transformer? = null

    fun export(call: MethodCall, result: MethodChannel.Result) {
        if (transformer != null) {
            result.error("EXPORT_IN_PROGRESS", "已有导出任务正在进行", null)
            return
        }
        val uri = Uri.parse(call.argument<String>("uri")!!)
        val startMs = call.argument<Number>("startMs")!!.toLong()
        val endMs = call.argument<Number>("endMs")!!.toLong()
        val keepAudio = call.argument<Boolean>("keepAudio") ?: true
        val work = File(context.cacheDir, "afterframe/export/${UUID.randomUUID()}").apply { mkdirs() }
        val motion = File(work, "motion.mp4")
        val mediaItem = MediaItem.Builder()
            .setUri(uri)
            .setClippingConfiguration(
                MediaItem.ClippingConfiguration.Builder()
                    .setStartPositionMs(startMs)
                    .setEndPositionMs(endMs)
                    .build(),
            )
            .build()
        val editedItem = EditedMediaItem.Builder(mediaItem)
            .setRemoveAudio(!keepAudio)
            .build()

        transformer = Transformer.Builder(context)
            .experimentalSetTrimOptimizationEnabled(true)
            .addListener(object : Transformer.Listener {
                override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                    transformer = null
                    executor.execute {
                        try {
                            val output = packageAndPublish(call, motion, work)
                            context.runOnUiThread { result.success(output) }
                        } catch (error: Exception) {
                            context.runOnUiThread {
                                result.error("MEDIA_ENGINE_FAILED", error.message, null)
                            }
                        } finally {
                            work.deleteRecursively()
                        }
                    }
                }

                override fun onError(
                    composition: Composition,
                    exportResult: ExportResult,
                    exportException: ExportException,
                ) {
                    transformer = null
                    work.deleteRecursively()
                    context.runOnUiThread {
                        result.error("MEDIA3_EXPORT_FAILED", exportException.message, null)
                    }
                }
            })
            .build()
        transformer!!.start(editedItem, motion.absolutePath)
    }

    fun cancel() {
        transformer?.cancel()
        transformer = null
    }

    private fun packageAndPublish(
        call: MethodCall,
        motion: File,
        work: File,
    ): Map<String, String> {
        val startMs = call.argument<Number>("startMs")!!.toLong()
        val endMs = call.argument<Number>("endMs")!!.toLong()
        val coverMs = call.argument<Number>("coverMs")!!.toLong()
        val cover = File(call.argument<String>("coverPath")!!)
        val safeName = (call.argument<String>("name") ?: "memory")
            .substringBeforeLast('.')
            .replace(Regex("[^a-zA-Z0-9_\\-\\u4e00-\\u9fa5]"), "_")
            .take(40)
        val stamp = System.currentTimeMillis()
        val baseName = "${safeName}_$stamp"
        val live = File(work, "$baseName.live")
        val manifest = JSONObject().apply {
            put("format", "com.afterframe.live")
            put("version", 1)
            put("engine", "androidx.media3.transformer")
            put("createdAt", stamp)
            put("sourceName", call.argument<String>("name"))
            put("durationMs", endMs - startMs)
            put("coverTimeMs", coverMs - startMs)
            put("keepAudio", call.argument<Boolean>("keepAudio") ?: true)
            put("loop", call.argument<Boolean>("loop") ?: false)
            put("width", call.argument<Number>("width")?.toInt() ?: 0)
            put("height", call.argument<Number>("height")?.toInt() ?: 0)
            put("cover", "cover.jpg")
            put("motion", "motion.mp4")
        }
        ZipOutputStream(FileOutputStream(live)).use { zip ->
            addBytes(zip, "manifest.json", manifest.toString(2).toByteArray(Charsets.UTF_8))
            addFile(zip, "cover.jpg", cover)
            addFile(zip, "motion.mp4", motion)
        }

        val published = mutableListOf<Uri>()
        try {
            val videoUri = publishMedia(
                source = motion,
                displayName = "$baseName.mp4",
                mimeType = "video/mp4",
                collection = if (Build.VERSION.SDK_INT >= 29) {
                    MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                } else {
                    MediaStore.Video.Media.EXTERNAL_CONTENT_URI
                },
                publicDirectory = Environment.DIRECTORY_DCIM,
                relativeFolder = "AfterFrame",
            ).also(published::add)
            val coverUri = publishMedia(
                source = cover,
                displayName = "$baseName.jpg",
                mimeType = "image/jpeg",
                collection = if (Build.VERSION.SDK_INT >= 29) {
                    MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                } else {
                    MediaStore.Images.Media.EXTERNAL_CONTENT_URI
                },
                publicDirectory = Environment.DIRECTORY_DCIM,
                relativeFolder = "AfterFrame",
            ).also(published::add)
            val liveUri = publishMedia(
                source = live,
                displayName = live.name,
                mimeType = "application/vnd.afterframe.live",
                collection = if (Build.VERSION.SDK_INT >= 29) {
                    MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                } else {
                    MediaStore.Files.getContentUri("external")
                },
                publicDirectory = Environment.DIRECTORY_DOWNLOADS,
                relativeFolder = "AfterFrame",
            ).also(published::add)
            return mapOf(
                "liveUri" to liveUri.toString(),
                "galleryUri" to videoUri.toString(),
                "coverUri" to coverUri.toString(),
                "displayName" to baseName,
                "albumName" to "AfterFrame",
            )
        } catch (error: Exception) {
            published.asReversed().forEach(::removePublished)
            throw error
        }
    }

    private fun publishMedia(
        source: File,
        displayName: String,
        mimeType: String,
        collection: Uri,
        publicDirectory: String,
        relativeFolder: String,
    ): Uri {
        if (Build.VERSION.SDK_INT < 29) {
            @Suppress("DEPRECATION")
            val directory = File(
                Environment.getExternalStoragePublicDirectory(publicDirectory),
                relativeFolder,
            ).apply { mkdirs() }
            val destination = File(directory, displayName)
            source.copyTo(destination, overwrite = false)
            MediaScannerConnection.scanFile(
                context,
                arrayOf(destination.absolutePath),
                arrayOf(mimeType),
                null,
            )
            return Uri.fromFile(destination)
        }

        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, displayName)
            put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
            put(MediaStore.MediaColumns.RELATIVE_PATH, "$publicDirectory/$relativeFolder")
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = context.contentResolver.insert(collection, values)
            ?: throw IllegalStateException("无法创建系统相册项目")
        try {
            context.contentResolver.openOutputStream(uri, "w")?.use { output ->
                FileInputStream(source).use { input -> input.copyTo(output) }
            } ?: throw IllegalStateException("无法写入系统相册")
            context.contentResolver.update(
                uri,
                ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) },
                null,
                null,
            )
            return uri
        } catch (error: Exception) {
            context.contentResolver.delete(uri, null, null)
            throw error
        }
    }

    private fun removePublished(uri: Uri) {
        runCatching {
            if (uri.scheme == "file") File(uri.path!!).delete()
            else context.contentResolver.delete(uri, null, null)
        }
    }

    private fun addFile(zip: ZipOutputStream, name: String, file: File) {
        zip.putNextEntry(ZipEntry(name))
        FileInputStream(file).use { it.copyTo(zip) }
        zip.closeEntry()
    }

    private fun addBytes(zip: ZipOutputStream, name: String, data: ByteArray) {
        zip.putNextEntry(ZipEntry(name))
        zip.write(data)
        zip.closeEntry()
    }
}
