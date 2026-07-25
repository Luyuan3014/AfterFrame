package com.example.after_frame

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.util.Log
import androidx.core.content.FileProvider
import java.io.File
import java.io.RandomAccessFile

/** Durable work index with a MediaStore reconciliation fallback. */
class ExportIndex(private val context: Context) :
    SQLiteOpenHelper(context, "afterframe_works.db", null, 2) {
    private val tag = "AfterFrameExportIndex"
    private data class IndexedWork(
        val liveUri: String,
        val galleryUri: String,
        val coverPath: String,
        val displayName: String,
        val createdAt: Long,
        val shareMimeType: String,
        val deleting: Boolean,
    )

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE works (
              live_uri TEXT PRIMARY KEY,
              gallery_uri TEXT NOT NULL,
              cover_path TEXT NOT NULL,
              display_name TEXT NOT NULL,
              created_at INTEGER NOT NULL,
              share_mime_type TEXT NOT NULL,
              deleting INTEGER NOT NULL DEFAULT 0
            )
            """.trimIndent(),
        )
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        if (oldVersion < 2) {
            db.execSQL("ALTER TABLE works ADD COLUMN deleting INTEGER NOT NULL DEFAULT 0")
        }
    }

    fun save(item: Map<String, String>) {
        writableDatabase.insertWithOnConflict(
            "works",
            null,
            ContentValues().apply {
                put("live_uri", item.getValue("liveUri"))
                put("gallery_uri", item.getValue("galleryUri"))
                put("cover_path", item.getValue("coverPath"))
                put("display_name", item.getValue("displayName"))
                put("created_at", item.getValue("createdAt").toLong())
                put("share_mime_type", item.getValue("shareMimeType"))
                put("deleting", 0)
            },
            SQLiteDatabase.CONFLICT_REPLACE,
        )
    }

    fun listAndReconcile(): List<Map<String, Any>> {
        val indexed = linkedMapOf<String, Map<String, Any>>()
        val records = mutableListOf<IndexedWork>()
        readableDatabase.query(
            "works",
            null,
            null,
            null,
            null,
            null,
            "created_at DESC",
        ).use { cursor ->
            while (cursor.moveToNext()) {
                records += IndexedWork(
                    liveUri = cursor.getString(cursor.getColumnIndexOrThrow("live_uri")),
                    galleryUri = cursor.getString(cursor.getColumnIndexOrThrow("gallery_uri")),
                    coverPath = cursor.getString(cursor.getColumnIndexOrThrow("cover_path")),
                    displayName = cursor.getString(cursor.getColumnIndexOrThrow("display_name")),
                    createdAt = cursor.getLong(cursor.getColumnIndexOrThrow("created_at")),
                    shareMimeType = cursor.getString(cursor.getColumnIndexOrThrow("share_mime_type")),
                    deleting = cursor.getInt(cursor.getColumnIndexOrThrow("deleting")) != 0,
                )
            }
        }
        records.forEach { record ->
            if (record.deleting) {
                try {
                    deletePublicMedia(record.liveUri)
                    completeDelete(record.liveUri, record.coverPath, record.displayName)
                } catch (error: Exception) {
                    Log.w(tag, "Will retry interrupted work deletion: ${record.liveUri}", error)
                }
                return@forEach
            }
            if (!mediaExists(record.liveUri)) {
                completeDelete(record.liveUri, record.coverPath, record.displayName)
                return@forEach
            }
            if (!File(record.coverPath).exists()) return@forEach
            indexed[record.liveUri] = mapOf(
                "liveUri" to record.liveUri,
                "galleryUri" to record.galleryUri,
                "coverPath" to record.coverPath,
                "displayName" to record.displayName,
                "createdAt" to record.createdAt,
                "shareMimeType" to record.shareMimeType,
            )
        }
        recoverFromMediaStore().forEach { recovered ->
            val liveUri = recovered.getValue("liveUri") as String
            val current = indexed[liveUri]
            if (current == null || current["shareMimeType"] != "video/mp4") {
                indexed[liveUri] = recovered
                save(recovered.mapValues { it.value.toString() })
            }
        }
        return indexed.values.sortedByDescending { it.getValue("createdAt") as Long }
    }

    /** Deletes the public Motion Photo and every private file owned by a work. */
    fun delete(liveUri: String, coverPathHint: String?, displayNameHint: String?) {
        var coverPath: String? = coverPathHint?.takeIf(String::isNotBlank)
        var displayName: String? = displayNameHint?.takeIf(String::isNotBlank)
        readableDatabase.query(
            "works",
            arrayOf("cover_path", "display_name"),
            "live_uri = ?",
            arrayOf(liveUri),
            null,
            null,
            null,
        ).use { cursor ->
            if (cursor.moveToFirst()) {
                coverPath = cursor.getString(0)
                displayName = cursor.getString(1)
            }
        }

        // Persist intent before touching MediaStore. If the process is killed
        // between steps, listAndReconcile finishes this idempotently next time.
        writableDatabase.update(
            "works",
            ContentValues().apply { put("deleting", 1) },
            "live_uri = ?",
            arrayOf(liveUri),
        )
        try {
            deletePublicMedia(liveUri)
        } catch (error: Exception) {
            writableDatabase.update(
                "works",
                ContentValues().apply { put("deleting", 0) },
                "live_uri = ?",
                arrayOf(liveUri),
            )
            throw error
        }
        completeDelete(liveUri, coverPath, displayName)
    }

    private fun completeDelete(liveUri: String, coverPath: String?, displayName: String?) {
        // Missing files are already in the desired state, so every step is safe
        // to repeat after a crash or an external gallery deletion.
        val coverRemoved = coverPath?.let { deletePrivateFile(File(it)) } ?: true
        val videoRemoved = displayName?.let { name ->
            deletePrivateFile(File(context.filesDir, "afterframe/exports/$name.mp4"))
        } ?: true
        if (coverRemoved && videoRemoved) {
            writableDatabase.delete("works", "live_uri = ?", arrayOf(liveUri))
        } else {
            writableDatabase.update(
                "works",
                ContentValues().apply { put("deleting", 1) },
                "live_uri = ?",
                arrayOf(liveUri),
            )
        }
    }

    private fun deletePublicMedia(liveUri: String) {
        val uri = Uri.parse(liveUri)
        if (uri.scheme == "content" && mediaExists(liveUri)) {
            val removed = context.contentResolver.delete(uri, null, null)
            check(removed > 0 || !mediaExists(liveUri)) {
                "MediaStore did not delete work: $uri"
            }
        }
    }

    private fun deletePrivateFile(file: File): Boolean {
        val deleted = !file.exists() || file.delete()
        if (!deleted) {
            // Keep the tombstone for a later retry, but never show the deleted
            // work again merely because a private file is temporarily busy.
            Log.w(tag, "Unable to delete private work file: ${file.absolutePath}")
        }
        return deleted
    }

    private fun mediaExists(value: String): Boolean {
        val uri = runCatching { Uri.parse(value) }.getOrNull() ?: return false
        if (uri.scheme == "file") return uri.path?.let(::File)?.exists() == true
        if (uri.scheme.isNullOrEmpty()) return File(value).exists()
        if (uri.scheme != "content") return true
        return try {
            context.contentResolver.query(uri, arrayOf(MediaStore.MediaColumns._ID), null, null, null)
                ?.use { it.moveToFirst() } == true
        } catch (error: SecurityException) {
            // Do not discard a record merely because Android temporarily denies
            // querying it. The explicit delete path will surface that failure.
            Log.w(tag, "Unable to verify work URI: $uri", error)
            true
        } catch (error: IllegalArgumentException) {
            false
        } catch (error: Exception) {
            Log.w(tag, "Unable to verify work URI: $uri", error)
            true
        }
    }

    private fun recoverFromMediaStore(): List<Map<String, Any>> {
        val collection = MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        val projection = arrayOf(
            MediaStore.Images.Media._ID,
            MediaStore.Images.Media.DISPLAY_NAME,
            MediaStore.Images.Media.DATE_ADDED,
        )
        val selection: String
        val args: Array<String>
        if (Build.VERSION.SDK_INT >= 29) {
            selection = "${MediaStore.Images.Media.RELATIVE_PATH} LIKE ? AND ${MediaStore.Images.Media.DISPLAY_NAME} LIKE ?"
            args = arrayOf("%DCIM/AfterFrame%", "%MP.jpg")
        } else {
            @Suppress("DEPRECATION")
            selection = "${MediaStore.Images.Media.DATA} LIKE ? AND ${MediaStore.Images.Media.DISPLAY_NAME} LIKE ?"
            args = arrayOf("%/DCIM/AfterFrame/%", "%MP.jpg")
        }
        val recovered = mutableListOf<Map<String, Any>>()
        context.contentResolver.query(collection, projection, selection, args, null)?.use { cursor ->
            val idColumn = cursor.getColumnIndexOrThrow(MediaStore.Images.Media._ID)
            val nameColumn = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.DISPLAY_NAME)
            val dateColumn = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.DATE_ADDED)
            while (cursor.moveToNext()) {
                runCatching {
                    val uri = Uri.withAppendedPath(collection, cursor.getLong(idColumn).toString())
                    val name = cursor.getString(nameColumn)
                    val cover = persistentCover(uri, name)
                    val video = runCatching { persistentVideo(cover, name) }.getOrNull()
                    mapOf(
                        "liveUri" to uri.toString(),
                        "galleryUri" to (video?.let {
                            FileProvider.getUriForFile(
                                context,
                                "${context.packageName}.fileprovider",
                                it,
                            ).toString()
                        } ?: uri.toString()),
                        "coverPath" to cover.absolutePath,
                        "displayName" to name.removeSuffix("MP.jpg"),
                        "createdAt" to cursor.getLong(dateColumn) * 1_000L,
                        "shareMimeType" to if (video == null) "image/jpeg" else "video/mp4",
                    )
                }.onSuccess(recovered::add).onFailure { error ->
                    Log.w(tag, "Skipping an unreadable recovered Motion Photo", error)
                }
            }
        }
        return recovered
    }

    private fun persistentCover(uri: Uri, name: String): File {
        val directory = File(context.filesDir, "afterframe/covers").apply { mkdirs() }
        val destination = File(directory, "recovered_${name.hashCode()}.jpg")
        if (!destination.exists() || destination.length() == 0L) {
            context.contentResolver.openInputStream(uri).use { input ->
                requireNotNull(input) { "无法读取 MediaStore 作品" }
                destination.outputStream().use(input::copyTo)
            }
        }
        return destination
    }

    /** Rebuilds the private preview MP4 from the trailing Motion Photo payload. */
    private fun persistentVideo(motionPhoto: File, name: String): File {
        val directory = File(context.filesDir, "afterframe/exports").apply { mkdirs() }
        val displayName = name.removeSuffix("MP.jpg")
        val destination = File(directory, "$displayName.mp4")
        if (destination.exists() && destination.length() > 0L) return destination

        val headerSize = minOf(motionPhoto.length(), 1_048_576L).toInt()
        val header = ByteArray(headerSize)
        RandomAccessFile(motionPhoto, "r").use { source -> source.readFully(header) }
        val xmp = header.toString(Charsets.ISO_8859_1)
        val videoLength = Regex("Item:Length=\"(\\d+)\"")
            .findAll(xmp)
            .mapNotNull { it.groupValues[1].toLongOrNull() }
            .lastOrNull()
            ?: error("Motion Photo XMP does not declare a video length")
        require(videoLength in 1 until motionPhoto.length()) { "Invalid Motion Photo video length" }

        val pending = File(directory, ".${destination.name}.${System.nanoTime()}.tmp")
        try {
            RandomAccessFile(motionPhoto, "r").use { source ->
                source.seek(motionPhoto.length() - videoLength)
                pending.outputStream().use { output ->
                    val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                    var remaining = videoLength
                    while (remaining > 0) {
                        val read = source.read(buffer, 0, minOf(buffer.size.toLong(), remaining).toInt())
                        check(read > 0) { "Unexpected end of Motion Photo" }
                        output.write(buffer, 0, read)
                        remaining -= read
                    }
                }
            }
            check(pending.length() == videoLength && pending.renameTo(destination)) {
                "Unable to save recovered Motion Photo video"
            }
        } finally {
            pending.delete()
        }
        return destination
    }
}
