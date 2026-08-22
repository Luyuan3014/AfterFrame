package com.example.after_frame

import android.content.Context
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaMetadataRetriever
import android.media.MediaMuxer
import android.net.Uri
import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.util.Locale

/**
 * Turns an Android Motion Photo / OEM Live image into a playable MP4.
 *
 * Google Motion Photo 1.0, MicroVideo and many Samsung/Xiaomi JPEGs store a
 * trailing MP4 after the still. HEIC Live images are remuxed when the
 * container exposes a video track. Extracted files live under
 * `cacheDir/afterframe/motion_sources` so they are disposable cache.
 */
internal object MotionPhotoSource {
    data class Payload(
        val offset: Long,
        val length: Long,
    )

    fun looksLikeMotionName(name: String): Boolean {
        val value = name.lowercase(Locale.US)
        return value.startsWith("mvimg") ||
            value.contains("_mp.") ||
            value.contains(".mp.") ||
            value.endsWith("mp.jpg") ||
            value.endsWith("mp.jpeg") ||
            value.contains("motion") ||
            (value.startsWith("pxl_") && value.contains("mp"))
    }

    fun headerSuggestsMotion(header: ByteArray): Boolean {
        val xmp = header.toString(Charsets.ISO_8859_1)
        return MOTION_FLAG.containsMatchIn(xmp) ||
            MICRO_VIDEO_FLAG.containsMatchIn(xmp) ||
            MOTION_SEMANTIC.containsMatchIn(xmp) ||
            MICRO_OFFSET.containsMatchIn(xmp)
    }

    fun inspectFile(file: File): Payload? {
        if (!file.exists() || file.length() < 32L) return null
        val headerSize = minOf(file.length(), HEADER_LIMIT).toInt()
        val header = ByteArray(headerSize)
        RandomAccessFile(file, "r").use { it.readFully(header) }
        return inspectHeader(header, file.length())
    }

    fun inspectHeader(header: ByteArray, fileLength: Long): Payload? {
        if (fileLength < 32L || header.size < 8) return null
        val xmp = header.toString(Charsets.ISO_8859_1)
        motionPhotoLength(xmp)?.let { length ->
            return payloadAtEnd(fileLength, length)
        }
        microVideoOffset(xmp)?.let { length ->
            return payloadAtEnd(fileLength, length)
        }
        if (isJpeg(header)) {
            trailingMp4FromJpeg(header, fileLength)?.let { return it }
        }
        return null
    }

    fun extract(source: File, destination: File): File {
        val payload = inspectFile(source)
            ?: error("Not a Motion Photo container")
        writeRange(source, payload, destination)
        return destination
    }

    fun extract(
        context: Context,
        uri: Uri,
        cacheDirectory: File,
    ): File {
        val directory = File(cacheDirectory, DIRECTORY).apply { mkdirs() }
        val destination = File(directory, "${uri.hashCode()}.mp4")
        if (destination.exists() && destination.length() > 32L && isPlayableMp4(destination)) {
            return destination
        }
        val copied = File(directory, ".${uri.hashCode()}.${System.nanoTime()}.src")
        try {
            context.contentResolver.openInputStream(uri).use { input ->
                requireNotNull(input) { "Unable to open Motion Photo" }
                copied.outputStream().use { input.copyTo(it) }
            }
            val payload = inspectFile(copied)
            if (payload != null) {
                writeRange(copied, payload, destination)
                if (isPlayableMp4(destination)) return destination
                destination.delete()
            }
            if (remuxEmbeddedVideo(context, uri, destination) && isPlayableMp4(destination)) {
                return destination
            }
            destination.delete()
            error("Unable to extract Live motion from this photo")
        } finally {
            copied.delete()
        }
    }

