@file:androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)

package com.example.after_frame

import android.content.ContentValues
import android.content.Intent
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.core.content.FileProvider
import androidx.media3.common.MediaItem
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.Transformer
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.UUID
import java.util.concurrent.ExecutorService

/** Frame-accurate export plus MediaStore publishing for the AfterFrame album. */
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
                            val output = packageAndPublish(call, motion, work)
                            context.runOnUiThread { result.success(output) }
                        } catch (error: Exception) {
                            context.runOnUiThread {
                                result.error("MEDIA_ENGINE_FAILED", error.message, null)
                            }
                        } finally {
                            work.deleteRecursively()
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
        val presentationUs = ((coverMs - startMs).coerceIn(0, endMs - startMs)) * 1_000L
        writeMotionPhoto(cover, motion, motionPhoto, presentationUs)

        // Keep a private, share-ready MP4. It does not create a second visible
        // gallery item, but FileProvider lets WeChat, Douyin and other apps read it.
        val shareDirectory = File(context.filesDir, "afterframe/exports").apply { mkdirs() }
        val shareVideo = File(shareDirectory, "$baseName.mp4")
        motion.copyTo(shareVideo, overwrite = false)

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
            return mapOf(
                "liveUri" to motionPhotoUri.toString(),
                "galleryUri" to shareVideoUri.toString(),
                "coverUri" to motionPhotoUri.toString(),
                "displayName" to baseName,
                "albumName" to "AfterFrame",
            )
        } catch (error: Exception) {
            published.asReversed().forEach(::removePublished)
            shareVideo.delete()
            throw error
        }
    }

    private fun writeMotionPhoto(
        cover: File,
        motion: File,
        destination: File,
        presentationTimestampUs: Long,
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
                  Camera:MotionPhoto="1"
                  Camera:MotionPhotoVersion="1"
                  Camera:MotionPhotoPresentationTimestampUs="$presentationTimestampUs">
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
