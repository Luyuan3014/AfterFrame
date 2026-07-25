package com.example.after_frame

import android.content.Context
import android.media.MediaExtractor
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.media3.common.C
import androidx.media3.common.Effect
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.OverlaySettings
import androidx.media3.common.VideoCompositorSettings
import androidx.media3.common.util.Size
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.Crop
import androidx.media3.effect.GaussianBlur
import androidx.media3.effect.HslAdjustment
import androidx.media3.effect.Presentation
import androidx.media3.effect.RgbAdjustment
import androidx.media3.effect.StaticOverlaySettings
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.Transformer
import io.flutter.plugin.common.MethodCall
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import kotlin.math.abs

/** Media3-only creation engine. It renders MP4 bytes but never publishes media. */
@UnstableApi
class Media3RenderEngine(
    private val context: Context,
) {
    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var activeTransformer: Transformer? = null

    @Volatile
    private var cancelled = false

    fun render(call: MethodCall, work: File): File {
        cancelled = false
        val request = RenderRequest.from(call)
        val destination = File(work, "motion.mp4")
        val completed = CountDownLatch(1)
        val failure = AtomicReference<Throwable?>()

        mainHandler.post {
            try {
                check(!cancelled) { "导出已取消" }
                val transformer = Transformer.Builder(context)
                    .setVideoMimeType(MimeTypes.VIDEO_H264)
                    .setAudioMimeType(MimeTypes.AUDIO_AAC)
                    .experimentalSetTrimOptimizationEnabled(request.canOptimizeTrim)
                    .addListener(
                        object : Transformer.Listener {
                            override fun onCompleted(composition: Composition, result: ExportResult) {
                                activeTransformer = null
                                completed.countDown()
                            }

                            override fun onError(
                                composition: Composition,
                                result: ExportResult,
                                exception: ExportException,
                            ) {
                                activeTransformer = null
                                failure.set(exception)
                                completed.countDown()
                            }
                        },
                    )
                    .build()
                activeTransformer = transformer
                transformer.start(buildComposition(request), destination.absolutePath)
            } catch (error: Throwable) {
                activeTransformer = null
                failure.set(error)
                completed.countDown()
            }
        }

        check(completed.await(10, TimeUnit.MINUTES)) {
            cancel()
            "Media3 导出超时"
        }
        failure.get()?.let { throw IllegalStateException("Media3 导出失败：${it.message}", it) }
        check(!cancelled) { "导出已取消" }
        check(destination.isFile && destination.length() > 0L && hasVideo(destination)) {
            "Media3 没有生成有效的 MP4 视频"
        }
        return destination
    }

    fun cancel() {
        cancelled = true
        mainHandler.post {
            activeTransformer?.cancel()
            activeTransformer = null
        }
    }

    private fun buildComposition(request: RenderRequest): Composition {
        if (request.sources.size == 1) {
            val source = request.sources.single()
            val item = editedItem(
                source = source,
                request = request,
                removeAudio = !request.keepAudio,
                removeVideo = false,
                slot = null,
            )
            val sequence = if (request.keepAudio && hasAudio(source.uri)) {
                EditedMediaItemSequence.withAudioAndVideoFrom(listOf(item))
            } else {
                EditedMediaItemSequence.withVideoFrom(listOf(item))
            }
            return Composition.Builder(sequence).build()
        }

        val slots = collageSlots(request.sources.size, request.layout)
        val sequences = request.sources.mapIndexed { index, source ->
            EditedMediaItemSequence.withVideoFrom(
                listOf(
                    editedItem(
                        source = source,
                        request = request,
                        removeAudio = true,
                        removeVideo = false,
                        slot = slots[index],
                    ),
                ),
            )
        }.toMutableList()

        val audioSource = request.sources[request.audioSourceIndex]
        if (request.keepAudio && hasAudio(audioSource.uri)) {
            sequences += EditedMediaItemSequence.withAudioFrom(
                listOf(
                    editedItem(
                        source = audioSource,
                        request = request,
                        removeAudio = false,
                        removeVideo = true,
                        slot = null,
                    ),
                ),
            )
        }

        return Composition.Builder(sequences)
            .setVideoCompositorSettings(CollageCompositor(slots))
            .build()
    }

    private fun editedItem(
        source: Source,
        request: RenderRequest,
        removeAudio: Boolean,
        removeVideo: Boolean,
        slot: Slot?,
    ): EditedMediaItem {
        val mediaItem = MediaItem.Builder()
            .setUri(source.uri)
            .setClippingConfiguration(
                MediaItem.ClippingConfiguration.Builder()
                    .setStartPositionMs(source.startMs)
                    .setEndPositionMs(source.endMs)
                    .build(),
            )
            .build()
        val builder = EditedMediaItem.Builder(mediaItem)
            .setRemoveAudio(removeAudio)
            .setRemoveVideo(removeVideo)
            .setFrameRate(30)
        if (request.speed != 1f) builder.setSpeed(ConstantSpeedProvider(request.speed))
        if (!removeVideo) {
            builder.setEffects(Effects(emptyList(), videoEffects(source, request, slot)))
        }
        return builder.build()
    }

    private fun videoEffects(source: Source, request: RenderRequest, slot: Slot?): List<Effect> {
        val effects = mutableListOf<Effect>()
        if (slot != null) {
            cropForSlot(source, slot)?.let(effects::add)
            effects += Presentation.createForWidthAndHeight(
                slot.width,
                slot.height,
                Presentation.LAYOUT_STRETCH_TO_FIT,
            )
        } else {
            effects += Presentation.createForShortSide(1080)
        }
        if (request.enhancement) {
            effects += HslAdjustment.Builder()
                .adjustSaturation(8f)
                .adjustLightness(2f)
                .build()
        }
        when (request.transition) {
            2 -> effects += RgbAdjustment.Builder()
                .setRedScale(1.03f)
                .setGreenScale(.99f)
                .setBlueScale(.96f)
                .build()
            3 -> effects += GaussianBlur(1.2f)
        }
        return effects
    }

    private fun cropForSlot(source: Source, slot: Slot): Crop? {
        val size = mediaSize(source.uri)
        if (size.width <= 0 || size.height <= 0) return null
        val sourceAspect = size.width.toFloat() / size.height
        val targetAspect = slot.width.toFloat() / slot.height
        if (abs(sourceAspect - targetAspect) < .001f) return null
        return if (sourceAspect > targetAspect) {
            val visible = (targetAspect / sourceAspect).coerceIn(.01f, 1f)
            val width = visible * 2f
            val desiredLeft = source.focusX * 2f - 1f - width / 2f
            val left = desiredLeft.coerceIn(-1f, 1f - width)
            Crop(left, left + width, -1f, 1f)
        } else {
            val visible = (sourceAspect / targetAspect).coerceIn(.01f, 1f)
            val height = visible * 2f
            val center = 1f - source.focusY * 2f
            val bottom = (center - height / 2f).coerceIn(-1f, 1f - height)
            Crop(-1f, 1f, bottom, bottom + height)
        }
    }

    private fun mediaSize(uri: Uri): Size {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(context, uri)
            var width = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
                ?.toIntOrNull() ?: 0
            var height = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
                ?.toIntOrNull() ?: 0
            val rotation = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
                ?.toIntOrNull() ?: 0
            if (rotation == 90 || rotation == 270) width = height.also { height = width }
            Size(width, height)
        } finally {
            retriever.release()
        }
    }

    private fun hasAudio(uri: Uri): Boolean {
        val extractor = MediaExtractor()
        return try {
            extractor.setDataSource(context, uri, null)
            (0 until extractor.trackCount).any { index ->
                extractor.getTrackFormat(index).getString(android.media.MediaFormat.KEY_MIME)
                    ?.startsWith("audio/") == true
            }
        } catch (_: Exception) {
            false
        } finally {
            extractor.release()
        }
    }

    private fun hasVideo(file: File): Boolean {
        val extractor = MediaExtractor()
        return try {
            extractor.setDataSource(file.absolutePath)
            (0 until extractor.trackCount).any { index ->
                extractor.getTrackFormat(index).getString(android.media.MediaFormat.KEY_MIME)
                    ?.startsWith("video/") == true
            }
        } catch (_: Exception) {
            false
        } finally {
            extractor.release()
        }
    }

    private data class Source(
        val uri: Uri,
        val startMs: Long,
        val endMs: Long,
        val focusX: Float,
        val focusY: Float,
    )

    private data class Slot(val x: Int, val y: Int, val width: Int, val height: Int)

    private data class RenderRequest(
        val sources: List<Source>,
        val speed: Float,
        val keepAudio: Boolean,
        val enhancement: Boolean,
        val layout: Int,
        val audioSourceIndex: Int,
        val transition: Int,
    ) {
        val canOptimizeTrim: Boolean
            get() = sources.size == 1 && speed == 1f && !enhancement && transition == 0

        companion object {
            fun from(call: MethodCall): RenderRequest {
                val defaultStart = call.argument<Number>("startMs")!!.toLong()
                val defaultEnd = call.argument<Number>("endMs")!!.toLong()
                require(defaultEnd > defaultStart) { "结束时间必须晚于开始时间" }
                val collage = call.argument<List<String>>("collageUris").orEmpty().take(3)
                val uris = collage.ifEmpty { listOf(call.argument<String>("uri")!!) }.map(Uri::parse)
                val starts = call.argument<List<Number>>("collageStartMs").orEmpty()
                val ends = call.argument<List<Number>>("collageEndMs").orEmpty()
                val focusX = call.argument<List<Number>>("cropFocusX").orEmpty()
                val focusY = call.argument<List<Number>>("cropFocusY").orEmpty()
                val sources = uris.mapIndexed { index, uri ->
                    val start = starts.getOrNull(index)?.toLong() ?: defaultStart
                    val end = ends.getOrNull(index)?.toLong() ?: defaultEnd
                    require(end > start) { "第 ${index + 1} 段素材的时间范围无效" }
                    Source(
                        uri = uri,
                        startMs = start,
                        endMs = end,
                        focusX = (focusX.getOrNull(index)?.toFloat() ?: .5f).coerceIn(0f, 1f),
                        focusY = (focusY.getOrNull(index)?.toFloat() ?: .5f).coerceIn(0f, 1f),
                    )
                }
                return RenderRequest(
                    sources = sources,
                    speed = (call.argument<Number>("playbackSpeed")?.toFloat() ?: 1f)
                        .coerceIn(.5f, 2f),
                    keepAudio = call.argument<Boolean>("keepAudio") ?: true,
                    enhancement = call.argument<Boolean>("enhancementEnabled") ?: false,
                    layout = call.argument<Number>("collageLayout")?.toInt() ?: 0,
                    audioSourceIndex = (call.argument<Number>("collageAudioSourceIndex")?.toInt() ?: 0)
                        .coerceIn(0, sources.lastIndex),
                    transition = call.argument<Number>("motionTransition")?.toInt() ?: 0,
                )
            }
        }
    }

    private class ConstantSpeedProvider(private val speed: Float) : androidx.media3.common.audio.SpeedProvider {
        override fun getSpeed(timeUs: Long): Float = speed

        override fun getNextSpeedChangeTimeUs(timeUs: Long): Long = C.TIME_UNSET
    }

    private class CollageCompositor(private val slots: List<Slot>) : VideoCompositorSettings {
        override fun getOutputSize(inputSizes: List<Size>): Size = Size(1080, 1920)

        override fun getOverlaySettings(inputId: Int, presentationTimeUs: Long): OverlaySettings {
            val slot = slots[inputId.coerceIn(0, slots.lastIndex)]
            val centerX = (slot.x + slot.width / 2f) / 1080f * 2f - 1f
            val centerY = 1f - (slot.y + slot.height / 2f) / 1920f * 2f
            return StaticOverlaySettings.Builder()
                .setOverlayFrameAnchor(0f, 0f)
                .setBackgroundFrameAnchor(centerX, centerY)
                .build()
        }
    }

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
}
