package com.example.after_frame

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.media.MediaExtractor
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
import androidx.media3.effect.BitmapOverlay
import androidx.media3.effect.Crop
import androidx.media3.effect.GaussianBlur
import androidx.media3.effect.HslAdjustment
import androidx.media3.effect.OverlayEffect
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
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

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
        if (request.sources.size == 1 && request.slots.isEmpty()) {
            val source = request.sources.single()
            val item = editedItem(
                source = source,
                request = request,
                removeAudio = !request.keepAudio,
                removeVideo = false,
                slot = null,
                crop = null,
            )
            val sequence = if (request.keepAudio && hasAudio(source.uri)) {
                EditedMediaItemSequence.withAudioAndVideoFrom(listOf(item))
            } else {
                EditedMediaItemSequence.withVideoFrom(listOf(item))
            }
            return Composition.Builder(sequence).build()
        }

        val slots = request.slots.ifEmpty {
            collageSlots(request.sources.size, request.layout)
        }
        val sequences = request.sources.mapIndexed { index, source ->
            EditedMediaItemSequence.withVideoFrom(
                listOf(
                    editedItem(
                        source = source,
                        request = request,
                        removeAudio = true,
                        removeVideo = false,
                        slot = slots[index],
                        crop = request.crops.getOrNull(index),
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
                        crop = null,
                    ),
                ),
            )
        }

        val builder = Composition.Builder(sequences)
            .setVideoCompositorSettings(
                CollageCompositor(slots, request.canvasWidth, request.canvasHeight),
            )
        // Media3 alpha-blends every video quad and pairs secondary frames by
        // nearest primary timestamp. Abutting content seams therefore shimmer.
        // Paint opaque static bars into the planned gutters after compose so
        // the join is identical on every encoded frame.
        seamOverlayEffect(slots, request.canvasWidth, request.canvasHeight)?.let { seam ->
            builder.setEffects(Effects(/* audioProcessors= */ emptyList(), listOf(seam)))
        }
        return builder.build()
    }

    /**
     * Builds opaque solid strips that sit in every gutter between slots.
     *
     * Applied as a composition OverlayEffect (after DefaultVideoCompositor), so
     * they cover Media3's alpha-blended video edges. Static black pixels cannot
     * shimmer with nearest-frame secondary sync the way abutting video content
     * does — which is why Studio (Flutter opaque composite) looked fine while
     * the exported Live divider floated.
     */
    private fun seamOverlayEffect(
        slots: List<Slot>,
        canvasWidth: Int,
        canvasHeight: Int,
    ): Effect? {
        if (slots.size < 2) return null
        val seams = mutableListOf<Slot>()
        for (i in 0 until slots.lastIndex) {
            for (j in i + 1..slots.lastIndex) {
                val a = slots[i]
                val b = slots[j]
                val overlapX = min(a.x + a.width, b.x + b.width) - max(a.x, b.x)
                val overlapY = min(a.y + a.height, b.y + b.height) - max(a.y, b.y)
                if (overlapX > 0) {
                    val gapTop = min(a.y + a.height, b.y + b.height)
                    val gapBottom = max(a.y, b.y)
                    val gap = gapBottom - gapTop
                    if (gap in 1..8) {
                        seams += Slot(
                            x = max(a.x, b.x),
                            y = gapTop,
                            width = overlapX,
                            height = gap,
                        )
                    }
                }
                if (overlapY > 0) {
                    val gapLeft = min(a.x + a.width, b.x + b.width)
                    val gapRight = max(a.x, b.x)
                    val gap = gapRight - gapLeft
                    if (gap in 1..8) {
                        seams += Slot(
                            x = gapLeft,
                            y = max(a.y, b.y),
                            width = gap,
                            height = overlapY,
                        )
                    }
                }
            }
        }
        if (seams.isEmpty()) return null

        val overlays = seams.map { seam ->
            // Expand 1px onto each neighbouring video so any sub-pixel blend
            // fringe is buried under opaque, unchanging pixels.
            val left = (seam.x - 1).coerceAtLeast(0)
            val top = (seam.y - 1).coerceAtLeast(0)
            val right = (seam.x + seam.width + 1).coerceAtMost(canvasWidth)
            val bottom = (seam.y + seam.height + 1).coerceAtMost(canvasHeight)
            val width = (right - left).coerceAtLeast(1)
            val height = (bottom - top).coerceAtLeast(1)
            val strip = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            strip.eraseColor(Color.BLACK)
            val leftNdc = left.toFloat() / canvasWidth * 2f - 1f
            val topNdc = 1f - top.toFloat() / canvasHeight * 2f
            BitmapOverlay.createStaticBitmapOverlay(
                strip,
                StaticOverlaySettings.Builder()
                    .setOverlayFrameAnchor(-1f, 1f)
                    .setBackgroundFrameAnchor(leftNdc, topNdc)
                    .setScale(1f, 1f)
                    .build(),
            )
        }
        return OverlayEffect(overlays)
    }

    private fun editedItem(
        source: Source,
        request: RenderRequest,
        removeAudio: Boolean,
        removeVideo: Boolean,
        slot: Slot?,
        crop: CropWindow?,
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
            builder.setEffects(Effects(emptyList(), videoEffects(request, slot, crop)))
        }
        return builder.build()
    }

    private fun videoEffects(
        request: RenderRequest,
        slot: Slot?,
        crop: CropWindow?,
    ): List<Effect> {
        val effects = mutableListOf<Effect>()
        if (slot != null && crop != null) {
            val left = crop.left * 2f - 1f
            val right = (crop.left + crop.width) * 2f - 1f
            val top = 1f - crop.top * 2f
            val bottom = 1f - (crop.top + crop.height) * 2f
            effects += Crop(left, right, bottom, top)
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
    )

    private data class Slot(
        val x: Int,
        val y: Int,
        val width: Int,
        val height: Int,
    )

    private data class CropWindow(
        val left: Float,
        val top: Float,
        val width: Float,
        val height: Float,
    )

    private data class RenderRequest(
        val sources: List<Source>,
        val speed: Float,
        val keepAudio: Boolean,
        val enhancement: Boolean,
        val layout: Int,
        val audioSourceIndex: Int,
        val transition: Int,
        val slots: List<Slot>,
        val crops: List<CropWindow>,
        val canvasWidth: Int,
        val canvasHeight: Int,
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
                val encodedRects = call.argument<List<*>>("collageRects").orEmpty()
                val encodedCrops = call.argument<List<*>>("sourceCropRects").orEmpty()
                val encodedPixelRects = call.argument<List<*>>("collagePixelRects").orEmpty()
                val encodedCropPixels = call.argument<List<*>>("sourceCropPixelRects").orEmpty()
                val encodedSourceSizes = call.argument<List<*>>("collageSourceSizes").orEmpty()
                val canvasWidth = evenDimension(
                    (call.argument<Number>("canvasWidth")?.toInt() ?: 1080).coerceIn(2, 4320),
                )
                val canvasHeight = evenDimension(
                    (call.argument<Number>("canvasHeight")?.toInt() ?: 1920).coerceIn(2, 4320),
                )
                val sources = uris.mapIndexed { index, uri ->
                    val start = starts.getOrNull(index)?.toLong() ?: defaultStart
                    val end = ends.getOrNull(index)?.toLong() ?: defaultEnd
                    require(end > start) { "第 ${index + 1} 段素材的时间范围无效" }
                    Source(
                        uri = uri,
                        startMs = start,
                        endMs = end,
                    )
                }
                val pixelSlots = encodedPixelRects.take(sources.size).mapNotNull { encoded ->
                    val values = encoded as? List<*> ?: return@mapNotNull null
                    if (values.size < 4) return@mapNotNull null
                    val left = (values[0] as? Number)?.toInt() ?: return@mapNotNull null
                    val top = (values[1] as? Number)?.toInt() ?: return@mapNotNull null
                    val width = (values[2] as? Number)?.toInt() ?: return@mapNotNull null
                    val height = (values[3] as? Number)?.toInt() ?: return@mapNotNull null
                    if (
                        left < 0 || top < 0 || width <= 0 || height <= 0 ||
                        left + width > canvasWidth || top + height > canvasHeight
                    ) return@mapNotNull null
                    Slot(left, top, width, height)
                }.takeIf { it.size == sources.size }.orEmpty()
                val normalizedSlots = encodedRects.take(sources.size).mapNotNull { encoded ->
                    val values = encoded as? List<*> ?: return@mapNotNull null
                    if (values.size < 4) return@mapNotNull null
                    val x = (values[0] as? Number)?.toDouble() ?: return@mapNotNull null
                    val y = (values[1] as? Number)?.toDouble() ?: return@mapNotNull null
                    val width = (values[2] as? Number)?.toDouble() ?: return@mapNotNull null
                    val height = (values[3] as? Number)?.toDouble() ?: return@mapNotNull null
                    if (width <= 0.0 || height <= 0.0) return@mapNotNull null
                    val left = (x.coerceIn(0.0, 1.0) * canvasWidth).roundToInt()
                    val top = (y.coerceIn(0.0, 1.0) * canvasHeight).roundToInt()
                    val right = ((x + width).coerceIn(0.0, 1.0) * canvasWidth).roundToInt()
                    val bottom = ((y + height).coerceIn(0.0, 1.0) * canvasHeight).roundToInt()
                    Slot(
                        left,
                        top,
                        (right - left).coerceAtLeast(1),
                        (bottom - top).coerceAtLeast(1),
                    )
                }.takeIf { it.size == sources.size }.orEmpty()
                val customSlots = pixelSlots.ifEmpty { normalizedSlots }
                val pixelCrops = encodedCropPixels.take(sources.size).mapIndexedNotNull { index, encoded ->
                    val values = encoded as? List<*> ?: return@mapIndexedNotNull null
                    val sizeValues = encodedSourceSizes.getOrNull(index) as? List<*>
                        ?: return@mapIndexedNotNull null
                    if (values.size < 4 || sizeValues.size < 2) return@mapIndexedNotNull null
                    val left = (values[0] as? Number)?.toInt() ?: return@mapIndexedNotNull null
                    val top = (values[1] as? Number)?.toInt() ?: return@mapIndexedNotNull null
                    val width = (values[2] as? Number)?.toInt() ?: return@mapIndexedNotNull null
                    val height = (values[3] as? Number)?.toInt() ?: return@mapIndexedNotNull null
                    val sourceWidth = (sizeValues[0] as? Number)?.toInt()
                        ?: return@mapIndexedNotNull null
                    val sourceHeight = (sizeValues[1] as? Number)?.toInt()
                        ?: return@mapIndexedNotNull null
                    val slot = customSlots.getOrNull(index) ?: return@mapIndexedNotNull null
                    if (
                        left < 0 || top < 0 || width != slot.width || height != slot.height ||
                        left + width > sourceWidth || top + height > sourceHeight
                    ) return@mapIndexedNotNull null
                    CropWindow(
                        left = left.toFloat() / sourceWidth,
                        top = top.toFloat() / sourceHeight,
                        width = width.toFloat() / sourceWidth,
                        height = height.toFloat() / sourceHeight,
                    )
                }.takeIf { it.size == sources.size }.orEmpty()
                val normalizedCrops = encodedCrops.take(sources.size).mapNotNull { encoded ->
                    val values = encoded as? List<*> ?: return@mapNotNull null
                    if (values.size < 4) return@mapNotNull null
                    val left = (values[0] as? Number)?.toFloat() ?: return@mapNotNull null
                    val top = (values[1] as? Number)?.toFloat() ?: return@mapNotNull null
                    val width = (values[2] as? Number)?.toFloat() ?: return@mapNotNull null
                    val height = (values[3] as? Number)?.toFloat() ?: return@mapNotNull null
                    if (width <= 0f || height <= 0f) return@mapNotNull null
                    val safeLeft = left.coerceIn(0f, 1f)
                    val safeTop = top.coerceIn(0f, 1f)
                    CropWindow(
                        left = safeLeft,
                        top = safeTop,
                        width = width.coerceIn(0f, 1f - safeLeft),
                        height = height.coerceIn(0f, 1f - safeTop),
                    )
                }.takeIf { it.size == sources.size }.orEmpty()
                val customCrops = pixelCrops.ifEmpty { normalizedCrops }
                if (sources.size > 1) {
                    require(customSlots.size == sources.size) {
                        "Canvas First Frame 像素矩形缺失或越界"
                    }
                    require(customCrops.size == sources.size) {
                        "Canvas First Smart Crop 像素矩形缺失或与 Frame 不一致"
                    }
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
                    slots = customSlots,
                    crops = customCrops,
                    canvasWidth = canvasWidth,
                    canvasHeight = canvasHeight,
                )
            }

            private fun evenDimension(value: Int): Int = if (value % 2 == 0) value else value - 1
        }
    }

    private class ConstantSpeedProvider(private val speed: Float) : androidx.media3.common.audio.SpeedProvider {
        override fun getSpeed(timeUs: Long): Float = speed

        override fun getNextSpeedChangeTimeUs(timeUs: Long): Long = C.TIME_UNSET
    }

    private class CollageCompositor(
        private val slots: List<Slot>,
        private val canvasWidth: Int,
        private val canvasHeight: Int,
    ) : VideoCompositorSettings {
        override fun getOutputSize(inputSizes: List<Size>): Size {
            require(inputSizes.size == slots.size) { "裁剪结果数量与 Frame 数量不一致" }
            inputSizes.forEachIndexed { index, input ->
                val slot = slots[index]
                require(
                    input.width == slot.width && input.height == slot.height,
                ) {
                    "Canvas First 1:1 校验失败：素材 ${index + 1} 裁剪后 " +
                        "${input.width}x${input.height}，Frame 为 ${slot.width}x${slot.height}"
                }
            }
            return Size(canvasWidth, canvasHeight)
        }

        override fun getOverlaySettings(inputId: Int, presentationTimeUs: Long): OverlaySettings {
            val slot = slots[inputId.coerceIn(0, slots.lastIndex)]
            // Anchor at the overlay's top-left and place that corner on the
            // slot's top-left in NDC. Center-anchoring with float math can leave
            // a sub-pixel clear hairline between stacked frames that H.264 then
            // makes shimmer up and down in album playback.
            val leftNdc = slot.x.toFloat() / canvasWidth * 2f - 1f
            val topNdc = 1f - slot.y.toFloat() / canvasHeight * 2f
            return StaticOverlaySettings.Builder()
                .setOverlayFrameAnchor(-1f, 1f)
                .setBackgroundFrameAnchor(leftNdc, topNdc)
                .setScale(1f, 1f)
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
