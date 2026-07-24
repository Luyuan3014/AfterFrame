package com.example.after_frame

import android.app.Activity
import android.content.Intent
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaMuxer
import android.net.Uri
import android.os.Environment
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.util.UUID
import java.util.concurrent.Executors
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

class MainActivity : FlutterActivity() {
    private val channelName = "com.afterframe/media_engine"
    private val pickVideoRequest = 4107
    private val executor = Executors.newSingleThreadExecutor()
    private var pendingPick: MethodChannel.Result? = null

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != pickVideoRequest) return
        val result = pendingPick
        pendingPick = null
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            result?.success(null)
            return
        }
        val uri = data.data!!
        try {
            contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        } catch (_: SecurityException) {
            // Some gallery providers only grant access for the current process.
        }
        executor.execute {
            try {
                val metadata = inspect(uri)
                runOnUiThread { result?.success(metadata) }
            } catch (error: Exception) {
                runOnUiThread { result?.error("VIDEO_READ_FAILED", error.message, null) }
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result -> handle(call, result) }
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickVideo" -> pickVideo(result)
            "extractFrame" -> background(result) {
                val uri = Uri.parse(call.argument<String>("uri")!!)
                val timeMs = call.argument<Number>("timeMs")!!.toLong()
                extractFrame(uri, timeMs)
            }
            "exportLive" -> background(result) { exportLive(call) }
            else -> result.notImplemented()
        }
    }

    private fun pickVideo(result: MethodChannel.Result) {
        if (pendingPick != null) {
            result.error("PICK_IN_PROGRESS", "已有一个视频选择窗口", null)
            return
        }
        pendingPick = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "video/*"
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }
        startActivityForResult(intent, pickVideoRequest)
    }

    private fun inspect(uri: Uri): Map<String, Any> {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(this, uri)
            mapOf(
                "uri" to uri.toString(),
                "name" to displayName(uri),
                "durationMs" to metadataLong(retriever, MediaMetadataRetriever.METADATA_KEY_DURATION),
                "width" to metadataLong(retriever, MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH).toInt(),
                "height" to metadataLong(retriever, MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT).toInt(),
                "rotation" to metadataLong(retriever, MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION).toInt(),
            )
        } finally {
            retriever.release()
        }
    }

    private fun metadataLong(retriever: MediaMetadataRetriever, key: Int): Long =
        retriever.extractMetadata(key)?.toLongOrNull() ?: 0L

    private fun displayName(uri: Uri): String {
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) return cursor.getString(0)
        }
        return "memory.mp4"
    }

    private fun extractFrame(uri: Uri, timeMs: Long): String {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(this, uri)
            val bitmap = retriever.getFrameAtTime(timeMs * 1000, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                ?: throw IllegalStateException("无法提取 $timeMs ms 的画面")
            val directory = File(cacheDir, "afterframe/frames").apply { mkdirs() }
            val file = File(directory, "${uri.toString().hashCode()}_${timeMs}.jpg")
            FileOutputStream(file).use { bitmap.compress(android.graphics.Bitmap.CompressFormat.JPEG, 90, it) }
            bitmap.recycle()
            file.absolutePath
        } finally {
            retriever.release()
        }
    }

    private fun exportLive(call: MethodCall): String {
        val uri = Uri.parse(call.argument<String>("uri")!!)
        val startMs = call.argument<Number>("startMs")!!.toLong()
        val endMs = call.argument<Number>("endMs")!!.toLong()
        val coverMs = call.argument<Number>("coverMs")!!.toLong()
        val keepAudio = call.argument<Boolean>("keepAudio") ?: true
        val loop = call.argument<Boolean>("loop") ?: false
        val cover = File(call.argument<String>("coverPath")!!)
        val safeName = (call.argument<String>("name") ?: "memory")
            .substringBeforeLast('.').replace(Regex("[^a-zA-Z0-9_\\-\\u4e00-\\u9fa5]"), "_")
            .take(40)
        val work = File(cacheDir, "afterframe/export/${UUID.randomUUID()}").apply { mkdirs() }
        val motion = File(work, "motion.mp4")
        trim(uri, motion, startMs * 1000, endMs * 1000, keepAudio)

        val manifest = JSONObject().apply {
            put("format", "com.afterframe.live")
            put("version", 1)
            put("createdAt", System.currentTimeMillis())
            put("sourceName", call.argument<String>("name"))
            put("durationMs", endMs - startMs)
            put("coverTimeMs", coverMs - startMs)
            put("keepAudio", keepAudio)
            put("loop", loop)
            put("width", call.argument<Number>("width")?.toInt() ?: 0)
            put("height", call.argument<Number>("height")?.toInt() ?: 0)
            put("cover", "cover.jpg")
            put("motion", "motion.mp4")
        }
        val outputDirectory = File(getExternalFilesDir(Environment.DIRECTORY_MOVIES), "AfterFrame").apply { mkdirs() }
        val output = File(outputDirectory, "${safeName}_${System.currentTimeMillis()}.live")
        ZipOutputStream(FileOutputStream(output)).use { zip ->
            addBytes(zip, "manifest.json", manifest.toString(2).toByteArray(Charsets.UTF_8))
            addFile(zip, "cover.jpg", cover)
            addFile(zip, "motion.mp4", motion)
        }
        work.deleteRecursively()
        return output.absolutePath
    }

    private fun trim(uri: Uri, output: File, startUs: Long, endUs: Long, keepAudio: Boolean) {
        val extractor = MediaExtractor()
        val descriptor = contentResolver.openAssetFileDescriptor(uri, "r")
            ?: throw IllegalStateException("无法打开视频")
        descriptor.use { afd ->
            extractor.setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
            val muxer = MediaMuxer(output.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            val trackMap = mutableMapOf<Int, Int>()
            try {
                for (index in 0 until extractor.trackCount) {
                    val format = extractor.getTrackFormat(index)
                    val mime = format.getString(MediaFormat.KEY_MIME) ?: continue
                    if (mime.startsWith("video/") || (keepAudio && mime.startsWith("audio/"))) {
                        extractor.selectTrack(index)
                        trackMap[index] = muxer.addTrack(format)
                    }
                }
                if (trackMap.isEmpty()) throw IllegalStateException("视频中没有可用轨道")
                readRotation(uri)?.let { muxer.setOrientationHint(it) }
                muxer.start()
                extractor.seekTo(startUs, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
                val buffer = ByteBuffer.allocate(4 * 1024 * 1024)
                val info = MediaCodec.BufferInfo()
                var firstSampleUs = -1L
                while (true) {
                    val sampleTime = extractor.sampleTime
                    if (sampleTime < 0 || sampleTime > endUs) break
                    val inputTrack = extractor.sampleTrackIndex
                    val outputTrack = trackMap[inputTrack]
                    if (outputTrack != null) {
                        buffer.clear()
                        val size = extractor.readSampleData(buffer, 0)
                        if (size < 0) break
                        if (firstSampleUs < 0) firstSampleUs = sampleTime
                        info.set(0, size, sampleTime - firstSampleUs, extractor.sampleFlags)
                        muxer.writeSampleData(outputTrack, buffer, info)
                    }
                    if (!extractor.advance()) break
                }
            } finally {
                try { muxer.stop() } catch (_: Exception) { }
                muxer.release()
                extractor.release()
            }
        }
    }

    private fun readRotation(uri: Uri): Int? {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(this, uri)
            retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull()
        } finally { retriever.release() }
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

    private fun background(result: MethodChannel.Result, operation: () -> Any) {
        executor.execute {
            try {
                val value = operation()
                runOnUiThread { result.success(value) }
            } catch (error: Exception) {
                runOnUiThread { result.error("MEDIA_ENGINE_FAILED", error.message ?: error.javaClass.simpleName, null) }
            }
        }
    }

    override fun onDestroy() {
        executor.shutdown()
        super.onDestroy()
    }
}
