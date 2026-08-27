package com.example.after_frame

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.media.MediaCodecInfo
import android.media.MediaExtractor
import android.media.MediaFormat
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
import androidx.media3.effect.OverlayEffect
import androidx.media3.effect.Presentation
import androidx.media3.effect.RgbAdjustment
import androidx.media3.effect.RgbMatrix
import androidx.media3.effect.StaticOverlaySettings
import androidx.media3.transformer.Composition
import androidx.media3.transformer.DefaultEncoderFactory
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.Transformer
import androidx.media3.transformer.VideoEncoderSettings
import io.flutter.plugin.common.MethodCall
import java.io.File
import java.nio.ByteBuffer
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
        val request = prepare(RenderRequest.from(call))
        if (request.sources.size >= 3 && emulatorDecoderLimit()) {
            return renderStaged(request, work)
        }
        return try {
            renderOnce(request, File(work, "motion.mp4"))
        } catch (error: Exception) {
            if (cancelled) throw error
            val canRetryMuted = request.keepAudio && request.audioAvailable.any { it }
            if (canRetryMuted) {
                try {
                    return renderOnce(
                        request.copy(
                            keepAudio = false,
                            audioAvailable = List(request.sources.size) { false },
                        ),
                        File(work, "motion-muted.mp4"),
                    )
                } catch (mutedError: Exception) {
                    if (!cancelled && request.sources.size >= 3) {
                        return renderStaged(request, work)
                    }
                    throw mutedError
                }
            }
            if (request.sources.size >= 3 && MediaExportPolicy.decoderPressure(error)) {
                return renderStaged(request, work)
            }
            throw error
        }
    }

    private fun emulatorDecoderLimit(): Boolean =
        MediaExportPolicy.limitedConcurrentDecoders(
            hardware = android.os.Build.HARDWARE,
            fingerprint = android.os.Build.FINGERPRINT,
            model = android.os.Build.MODEL,
        )

    /**
     * Goldfish / low-end devices can only keep about two 1080p decoders alive.
     * A 3-cell collage therefore composes two frames first, then overlays the
     * remaining cell onto that already-baked canvas.
     */
    private fun renderStaged(request: RenderRequest, work: File): File {
        require(request.sources.size >= 3 && request.slots.size == request.sources.size) {
            "分阶段拼图需要至少 3 段带 Frame 的素材"
        }
        val first = request.copy(
            sources = request.sources.take(2),
            slots = request.slots.take(2),
            crops = request.crops.take(2),
            keepAudio = false,
            audioAvailable = listOf(false, false),
            seamSlots = request.slots.take(2),
            externalAudio = null,
        )
        val partial = renderOnce(first, File(work, "stage1.mp4"))
        val bakedDuration = mediaDurationMs(Uri.fromFile(partial)).let { duration ->
            if (duration > 0L) duration else (request.sources[0].endMs - request.sources[0].startMs)
        }
        val background = Source(
            uri = Uri.fromFile(partial),
            startMs = 0L,
            endMs = bakedDuration.coerceAtLeast(1L),
            baked = true,
        )
        val remaining = request.sources.drop(2)
        val audio = request.sources.getOrNull(request.audioSourceIndex)?.takeIf {
            request.keepAudio && request.hasUsableAudio(request.audioSourceIndex)
        }
        return renderOnce(
            request.copy(
                sources = listOf(background) + remaining,
                slots = listOf(
                    Slot(0, 0, request.canvasWidth, request.canvasHeight),
                ) + request.slots.drop(2),
                crops = listOf(CropWindow(0f, 0f, 1f, 1f)) + request.crops.drop(2),
                keepAudio = audio != null,
                audioAvailable = listOf(false) + remaining.map { false },
                audioSourceIndex = 0,
                seamSlots = request.slots,
                externalAudio = audio,
            ),
            File(work, "motion.mp4"),
        )
    }

    private fun renderOnce(request: RenderRequest, destination: File): File {
        destination.delete()
        val completed = CountDownLatch(1)
        val failure = AtomicReference<Throwable?>()

        mainHandler.post {
            try {
                check(!cancelled) { "导出已取消" }
                val transformer = Transformer.Builder(context)
                    .setVideoMimeType(MimeTypes.VIDEO_H264)
                    .setAudioMimeType(MimeTypes.AUDIO_AAC)
                    .setEncoderFactory(encoderFactory(request))
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
            val sequence = if (request.keepAudio && request.hasUsableAudio(0)) {
                EditedMediaItemSequence.withAudioAndVideoFrom(listOf(item))
            } else {
                EditedMediaItemSequence.withVideoFrom(listOf(item))
            }
            return Composition.Builder(sequence)
                .setHdrMode(Composition.HDR_MODE_TONE_MAP_HDR_TO_SDR_USING_OPEN_GL)
                .build()
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

        val audioSource = when {
            request.keepAudio && request.externalAudio != null -> request.externalAudio
            request.keepAudio && request.hasUsableAudio(request.audioSourceIndex) ->
                request.sources.getOrNull(request.audioSourceIndex)
            else -> null
        }
        if (audioSource != null) {
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
            .setHdrMode(Composition.HDR_MODE_TONE_MAP_HDR_TO_SDR_USING_OPEN_GL)
        // Media3 alpha-blends every video quad and pairs secondary frames by
        // nearest primary timestamp. Abutting content seams therefore shimmer.
        // Paint opaque static bars into the planned gutters after compose so
        // the join is identical on every encoded frame.
        seamOverlayEffect(
            request.seamSlots.ifEmpty { slots },
            request.canvasWidth,
            request.canvasHeight,
        )?.let { seam ->
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
            .setUri(playableMediaUri(source.uri))
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
        if (!source.baked && request.speed != 1f) {
            builder.setSpeed(ConstantSpeedProvider(request.speed))
        }
        if (!removeVideo) {
            builder.setEffects(
                Effects(emptyList(), videoEffects(request, source, slot, crop, source.baked)),
            )
        }
        return builder.build()
    }

    private fun videoEffects(
        request: RenderRequest,
        source: Source,
        slot: Slot?,
        crop: CropWindow?,
        baked: Boolean,
    ): List<Effect> {
        val effects = mutableListOf<Effect>()
        if (slot != null && crop != null) {
            val left = crop.left * 2f - 1f
            val right = (crop.left + crop.width) * 2f - 1f
            val top = 1f - crop.top * 2f
            val bottom = 1f - (crop.top + crop.height) * 2f
            effects += Crop(left, right, bottom, top)
            // Same-aspect Live/video pairs share a cell smaller than the
            // higher-res source. Crop keeps full framing; Presentation makes
            // the texture exactly the Frame size for the 1:1 compositor.
            effects += Presentation.createForWidthAndHeight(
                slot.width,
                slot.height,
                Presentation.LAYOUT_SCALE_TO_FIT,
            )
        } else {
            // A single source keeps its native resolution. Rescaling to a fixed
            // short side upsamples 720p into blur and throws away detail on
            // anything above 1080p, so only clamp what the encoder cannot take.
            downscaleToLimit(source)?.let { effects += it }
        }
        if (request.enhancement && !baked) {
            effects += Saturation(ENHANCEMENT_SATURATION)
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

    private fun downscaleToLimit(source: Source): Effect? {
        val shortSide = min(source.width, source.height)
        if (shortSide <= 0 || shortSide <= MAX_SHORT_SIDE) return null
        return Presentation.createForShortSide(MAX_SHORT_SIDE)
    }

    /**
     * Live photos arrive as `file://` cache MP4s. Probing them through
     * ContentResolver on the main thread can hang, so duration and audio are
     * resolved on the export worker before Transformer starts.
     */
    private fun prepare(request: RenderRequest): RenderRequest {
        val sources = request.sources.map { source ->
            val durationMs = mediaDurationMs(source.uri)
            val window = MediaClipWindows.clamp(source.startMs, source.endMs, durationMs)
            val size = videoSize(source.uri)
            source.copy(
                startMs = window[0],
                endMs = window[1],
                width = size.width,
                height = size.height,
            )
        }
        val audioAvailable = sources.map { hasUsableAudio(it.uri) }
        return request.copy(sources = sources, audioAvailable = audioAvailable)
    }

    /** Decoded frame size after the container's rotation metadata is applied. */
    private fun videoSize(uri: Uri): Size {
        val extractor = MediaExtractor()
        return try {
            openExtractor(extractor, uri)
            for (index in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(index)
                val mime = format.getString(android.media.MediaFormat.KEY_MIME) ?: continue
                if (!mime.startsWith("video/")) continue
                val width = format.integerOrZero(android.media.MediaFormat.KEY_WIDTH)
                val height = format.integerOrZero(android.media.MediaFormat.KEY_HEIGHT)
                val rotation = format.integerOrZero("rotation-degrees")
                return if (rotation == 90 || rotation == 270) {
                    Size(height, width)
                } else {
                    Size(width, height)
                }
            }
            Size(0, 0)
        } catch (_: Exception) {
            Size(0, 0)
        } finally {
            extractor.release()
        }
    }

    /**
     * Media3's default is `pixels * frameRate * 0.14`, which leaves large soft
     * gradients — fog, overcast sky, bokeh — with visible banding and blocky
     * chroma. A Live is at most six seconds, so paying for a much higher
     * ceiling costs a few megabytes and removes the artefacts entirely.
     */
    private fun encoderFactory(request: RenderRequest): DefaultEncoderFactory {
        val pixels = outputPixels(request).toLong()
        val bitrate = (pixels * OUTPUT_FRAME_RATE * BITRATE_PER_PIXEL)
            .toLong()
            .coerceIn(MIN_BITRATE, MAX_BITRATE)
            .toInt()
        return DefaultEncoderFactory.Builder(context)
            .setRequestedVideoEncoderSettings(
                VideoEncoderSettings.Builder()
                    .setBitrate(bitrate)
                    .setBitrateMode(MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_VBR)
                    .build(),
            )
            .build()
    }

    private fun outputPixels(request: RenderRequest): Int {
        if (request.slots.isNotEmpty() || request.sources.size > 1) {
            return request.canvasWidth * request.canvasHeight
        }
        val source = request.sources.first()
        if (source.width <= 0 || source.height <= 0) {
            return request.canvasWidth * request.canvasHeight
        }
        val shortSide = min(source.width, source.height)
        if (shortSide <= MAX_SHORT_SIDE) return source.width * source.height
        val scale = MAX_SHORT_SIDE.toDouble() / shortSide
        return ((source.width * scale) * (source.height * scale)).roundToInt()
    }

    private fun playableMediaUri(uri: Uri): Uri {
        if (uri.scheme != "file") return uri
        val path = uri.path ?: return uri
        return Uri.fromFile(File(path))
    }

    private fun openExtractor(extractor: MediaExtractor, uri: Uri) {
        if (uri.scheme == "file") {
            val path = requireNotNull(uri.path) { "Invalid file URI" }
            extractor.setDataSource(path)
        } else {
            extractor.setDataSource(context, uri, null)
        }
    }

    private fun hasUsableAudio(uri: Uri): Boolean {
        val extractor = MediaExtractor()
        return try {
            openExtractor(extractor, uri)
            val audioIndex = (0 until extractor.trackCount).firstOrNull { index ->
                extractor.getTrackFormat(index).getString(android.media.MediaFormat.KEY_MIME)
                    ?.startsWith("audio/") == true
            } ?: return false
            extractor.selectTrack(audioIndex)
            val buffer = ByteBuffer.allocateDirect(65_536)
            var samples = 0
            while (samples < 2) {
                buffer.clear()
                val size = extractor.readSampleData(buffer, 0)
                if (size < 0) break
                samples += 1
                extractor.advance()
            }
            samples > 0
        } catch (_: Exception) {
            false
        } finally {
            extractor.release()
        }
    }

    private fun mediaDurationMs(uri: Uri): Long {
        val extractor = MediaExtractor()
        return try {
            openExtractor(extractor, uri)
            var videoTrack = -1
            var formatDurationUs = 0L
            for (index in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(index)
                val mime = format.getString(android.media.MediaFormat.KEY_MIME) ?: continue
                if (!mime.startsWith("video/")) continue
                videoTrack = index
                if (format.containsKey(android.media.MediaFormat.KEY_DURATION)) {
                    formatDurationUs = format.getLong(android.media.MediaFormat.KEY_DURATION)
                }
                break
            }
            if (videoTrack < 0) return 0L
            extractor.selectTrack(videoTrack)
            extractor.seekTo(Long.MAX_VALUE, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
            var lastUs = extractor.sampleTime
            while (extractor.advance()) {
                if (extractor.sampleTime >= 0L) lastUs = extractor.sampleTime
            }
            val sampleEndMs = if (lastUs > 0L) lastUs / 1_000L + 1L else 0L
            val declaredMs = if (formatDurationUs > 0L) formatDurationUs / 1_000L else 0L
            when {
                sampleEndMs > 0L && declaredMs > 0L -> min(sampleEndMs, declaredMs)
                sampleEndMs > 0L -> sampleEndMs
                else -> declaredMs
            }
        } catch (_: Exception) {
            0L
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

    /**
     * Scales chroma around the BT.709 luma axis, leaving neutral pixels exactly
     * where they were.
     *
     * Media3's [androidx.media3.effect.HslAdjustment] saturation is an absolute
     * offset added to HSL's S channel, not a gain. On an overcast or foggy
     * frame — where S sits near 0.04 — a +0.08 offset triples the chroma and
     * amplifies the decoder's invisible ±1 Cb/Cr dither into visible red and
     * blue blotches. A gain matrix cannot do that: grey stays grey no matter
     * how strong the factor is.
     */
    private class Saturation(private val gain: Float) : RgbMatrix {
        override fun getMatrix(presentationTimeUs: Long, useHdr: Boolean): FloatArray {
            // Effects run on linear RGB (BT.709 for SDR, BT.2020 for HDR), so
            // the matching linear luma weights keep the luminance untouched.
            val (lr, lg, lb) = if (useHdr) BT2020_LUMA else BT709_LUMA
            val rest = 1f - gain
            // Column-major 4x4, matching android.opengl.Matrix and GLSL mat4.
            //
            // outR = (gain + rest*lr)*R + rest*lg*G + rest*lb*B
            // outG = rest*lr*R + (gain + rest*lg)*G + rest*lb*B
            // outB = rest*lr*R + rest*lg*G + (gain + rest*lb)*B
            //
            // A neutral pixel (R == G == B) therefore stays exactly where it
            // was because lr + lg + lb == 1: no red/blue cast on grey areas.
            return floatArrayOf(
                gain + rest * lr, rest * lr, rest * lr, 0f,
                rest * lg, gain + rest * lg, rest * lg, 0f,
                rest * lb, rest * lb, gain + rest * lb, 0f,
                0f, 0f, 0f, 1f,
            )
        }

        override fun isNoOp(inputWidth: Int, inputHeight: Int): Boolean = gain == 1f

        private companion object {
            val BT709_LUMA = Triple(.2126f, .7152f, .0722f)
            val BT2020_LUMA = Triple(.2627f, .6780f, .0593f)
        }
    }

    private data class Source(
        val uri: Uri,
        val startMs: Long,
        val endMs: Long,
        val baked: Boolean = false,
        val width: Int = 0,
        val height: Int = 0,
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
        val audioAvailable: List<Boolean> = emptyList(),
        val seamSlots: List<Slot> = emptyList(),
        val externalAudio: Source? = null,
    ) {
        val canOptimizeTrim: Boolean
            get() = sources.size == 1 &&
                speed == 1f &&
                !enhancement &&
                transition == 0 &&
                sources.none { it.uri.scheme == "file" }

        fun hasUsableAudio(index: Int): Boolean =
            audioAvailable.getOrElse(index) { false }

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
                        left < 0 || top < 0 || width <= 0 || height <= 0 ||
                        left + width > sourceWidth || top + height > sourceHeight
                    ) return@mapIndexedNotNull null
                    val slotAspect = slot.width.toDouble() / slot.height
                    val cropAspect = width.toDouble() / height
                    if (kotlin.math.abs(slotAspect - cropAspect) / slotAspect > 0.04) {
                        return@mapIndexedNotNull null
                    }
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

private const val MAX_SHORT_SIDE = 2160
private const val OUTPUT_FRAME_RATE = 30
private const val BITRATE_PER_PIXEL = 0.25f
private const val MIN_BITRATE = 6_000_000L
private const val MAX_BITRATE = 50_000_000L
private const val ENHANCEMENT_SATURATION = 1.2f

/** MediaFormat.getInteger(key) throws when the key is absent, unlike the API-29 default overload. */
private fun MediaFormat.integerOrZero(key: String): Int =
    runCatching { getInteger(key) }.getOrDefault(0)