    fun isPlayableMp4(file: File): Boolean {
        if (!file.exists() || file.length() < 32L) return false
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(file.absolutePath)
            val duration = retriever.extractMetadata(
                MediaMetadataRetriever.METADATA_KEY_DURATION,
            )?.toLongOrNull() ?: 0L
            val width = retriever.extractMetadata(
                MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH,
            )?.toIntOrNull() ?: 0
            duration > 0L && width > 0
        } catch (_: Exception) {
            false
        } finally {
            retriever.release()
        }
    }

    private fun motionPhotoLength(xmp: String): Long? {
        MOTION_ITEM_LENGTH.find(xmp)?.groupValues?.get(1)?.toLongOrNull()?.let { return it }
        LENGTH_BEFORE_SEMANTIC.find(xmp)?.groupValues?.get(1)?.toLongOrNull()?.let { return it }
        return ITEM_LENGTH.findAll(xmp)
            .mapNotNull { it.groupValues[1].toLongOrNull() }
            .lastOrNull()
    }

    private fun microVideoOffset(xmp: String): Long? =
        MICRO_OFFSET.find(xmp)?.groupValues?.get(1)?.toLongOrNull()

    private fun payloadAtEnd(fileLength: Long, length: Long): Payload? {
        if (length !in 8 until fileLength) return null
        return Payload(offset = fileLength - length, length = length)
    }

    private fun trailingMp4FromJpeg(header: ByteArray, fileLength: Long): Payload? {
        val eoi = jpegEoi(header) ?: return null
        if (eoi + 8 >= header.size) return null
        if (!looksLikeMp4(header, eoi)) return null
        val length = fileLength - eoi
        return payloadAtEnd(fileLength, length)
    }

    private fun jpegEoi(jpeg: ByteArray): Int? {
        var offset = 2
        while (offset + 4 <= jpeg.size && jpeg[offset] == 0xFF.toByte()) {
            val marker = jpeg[offset + 1].toInt() and 0xFF
            if (marker == 0xDA) {
                for (index in offset + 2 until jpeg.size - 1) {
                    if (jpeg[index] == 0xFF.toByte() && jpeg[index + 1] == 0xD9.toByte()) {
                        return index + 2
                    }
                }
                return null
            }
            if (marker !in 0xE0..0xEF && marker != 0xDB && marker != 0xC0 &&
                marker != 0xC2 && marker != 0xC4 && marker != 0xDD
            ) {
                break
            }
            val length = ((jpeg[offset + 2].toInt() and 0xFF) shl 8) or
                (jpeg[offset + 3].toInt() and 0xFF)
            if (length < 2 || offset + 2 + length > jpeg.size) break
            offset += 2 + length
        }
        for (index in jpeg.size - 2 downTo 0) {
            if (jpeg[index] == 0xFF.toByte() && jpeg[index + 1] == 0xD9.toByte()) {
                return index + 2
            }
        }
        return null
    }

    private fun looksLikeMp4(bytes: ByteArray, offset: Int): Boolean {
        if (offset + 8 > bytes.size) return false
        val type = bytes.copyOfRange(offset + 4, offset + 8).toString(Charsets.US_ASCII)
        return type == "ftyp"
    }

    private fun writeRange(source: File, payload: Payload, destination: File) {
        val pending = File(destination.parentFile, ".${destination.name}.${System.nanoTime()}.tmp")
        try {
            RandomAccessFile(source, "r").use { input ->
                input.seek(payload.offset)
                pending.outputStream().use { output ->
                    val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                    var remaining = payload.length
                    while (remaining > 0) {
                        val read = input.read(
                            buffer,
                            0,
                            minOf(buffer.size.toLong(), remaining).toInt(),
                        )
                        check(read > 0) { "Unexpected end of Motion Photo" }
                        output.write(buffer, 0, read)
                        remaining -= read
                    }
                }
            }
            check(pending.length() == payload.length && pending.renameTo(destination)) {
                "Unable to save extracted Live motion"
            }
        } finally {
            pending.delete()
        }
    }

    private fun remuxEmbeddedVideo(context: Context, uri: Uri, destination: File): Boolean {
        val extractor = MediaExtractor()
        val pending = File(destination.parentFile, ".${destination.name}.${System.nanoTime()}.mux")
        var muxer: MediaMuxer? = null
        return try {
            extractor.setDataSource(context, uri, null)
            val tracks = mutableListOf<Pair<Int, Int>>()
            muxer = MediaMuxer(pending.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            for (index in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(index)
                val mime = format.getString(android.media.MediaFormat.KEY_MIME) ?: continue
                if (!mime.startsWith("video/") && !mime.startsWith("audio/")) continue
                extractor.selectTrack(index)
                tracks += index to muxer.addTrack(format)
            }
            if (tracks.none { extractor.getTrackFormat(it.first).getString(android.media.MediaFormat.KEY_MIME)?.startsWith("video/") == true }) {
                return false
            }
            muxer.start()
            val buffer = ByteBuffer.allocateDirect(1_048_576)
            val info = MediaCodec.BufferInfo()
            while (true) {
                buffer.clear()
                val size = extractor.readSampleData(buffer, 0)
                if (size < 0) break
                val extractorTrack = extractor.sampleTrackIndex
                val muxerTrack = tracks.firstOrNull { it.first == extractorTrack }?.second ?: run {
                    extractor.advance()
                    continue
                }
                info.offset = 0
                info.size = size
                info.presentationTimeUs = extractor.sampleTime.coerceAtLeast(0L)
                info.flags = extractor.sampleFlags
                muxer.writeSampleData(muxerTrack, buffer, info)
                extractor.advance()
            }
            muxer.stop()
            muxer.release()
            muxer = null
            pending.renameTo(destination) && destination.length() > 32L
        } catch (_: Exception) {
            false
        } finally {
            pending.delete()
            runCatching { muxer?.release() }
            extractor.release()
        }
    }

    private fun isJpeg(bytes: ByteArray): Boolean =
        bytes.size >= 2 && bytes[0] == 0xFF.toByte() && bytes[1] == 0xD8.toByte()

    private val MOTION_FLAG = Regex("""(?:Camera|GCamera|GCamera:)?MotionPhoto=["']1["']""")
    private val MICRO_VIDEO_FLAG = Regex("""GCamera:MicroVideo=["']1["']""")
    private val MOTION_SEMANTIC = Regex("""Item:Semantic=["']MotionPhoto["']""")
    private val MICRO_OFFSET = Regex("""GCamera:MicroVideoOffset=["'](\d+)["']""")
    private val MOTION_ITEM_LENGTH = Regex(
        """Item:Semantic=["']MotionPhoto["'][^>]*Item:Length=["'](\d+)["']""",
    )
    private val LENGTH_BEFORE_SEMANTIC = Regex(
        """Item:Length=["'](\d+)["'][^>]*Item:Semantic=["']MotionPhoto["']""",
    )
    private val ITEM_LENGTH = Regex("""Item:Length=["'](\d+)["']""")

    const val DIRECTORY = "afterframe/motion_sources"
    private const val HEADER_LIMIT = 1_048_576L
}