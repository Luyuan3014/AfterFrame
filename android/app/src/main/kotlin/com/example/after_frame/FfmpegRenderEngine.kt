package com.example.after_frame

import android.net.Uri
import android.content.Context
import com.antonkarpenko.ffmpegkit.FFmpegKit
import com.antonkarpenko.ffmpegkit.FFmpegKitConfig
import com.antonkarpenko.ffmpegkit.FFprobeKit
import com.antonkarpenko.ffmpegkit.ReturnCode
import io.flutter.plugin.common.MethodCall
import java.io.File
import java.util.Locale

/** Pure creation engine: FFmpeg renders bytes; it never previews or publishes media. */
class FfmpegRenderEngine(
    private val context: Context,
) {
    @Volatile
    private var cancelled = false

    fun render(call: MethodCall, work: File): File {
        cancelled = false
        val motion = File(work, "motion.mp4")
        val hardwareSession = FFmpegKit.executeWithArguments(
            buildExportArguments(call, motion, VideoEncoder.MEDIA_CODEC_H264).toTypedArray(),
        )
        var lastLogs = hardwareSession.allLogsAsString
        var validOutput = ReturnCode.isSuccess(hardwareSession.returnCode) &&
            motion.length() > 0L && hasVideo(motion.absolutePath)
        if (!validOutput) {
            check(!cancelled) { "导出已取消" }
            motion.delete()
            val softwareSession = FFmpegKit.executeWithArguments(
                buildExportArguments(call, motion, VideoEncoder.SOFTWARE_MPEG4).toTypedArray(),
            )
            lastLogs = softwareSession.allLogsAsString
            validOutput = ReturnCode.isSuccess(softwareSession.returnCode) &&
                motion.length() > 0L && hasVideo(motion.absolutePath)
        }
        check(validOutput) { "FFmpeg 导出失败：${lastLogs.takeLast(4_000)}" }
        return motion
    }

    fun cancel() {
        cancelled = true
        FFmpegKit.cancel()
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

    fun renderAnimated(input: File, format: String, destination: File) {
        val arguments = when (format) {
            "gif" -> arrayOf(
                "-y", "-hide_banner", "-loglevel", "warning", "-i", input.absolutePath,
                "-vf", "fps=15,scale='min(720,iw)':-2:flags=lanczos,split[a][b];[a]palettegen=max_colors=192[p];[b][p]paletteuse=dither=sierra2_4a",
                "-loop", "0", destination.absolutePath,
            )
            "webp" -> arrayOf(
                "-y", "-hide_banner", "-loglevel", "warning", "-i", input.absolutePath,
                "-an", "-vf", "fps=20,scale='min(1080,iw)':-2:flags=lanczos",
                "-c:v", "libwebp_anim", "-quality", "82", "-loop", "0", destination.absolutePath,
            )
            else -> error("不支持的动画格式：$format")
        }
        val session = FFmpegKit.executeWithArguments(arguments)
        check(ReturnCode.isSuccess(session.returnCode) && destination.length() > 0L) {
            "FFmpeg $format 导出失败：${session.allLogsAsString.takeLast(4_000)}"
        }
    }

}
