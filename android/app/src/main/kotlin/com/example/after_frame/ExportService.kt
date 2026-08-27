package com.example.after_frame

import android.content.ContentValues
import android.content.Intent
import android.media.MediaScannerConnection
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.UUID
import java.util.concurrent.ExecutorService

/** Owns export jobs, format packaging, MediaStore publication and sharing. */
class ExportService(
    private val context: MainActivity,
    private val executor: ExecutorService,
    private val renderer: Media3RenderEngine,
    private val exportIndex: ExportIndex,
) {
    @Volatile private var exportInProgress = false

    fun export(call: MethodCall, result: MethodChannel.Result) {
        synchronized(this) {
            if (exportInProgress) {
                result.error("EXPORT_IN_PROGRESS", "已有导出任务正在进行", null)
                return
            }
            exportInProgress = true
        }
        val work = File(context.cacheDir, "afterframe/export/${UUID.randomUUID()}").apply { mkdirs() }
        executor.execute {
            try {
                val mp4 = renderer.render(call, work)
                val output = packageAndPublish(call, mp4, work)
                context.runOnUiThread { result.success(output) }
            } catch (error: Exception) {
                context.runOnUiThread {
                    result.error("MEDIA3_EXPORT_FAILED", error.message ?: error.javaClass.simpleName, null)
                }
            } finally {
                exportInProgress = false
                work.deleteRecursively()
            }
        }
    }

    fun cancel() {
        renderer.cancel()
    }

    fun share(uri: Uri, mimeType: String, chooserTitle: String) {
        val sendIntent = Intent(Intent.ACTION_SEND).apply {
            type = mimeType
            putExtra(Intent.EXTRA_STREAM, uri)
            clipData = android.content.ClipData.newRawUri("AfterFrame", uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(Intent.createChooser(sendIntent, chooserTitle))
    }

    private fun packageAndPublish(call: MethodCall, mp4: File, work: File): Map<String, String> {
        val format = call.argument<String>("format") ?: "motionPhoto"
        require(format in setOf("motionPhoto", "mp4")) { "Media3 仅支持 Motion Photo 或 MP4 导出" }
        // Extract the still from the tone-mapped render so the cover always
        // matches the video's colours. A MediaMetadataRetriever frame taken
        // straight from an HDR source is not tone-mapped to SDR and shifts
        // toward red/blue once it is written back as a plain JPEG.
        val cover = extractRenderedCover(call, mp4, work)
        require(cover.isFile && cover.length() > 0L) { "导出封面不存在" }
        val safeName = (call.argument<String>("name") ?: "memory")
            .substringBeforeLast('.')
            .replace(Regex("[^a-zA-Z0-9_\\-\\u4e00-\\u9fa5]"), "_")
            .take(40)
        val stamp = System.currentTimeMillis()
        val baseName = "${safeName}_$stamp"
        val coverDirectory = File(context.filesDir, "afterframe/covers").apply { mkdirs() }
        val persistentCover = File(coverDirectory, "$baseName.jpg")
        cover.copyTo(persistentCover, overwrite = false)

        return try {
            val output = if (format == "motionPhoto") {
                publishMotionPhoto(call, mp4, cover, work, baseName, stamp, persistentCover)
            } else {
                publishStandalone(format, mp4, baseName, stamp, persistentCover)
            }
            exportIndex.save(output)
            output
        } catch (error: Exception) {
            persistentCover.delete()
            throw error
        }
    }

    private fun extractRenderedCover(call: MethodCall, mp4: File, work: File): File {
        val coverTimes = call.argument<List<Number>>("collageCoverMs").orEmpty().map { it.toLong() }
        if (coverTimes.size > 1) {
            runCatching { composeCollageStill(call, work, coverTimes) }.getOrNull()?.let { return it }
        }
        val startMs = call.argument<Number>("startMs")!!.toLong()
        val endMs = call.argument<Number>("endMs")!!.toLong()
        val coverMs = coverTimes.firstOrNull() ?: call.argument<Number>("coverMs")!!.toLong()
        val speed = (call.argument<Number>("playbackSpeed")?.toDouble() ?: 1.0).coerceIn(.5, 2.0)
        val presentationUs =
            ((coverMs - startMs).coerceIn(0, endMs - startMs) / speed * 1_000).toLong()
        val output = File(work, "rendered-cover.jpg")
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(mp4.absolutePath)
            val frame = requireNotNull(
                retriever.getFrameAtTime(presentationUs, MediaMetadataRetriever.OPTION_CLOSEST),
            ) { "无法从成片提取封面" }
            try {
                FileOutputStream(output).use { stream ->
                    check(frame.compress(android.graphics.Bitmap.CompressFormat.JPEG, 95, stream)) {
                        "无法编码成片封面"
                    }
                }
            } finally {
                frame.recycle()
            }
        } finally {
            retriever.release()
        }
        check(output.isFile && output.length() > 0L) { "成片封面为空" }
        return output
    }

    private fun composeCollageStill(
        call: MethodCall,
        work: File,
        coverTimes: List<Long>,
    ): File {
        val canvasWidth = call.argument<Number>("canvasWidth")!!.toInt()
        val canvasHeight = call.argument<Number>("canvasHeight")!!.toInt()
        val uris = call.argument<List<String>>("collageUris").orEmpty()
        val slots = numberRows(call, "collagePixelRects")
        val crops = numberRows(call, "sourceCropPixelRects")
        val sizes = numberRows(call, "collageSourceSizes")
        require(uris.size > 1 && uris.size == coverTimes.size) { "拼图封面缺少独立时间点" }
        require(
            slots.size == uris.size && crops.size == uris.size && sizes.size == uris.size,
        ) { "拼图封面缺少 Frame / Smart Crop 像素" }

        val composed = android.graphics.Bitmap.createBitmap(
            canvasWidth,
            canvasHeight,
            android.graphics.Bitmap.Config.ARGB_8888,
        )
        val canvas = android.graphics.Canvas(composed)
        canvas.drawColor(android.graphics.Color.BLACK)
        val paint = android.graphics.Paint(android.graphics.Paint.FILTER_BITMAP_FLAG)
        try {
            for (index in uris.indices) {
                val slot = slots[index]
                val crop = crops[index]
                val sourceSize = sizes[index]
                require(slot.size >= 4 && crop.size >= 4 && sourceSize.size >= 2) {
                    "第 ${index + 1} 段封面几何不完整"
                }
                val frame = decodeSourceFrame(Uri.parse(uris[index]), coverTimes[index])
                try {
                    val sourceWidth = sourceSize[0].toFloat().coerceAtLeast(1f)
                    val sourceHeight = sourceSize[1].toFloat().coerceAtLeast(1f)
                    val scaleX = frame.width / sourceWidth
                    val scaleY = frame.height / sourceHeight
                    val src = android.graphics.Rect(
                        (crop[0].toFloat() * scaleX).toInt().coerceIn(0, frame.width - 1),
                        (crop[1].toFloat() * scaleY).toInt().coerceIn(0, frame.height - 1),
                        ((crop[0].toFloat() + crop[2].toFloat()) * scaleX).toInt()
                            .coerceIn(1, frame.width),
                        ((crop[1].toFloat() + crop[3].toFloat()) * scaleY).toInt()
                            .coerceIn(1, frame.height),
                    )
                    val dst = android.graphics.Rect(
                        slot[0].toInt(),
                        slot[1].toInt(),
                        slot[0].toInt() + slot[2].toInt(),
                        slot[1].toInt() + slot[3].toInt(),
                    )
                    canvas.drawBitmap(frame, src, dst, paint)
                } finally {
                    frame.recycle()
                }
            }
            val output = File(work, "canvas-cover.jpg")
            FileOutputStream(output).use { stream ->
                check(composed.compress(android.graphics.Bitmap.CompressFormat.JPEG, 95, stream)) {
                    "无法编码独立封面拼图"
                }
            }
            check(output.isFile && output.length() > 0L) { "独立封面拼图为空" }
            return output
        } finally {
            composed.recycle()
        }
    }

    private fun decodeSourceFrame(uri: Uri, timeMs: Long): android.graphics.Bitmap {
        val retriever = MediaMetadataRetriever()
        return try {
            if (uri.scheme == "file") {
                retriever.setDataSource(uri.path)
            } else {
                retriever.setDataSource(context, uri)
            }
            requireNotNull(
                retriever.getFrameAtTime(timeMs * 1_000L, MediaMetadataRetriever.OPTION_CLOSEST),
            ) { "无法读取素材封面 $timeMs" }
        } finally {
            retriever.release()
        }
    }

    private fun publishMotionPhoto(
        call: MethodCall,
        mp4: File,
        cover: File,
        work: File,
        baseName: String,
        stamp: Long,
        persistentCover: File,
    ): Map<String, String> {
        val startMs = call.argument<Number>("startMs")!!.toLong()
        val endMs = call.argument<Number>("endMs")!!.toLong()
        val coverMs = call.argument<Number>("coverMs")!!.toLong()
        val speed = (call.argument<Number>("playbackSpeed")?.toDouble() ?: 1.0).coerceIn(.5, 2.0)
        val presentationUs = ((coverMs - startMs).coerceIn(0, endMs - startMs) / speed * 1_000).toLong()
        val motionPhoto = File(work, "${baseName}MP.jpg")
        MotionPhotoPackager.write(cover, mp4, motionPhoto, presentationUs, call.argument<Boolean>("loop") ?: false)

        val shareDirectory = File(context.filesDir, "afterframe/exports").apply { mkdirs() }
        val shareVideo = File(shareDirectory, "$baseName.mp4")
        mp4.copyTo(shareVideo, overwrite = false)
        var publicUri: Uri? = null
        try {
            publicUri = publishMedia(
                motionPhoto,
                motionPhoto.name,
                "image/jpeg",
                imageCollection(),
                Environment.DIRECTORY_DCIM,
            )
            val shareUri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", shareVideo)
            return output(publicUri, shareUri, publicUri, persistentCover, baseName, stamp, "video/mp4", "motionPhoto")
        } catch (error: Exception) {
            publicUri?.let(::removePublished)
            shareVideo.delete()
            throw error
        }
    }

    private fun publishStandalone(
        format: String,
        mp4: File,
        baseName: String,
        stamp: Long,
        persistentCover: File,
    ): Map<String, String> {
        require(format == "mp4") { "Unsupported standalone Media3 format: $format" }
        val extension = "mp4"
        val mimeType = "video/mp4"
        val uri = publishMedia(
            mp4,
            "$baseName.$extension",
            mimeType,
            videoCollection(),
            Environment.DIRECTORY_MOVIES,
        )
        return output(uri, uri, uri, persistentCover, baseName, stamp, mimeType, format)
    }

    private fun output(
        primary: Uri,
        share: Uri,
        cover: Uri,
        persistentCover: File,
        baseName: String,
        stamp: Long,
        mimeType: String,
        format: String,
    ) = mapOf(
        "liveUri" to primary.toString(),
        "galleryUri" to share.toString(),
        "coverUri" to cover.toString(),
        "coverPath" to persistentCover.absolutePath,
        "displayName" to baseName,
        "albumName" to "AfterFrame",
        "createdAt" to stamp.toString(),
        "shareMimeType" to mimeType,
        "format" to format,
    )

    private fun imageCollection(): Uri = if (Build.VERSION.SDK_INT >= 29) {
        MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
    } else MediaStore.Images.Media.EXTERNAL_CONTENT_URI

    private fun videoCollection(): Uri = if (Build.VERSION.SDK_INT >= 29) {
        MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
    } else MediaStore.Video.Media.EXTERNAL_CONTENT_URI

    private fun publishMedia(source: File, name: String, mime: String, collection: Uri, directoryName: String): Uri {
        if (Build.VERSION.SDK_INT < 29) {
            @Suppress("DEPRECATION")
            val directory = File(Environment.getExternalStoragePublicDirectory(directoryName), "AfterFrame").apply { mkdirs() }
            val destination = File(directory, name)
            source.copyTo(destination, overwrite = false)
            MediaScannerConnection.scanFile(context, arrayOf(destination.absolutePath), arrayOf(mime), null)
            return Uri.fromFile(destination)
        }
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            put(MediaStore.MediaColumns.RELATIVE_PATH, "$directoryName/AfterFrame")
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = context.contentResolver.insert(collection, values) ?: error("无法创建媒体库项目")
        try {
            context.contentResolver.openOutputStream(uri, "w")?.use { output ->
                FileInputStream(source).use { it.copyTo(output) }
            } ?: error("无法写入媒体库")
            context.contentResolver.update(uri, ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }, null, null)
            return uri
        } catch (error: Exception) {
            context.contentResolver.delete(uri, null, null)
            throw error
        }
    }

    private fun removePublished(uri: Uri) {
        runCatching { if (uri.scheme == "file") File(uri.path!!).delete() else context.contentResolver.delete(uri, null, null) }
    }

    private fun numberRows(call: MethodCall, key: String): List<List<Number>> {
        return call.argument<List<*>>(key).orEmpty().mapNotNull { encoded ->
            val values = encoded as? List<*> ?: return@mapNotNull null
            values.mapNotNull { it as? Number }.takeIf { it.size == values.size }
        }
    }
}

