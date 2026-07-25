package com.example.after_frame

import android.content.ContentValues
import android.content.Intent
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.core.content.FileProvider
import com.antonkarpenko.ffmpegkit.FFmpegKit
import com.antonkarpenko.ffmpegkit.FFmpegKitConfig
import com.antonkarpenko.ffmpegkit.FFprobeKit
import com.antonkarpenko.ffmpegkit.ReturnCode
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.Locale
import java.util.UUID
import java.util.concurrent.ExecutorService

/** FFmpeg/FFprobe processing plus Motion Photo publishing for the AfterFrame album. */
class FfmpegMediaEngine(
    private val context: MainActivity,
    private val executor: ExecutorService,
    private val exportIndex: ExportIndex,
) {
    @Volatile
    private var exportInProgress = false

    fun export(call: MethodCall, result: MethodChannel.Result) {
        synchronized(this) {
            if (exportInProgress) {
                result.error("EXPORT_IN_PROGRESS", "已有导出任务正在进行", null)
                return
            }
            exportInProgress = true
        }
        val work = File(context.cacheDir, "afterframe/export/${UUID.randomUUID()}").apply { mkdirs() }
        val motion = File(work, "motion.mp4")
        executor.execute {
            try {
                val hardwareSession = FFmpegKit.executeWithArguments(
                    buildExportArguments(call, motion, VideoEncoder.MEDIA_CODEC_H264).toTypedArray(),
                )
                var lastLogs = hardwareSession.allLogsAsString
                var validOutput = ReturnCode.isSuccess(hardwareSession.returnCode) &&
                    motion.length() > 0L && hasVideo(motion.absolutePath)
                if (!validOutput) {
                    check(exportInProgress) { "导出已取消" }
                    motion.delete()
                    val softwareSession = FFmpegKit.executeWithArguments(
                        buildExportArguments(call, motion, VideoEncoder.SOFTWARE_MPEG4).toTypedArray(),
                    )
                    lastLogs = softwareSession.allLogsAsString
                    validOutput = ReturnCode.isSuccess(softwareSession.returnCode) &&
                        motion.length() > 0L && hasVideo(motion.absolutePath)
                }
                check(validOutput) { "FFmpeg 导出失败：${lastLogs.takeLast(4_000)}" }
                /* Replaced by the validated hardware/software fallback above.
                check(ReturnCode.isSuccess(session.returnCode) && motion.length() > 0L) {
                    "FFmpeg 导出失败：${session.allLogsAsString.takeLast(4_000)}"
                }
                check(hasVideo(motion.absolutePath)) { "FFmpeg 输出不包含可解码的视频轨道" }
                */
                val output = packageAndPublish(call, motion, work)
                context.runOnUiThread { result.success(output) }
            } catch (error: Exception) {
                context.runOnUiThread {
                    result.error("FFMPEG_EXPORT_FAILED", error.message ?: error.javaClass.simpleName, null)
                }
            } finally {
                exportInProgress = false
                work.deleteRecursively()
            }
        }
    }

    fun cancel() {
        FFmpegKit.cancel()
        exportInProgress = false
    }

    fun inspect(uri: Uri, name: String): Map<String, Any> {
        return runCatching {
            val input = inputArgument(uri)
            val session = FFprobeKit.getMediaInformation(input)
            check(ReturnCode.isSuccess(session.returnCode)) {
                "FFprobe 无法解析视频：${session.allLogsAsString.takeLast(2_000)}"
            }
            val information = session.mediaInformation ?: error("FFprobe 没有返回媒体信息")
            val stream = information.streams.firstOrNull { it.type == "video" }
                ?: error("文件中没有视频轨道")
            val sideData = stream.allProperties.optJSONArray("side_data_list")
            var sideRotation = 0
            if (sideData != null) {
                for (index in 0 until sideData.length()) {
                    val value = sideData.getJSONObject(index).optInt("rotation", 0)
                    if (value != 0) sideRotation = value
                }
            }
            val rotation = normalizeRotation(
                stream.tags?.optString("rotate")?.toIntOrNull() ?: sideRotation,
            )
            var width = stream.width?.toInt() ?: 0
            var height = stream.height?.toInt() ?: 0
            if (rotation == 90 || rotation == 270) {
                width = height.also { height = width }
            }
            val durationSeconds = information.duration?.toDoubleOrNull() ?: 0.0
            mapOf(
                "uri" to uri.toString(),
                "name" to name,
                "durationMs" to (durationSeconds * 1_000.0).toLong(),
                "width" to width,
                "height" to height,
                "rotation" to rotation,
            )
        }.getOrElse {
            android.util.Log.w("FfmpegMediaEngine", "FFprobe inspect failed for $uri", it)
            mapOf(
                "uri" to uri.toString(),
                "name" to name,
                "durationMs" to 0L,
                "width" to 0,
                "height" to 0,
                "rotation" to 0,
            )
        }
    }

    fun extractFrame(uri: Uri, timeMs: Long, directory: File, cacheKey: String): String {
        directory.mkdirs()
        val file = File(directory, "$cacheKey.jpg")
        if (file.exists() && file.length() > 0L) return file.absolutePath
        val pending = File(directory, ".${file.name}.${System.nanoTime()}.tmp.jpg")
        val session = FFmpegKit.executeWithArguments(
            arrayOf(
                "-y", "-hide_banner", "-loglevel", "warning",
                "-i", inputArgument(uri),
                "-ss", seconds(timeMs),
                "-map", "0:v:0", "-frames:v", "1",
                "-vf", "scale=w='min(1080,iw)':h=-2:force_divisible_by=2",
                "-q:v", "2", pending.absolutePath,
            ),
        )
        try {
            check(ReturnCode.isSuccess(session.returnCode) && pending.length() > 0L) {
                "无法提取 ${timeMs}ms 画面：${session.allLogsAsString.takeLast(2_000)}"
            }
            check(pending.renameTo(file)) { "无法保存提取的画面" }
            return file.absolutePath
        } finally {
            pending.delete()
        }
    }

    private enum class VideoEncoder {
        MEDIA_CODEC_H264,
        SOFTWARE_MPEG4,
    }

    private fun buildExportArguments(
        call: MethodCall,
        destination: File,
        videoEncoder: VideoEncoder,
    ): List<String> {
        val defaultStart = call.argument<Number>("startMs")!!.toLong()
        val defaultEnd = call.argument<Number>("endMs")!!.toLong()
        require(defaultEnd > defaultStart) { "结束时间必须晚于开始时间" }
        val speed = (call.argument<Number>("playbackSpeed")?.toDouble() ?: 1.0)
            .coerceIn(0.5, 2.0)
        val enhancement = call.argument<Boolean>("enhancementEnabled") ?: false
        val collageValues = call.argument<List<String>>("collageUris").orEmpty().take(3)
        val uris = collageValues.ifEmpty { listOf(call.argument<String>("uri")!!) }.map(Uri::parse)
        val starts = call.argument<List<Number>>("collageStartMs").orEmpty()
        val ends = call.argument<List<Number>>("collageEndMs").orEmpty()
        val ranges = uris.indices.map { index ->
            val start = starts.getOrNull(index)?.toLong() ?: defaultStart
            val end = ends.getOrNull(index)?.toLong() ?: defaultEnd
            require(end > start) { "第 ${index + 1} 段素材的时间范围无效" }
            start to end
        }
        val durationMs = (ranges.minOf { it.second - it.first } / speed).toLong().coerceAtLeast(1L)
        val keepAudio = call.argument<Boolean>("keepAudio") ?: true
        val audioIndex = (call.argument<Number>("collageAudioSourceIndex")?.toInt() ?: 0)
            .coerceIn(0, uris.lastIndex)
        val audioEnabled = keepAudio && hasAudio(uris[audioIndex])
        val focusX = call.argument<List<Number>>("cropFocusX").orEmpty()
        val focusY = call.argument<List<Number>>("cropFocusY").orEmpty()

        val arguments = mutableListOf("-y", "-hide_banner", "-loglevel", "warning")
        uris.forEach { uri -> arguments += listOf("-i", inputArgument(uri)) }
        val filters = mutableListOf<String>()
        if (uris.size == 1) {
            val (start, end) = ranges.single()
            val effects = mutableListOf(
                "trim=start=${seconds(start)}:end=${seconds(end)}",
                "setpts=(PTS-STARTPTS)/${decimal(speed)}",
                "fps=30",
                "scale=w='min(1080,iw)':h=-2:force_divisible_by=2",
            )
            if (enhancement) effects += "eq=saturation=1.08:brightness=0.02"
            effects += "format=yuv420p"
            filters += "[0:v:0]${effects.joinToString(",")}[vout]"
        } else {
            val slots = collageSlots(uris.size, call.argument<Number>("collageLayout")?.toInt() ?: 0)
            slots.forEachIndexed { index, slot ->
                val (start, end) = ranges[index]
                val x = (focusX.getOrNull(index)?.toDouble() ?: 0.5).coerceIn(0.0, 1.0)
                val y = (focusY.getOrNull(index)?.toDouble() ?: 0.5).coerceIn(0.0, 1.0)
                val effects = mutableListOf(
                    "trim=start=${seconds(start)}:end=${seconds(end)}",
                    "setpts=(PTS-STARTPTS)/${decimal(speed)}",
                    "fps=30",
                    "scale=w=${slot.width}:h=${slot.height}:force_original_aspect_ratio=increase",
                    "crop=${slot.width}:${slot.height}:x='(iw-ow)*${decimal(x)}':y='(ih-oh)*${decimal(y)}'",
                )
                if (enhancement) effects += "eq=saturation=1.08:brightness=0.02"
                effects += "setsar=1"
                filters += "[$index:v:0]${effects.joinToString(",")}[v$index]"
            }
            val inputs = slots.indices.joinToString("") { "[v$it]" }
            val layout = slots.joinToString("|") { "${it.x}_${it.y}" }
            val transition = call.argument<Number>("motionTransition")?.toInt() ?: 0
            val finalEffects = mutableListOf<String>()
            when (transition) {
                1 -> {
                    val fadeOut = ((durationMs / 1_000.0) - 0.25).coerceAtLeast(0.0)
                    finalEffects += "fade=t=in:st=0:d=0.25"
                    finalEffects += "fade=t=out:st=${decimal(fadeOut)}:d=0.25"
                }
                2 -> finalEffects += "colorchannelmixer=rr=1.03:gg=0.99:bb=0.96"
                3 -> finalEffects += "gblur=sigma=1.2"
                4 -> finalEffects += "noise=alls=5:allf=t"
            }
            finalEffects += "format=yuv420p"
            filters += "$inputs" +
                "xstack=inputs=${slots.size}:layout=$layout:fill=black:shortest=1," +
                finalEffects.joinToString(",") + "[vout]"
        }
        if (audioEnabled) {
            val (start, end) = ranges[audioIndex]
            filters += "[$audioIndex:a:0]atrim=start=${seconds(start)}:end=${seconds(end)}," +
                "asetpts=PTS-STARTPTS,atempo=${decimal(speed)}[aout]"
        }

        arguments += listOf("-filter_complex", filters.joinToString(";"), "-map", "[vout]")
        if (audioEnabled) arguments += listOf("-map", "[aout]", "-c:a", "aac", "-b:a", "192k")
        arguments += when (videoEncoder) {
            VideoEncoder.MEDIA_CODEC_H264 -> listOf(
                "-c:v", "h264_mediacodec",
                "-b:v", "8M",
                "-maxrate", "12M",
                "-bufsize", "16M",
            )
            VideoEncoder.SOFTWARE_MPEG4 -> listOf(
                "-c:v", "mpeg4",
                "-q:v", "3",
            )
        }
        arguments += listOf(
            "-fps_mode", "cfr",
            "-t", seconds(durationMs),
            "-movflags", "+faststart",
            "-metadata:s:v:0", "rotate=0",
            destination.absolutePath,
        )
        return arguments
    }

    private fun hasAudio(uri: Uri): Boolean {
        val session = FFprobeKit.getMediaInformation(inputArgument(uri))
        return ReturnCode.isSuccess(session.returnCode) &&
            session.mediaInformation?.streams?.any { it.type == "audio" } == true
    }

    private fun hasVideo(path: String): Boolean {
        val session = FFprobeKit.getMediaInformation(path)
        return ReturnCode.isSuccess(session.returnCode) &&
            session.mediaInformation?.streams?.any { it.type == "video" } == true
    }

    private data class Slot(val x: Int, val y: Int, val width: Int, val height: Int)

    private fun collageSlots(count: Int, layout: Int): List<Slot> = when (layout) {
        0 -> {
            val widths = partition(1080, count)
            var x = 0
            widths.map { width -> Slot(x, 0, width, 1920).also { x += width } }
        }
        1, 3 -> {
            val heights = partition(1920, count)
            var y = 0
            heights.map { height -> Slot(0, y, 1080, height).also { y += height } }
        }
        else -> if (count == 2) {
            listOf(Slot(0, 0, 1080, 1280), Slot(0, 1280, 1080, 640))
        } else {
            listOf(
                Slot(0, 0, 1080, 1280),
                Slot(0, 1280, 540, 640),
                Slot(540, 1280, 540, 640),
            )
        }
    }

    private fun partition(total: Int, count: Int): List<Int> {
        val base = total / count
        return List(count) { index -> if (index == count - 1) total - base * index else base }
    }

    private fun inputArgument(uri: Uri): String = when (uri.scheme?.lowercase()) {
        "content" -> FFmpegKitConfig.getSafParameterForRead(context, uri)
        "file" -> requireNotNull(uri.path) { "文件 URI 缺少路径" }
        null, "" -> uri.toString()
        else -> uri.toString()
    }

    private fun normalizeRotation(value: Int): Int = ((value % 360) + 360) % 360

    private fun seconds(milliseconds: Long): String = decimal(milliseconds / 1_000.0)

    private fun decimal(value: Double): String = String.format(Locale.US, "%.6f", value)

    fun share(uri: Uri, mimeType: String, chooserTitle: String) {
        val sendIntent = Intent(Intent.ACTION_SEND).apply {
            type = mimeType
            putExtra(Intent.EXTRA_STREAM, uri)
            clipData = android.content.ClipData.newRawUri("AfterFrame", uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(Intent.createChooser(sendIntent, chooserTitle))
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
        // Motion Photo 1.0 is one JPEG: XMP metadata in an APP1 segment, followed
        // by the original JPEG data and an MP4 appended after the JPEG EOI marker.
        // The MP suffix is recommended by the Android specification and is used
        // by some gallery readers as an additional recognition signal.
        val motionPhoto = File(work, "${baseName}MP.jpg")
        val playbackSpeed = (call.argument<Number>("playbackSpeed")?.toDouble() ?: 1.0)
            .coerceIn(0.5, 2.0)
        val presentationUs = (
            (coverMs - startMs).coerceIn(0, endMs - startMs) / playbackSpeed * 1_000.0
            ).toLong()
        val loop = call.argument<Boolean>("loop") ?: false
        writeMotionPhoto(cover, motion, motionPhoto, presentationUs, loop)

        // Keep a private, share-ready MP4. It does not create a second visible
        // gallery item, but FileProvider lets WeChat, Douyin and other apps read it.
        val shareDirectory = File(context.filesDir, "afterframe/exports").apply { mkdirs() }
        val shareVideo = File(shareDirectory, "$baseName.mp4")
        motion.copyTo(shareVideo, overwrite = false)
        val coverDirectory = File(context.filesDir, "afterframe/covers").apply { mkdirs() }
        val persistentCover = File(coverDirectory, "$baseName.jpg")
        cover.copyTo(persistentCover, overwrite = false)

        val published = mutableListOf<Uri>()
        try {
            val motionPhotoUri = publishMedia(
                source = motionPhoto,
                displayName = motionPhoto.name,
                mimeType = "image/jpeg",
                collection = if (Build.VERSION.SDK_INT >= 29) {
                    MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                } else {
                    MediaStore.Images.Media.EXTERNAL_CONTENT_URI
                },
                publicDirectory = Environment.DIRECTORY_DCIM,
                relativeFolder = "AfterFrame",
            ).also(published::add)
            val shareVideoUri = FileProvider.getUriForFile(
                context,
                "${context.packageName}.fileprovider",
                shareVideo,
            ).also(published::add)
            val output = mapOf(
                "liveUri" to motionPhotoUri.toString(),
                "galleryUri" to shareVideoUri.toString(),
                "coverUri" to motionPhotoUri.toString(),
                "coverPath" to persistentCover.absolutePath,
                "displayName" to baseName,
                "albumName" to "AfterFrame",
                "createdAt" to stamp.toString(),
                "shareMimeType" to "video/mp4",
            )
            exportIndex.save(output)
            return output
        } catch (error: Exception) {
            published.asReversed().forEach(::removePublished)
            shareVideo.delete()
            persistentCover.delete()
            throw error
        }
    }

    private fun writeMotionPhoto(
        cover: File,
        motion: File,
        destination: File,
        presentationTimestampUs: Long,
        loop: Boolean,
    ) {
        val jpeg = cover.readBytes()
        require(jpeg.size >= 2 && jpeg[0] == 0xFF.toByte() && jpeg[1] == 0xD8.toByte()) {
            "封面不是有效的 JPEG 文件"
        }
        val videoLength = motion.length()
        val xmp = """
            <x:xmpmeta xmlns:x="adobe:ns:meta/">
              <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
                <rdf:Description rdf:about=""
                  xmlns:Camera="http://ns.google.com/photos/1.0/camera/"
                  xmlns:Container="http://ns.google.com/photos/1.0/container/"
                  xmlns:Item="http://ns.google.com/photos/1.0/container/item/"
                  xmlns:AfterFrame="https://afterframe.app/ns/1.0/"
                  Camera:MotionPhoto="1"
                  Camera:MotionPhotoVersion="1"
                  Camera:MotionPhotoPresentationTimestampUs="$presentationTimestampUs"
                  AfterFrame:Loop="$loop">
                  <Container:Directory>
                    <rdf:Seq>
                      <rdf:li rdf:parseType="Resource">
                        <Container:Item Item:Mime="image/jpeg" Item:Semantic="Primary"/>
                      </rdf:li>
                      <rdf:li rdf:parseType="Resource">
                        <Container:Item Item:Mime="video/mp4" Item:Semantic="MotionPhoto" Item:Length="$videoLength"/>
                      </rdf:li>
                    </rdf:Seq>
                  </Container:Directory>
                </rdf:Description>
              </rdf:RDF>
            </x:xmpmeta>
        """.trimIndent().toByteArray(Charsets.UTF_8)
        val xmpHeader = "http://ns.adobe.com/xap/1.0/\u0000".toByteArray(Charsets.US_ASCII)
        val payloadLength = xmpHeader.size + xmp.size
        require(payloadLength + 2 <= 0xFFFF) { "Motion Photo XMP 元数据过大" }
        val app1Length = ByteBuffer.allocate(2)
            .order(ByteOrder.BIG_ENDIAN)
            .putShort((payloadLength + 2).toShort())
            .array()
        val insertionOffset = jpegMetadataEnd(jpeg)

        FileOutputStream(destination).use { output ->
            output.write(jpeg, 0, insertionOffset)
            output.write(byteArrayOf(0xFF.toByte(), 0xE1.toByte()))
            output.write(app1Length)
            output.write(xmpHeader)
            output.write(xmp)
            output.write(jpeg, insertionOffset, jpeg.size - insertionOffset)
            FileInputStream(motion).use { it.copyTo(output) }
        }
    }

    /** Keeps JFIF/Exif APP segments immediately after SOI and inserts XMP after them. */
    private fun jpegMetadataEnd(jpeg: ByteArray): Int {
        var offset = 2
        while (offset + 4 <= jpeg.size && jpeg[offset] == 0xFF.toByte()) {
            val marker = jpeg[offset + 1].toInt() and 0xFF
            if (marker !in 0xE0..0xEF) break
            val segmentLength = ((jpeg[offset + 2].toInt() and 0xFF) shl 8) or
                (jpeg[offset + 3].toInt() and 0xFF)
            if (segmentLength < 2 || offset + 2 + segmentLength > jpeg.size) break
            offset += 2 + segmentLength
        }
        return offset
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

}
