package com.example.after_frame

import android.content.ContentValues
import android.content.Intent
import android.media.MediaScannerConnection
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
    private val renderer: FfmpegRenderEngine,
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
                    result.error("FFMPEG_EXPORT_FAILED", error.message ?: error.javaClass.simpleName, null)
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
        require(format in setOf("motionPhoto", "mp4", "gif", "webp")) { "不支持的导出格式：$format" }
        val cover = File(call.argument<String>("coverPath")!!)
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
                publishStandalone(format, mp4, work, baseName, stamp, persistentCover)
            }
            exportIndex.save(output)
            output
        } catch (error: Exception) {
            persistentCover.delete()
            throw error
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
        work: File,
        baseName: String,
        stamp: Long,
        persistentCover: File,
    ): Map<String, String> {
        val (extension, mimeType) = when (format) {
            "mp4" -> "mp4" to "video/mp4"
            "gif" -> "gif" to "image/gif"
            "webp" -> "webp" to "image/webp"
            else -> error("不支持的导出格式：$format")
        }
        val source = if (format == "mp4") mp4 else File(work, "$baseName.$extension").also {
            renderer.renderAnimated(mp4, format, it)
        }
        val collection = if (format == "mp4") videoCollection() else imageCollection()
        val directory = if (format == "mp4") Environment.DIRECTORY_MOVIES else Environment.DIRECTORY_PICTURES
        val uri = publishMedia(source, "$baseName.$extension", mimeType, collection, directory)
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