/** Android Motion Photo 1.0 packager: JPEG/XMP followed by the exact MP4 payload. */
internal object MotionPhotoPackager {
    fun write(cover: File, motion: File, destination: File, presentationUs: Long, loop: Boolean) {
        val jpeg = cover.readBytes()
        require(jpeg.size >= 2 && jpeg[0] == 0xFF.toByte() && jpeg[1] == 0xD8.toByte()) { "封面不是有效 JPEG" }
        val xmp = """
            <x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"><rdf:Description rdf:about="" xmlns:Camera="http://ns.google.com/photos/1.0/camera/" xmlns:Container="http://ns.google.com/photos/1.0/container/" xmlns:Item="http://ns.google.com/photos/1.0/container/item/" xmlns:AfterFrame="https://afterframe.app/ns/1.0/" Camera:MotionPhoto="1" Camera:MotionPhotoVersion="1" Camera:MotionPhotoPresentationTimestampUs="$presentationUs" AfterFrame:Loop="$loop"><Container:Directory><rdf:Seq><rdf:li rdf:parseType="Resource"><Container:Item Item:Mime="image/jpeg" Item:Semantic="Primary"/></rdf:li><rdf:li rdf:parseType="Resource"><Container:Item Item:Mime="video/mp4" Item:Semantic="MotionPhoto" Item:Length="${motion.length()}"/></rdf:li></rdf:Seq></Container:Directory></rdf:Description></rdf:RDF></x:xmpmeta>
        """.trimIndent().toByteArray(Charsets.UTF_8)
        val header = "http://ns.adobe.com/xap/1.0/\u0000".toByteArray(Charsets.US_ASCII)
        val payloadLength = header.size + xmp.size
        require(payloadLength + 2 <= 0xFFFF) { "Motion Photo XMP 过大" }
        val length = ByteBuffer.allocate(2).order(ByteOrder.BIG_ENDIAN).putShort((payloadLength + 2).toShort()).array()
        val insertion = jpegMetadataEnd(jpeg)
        FileOutputStream(destination).use { output ->
            output.write(jpeg, 0, insertion)
            output.write(byteArrayOf(0xFF.toByte(), 0xE1.toByte()))
            output.write(length)
            output.write(header)
            output.write(xmp)
            output.write(jpeg, insertion, jpeg.size - insertion)
            FileInputStream(motion).use { it.copyTo(output) }
        }
        require(destination.length() == jpeg.size + 4L + payloadLength + motion.length()) { "Motion Photo 写入长度异常" }
    }

    private fun jpegMetadataEnd(jpeg: ByteArray): Int {
        var offset = 2
        while (offset + 4 <= jpeg.size && jpeg[offset] == 0xFF.toByte()) {
            val marker = jpeg[offset + 1].toInt() and 0xFF
            if (marker !in 0xE0..0xEF) break
            val length = ((jpeg[offset + 2].toInt() and 0xFF) shl 8) or (jpeg[offset + 3].toInt() and 0xFF)
            if (length < 2 || offset + 2 + length > jpeg.size) break
            offset += 2 + length
        }
        return offset
    }
}
