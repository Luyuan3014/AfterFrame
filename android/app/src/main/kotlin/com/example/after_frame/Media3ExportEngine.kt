@file:androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)

package com.example.after_frame

import android.net.Uri
import android.os.Environment
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

/** Frame-accurate MP4 clipping powered by Jetpack Media3 Transformer. */
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
                            val output = packageLive(call, motion, work)
                            context.runOnUiThread { result.success(output.absolutePath) }
                        } catch (error: Exception) {
                            work.deleteRecursively()
                            context.runOnUiThread {
                                result.error("MEDIA_ENGINE_FAILED", error.message, null)
                            }
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

    private fun packageLive(call: MethodCall, motion: File, work: File): File {
        val startMs = call.argument<Number>("startMs")!!.toLong()
        val endMs = call.argument<Number>("endMs")!!.toLong()
        val coverMs = call.argument<Number>("coverMs")!!.toLong()
        val cover = File(call.argument<String>("coverPath")!!)
        val safeName = (call.argument<String>("name") ?: "memory")
            .substringBeforeLast('.')
            .replace(Regex("[^a-zA-Z0-9_\\-\\u4e00-\\u9fa5]"), "_")
            .take(40)
        val manifest = JSONObject().apply {
            put("format", "com.afterframe.live")
            put("version", 1)
            put("engine", "androidx.media3.transformer")
            put("createdAt", System.currentTimeMillis())
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
        val outputDirectory = File(
            context.getExternalFilesDir(Environment.DIRECTORY_MOVIES),
            "AfterFrame",
        ).apply { mkdirs() }
        val output = File(outputDirectory, "${safeName}_${System.currentTimeMillis()}.live")
        ZipOutputStream(FileOutputStream(output)).use { zip ->
            addBytes(zip, "manifest.json", manifest.toString(2).toByteArray(Charsets.UTF_8))
            addFile(zip, "cover.jpg", cover)
            addFile(zip, "motion.mp4", motion)
        }
        work.deleteRecursively()
        return output
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
