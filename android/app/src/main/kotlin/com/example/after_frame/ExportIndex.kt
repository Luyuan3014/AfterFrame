package com.example.after_frame

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import java.io.File

/** Durable work index with a MediaStore reconciliation fallback. */
class ExportIndex(private val context: Context) :
    SQLiteOpenHelper(context, "afterframe_works.db", null, 1) {
    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE works (
              live_uri TEXT PRIMARY KEY,
              gallery_uri TEXT NOT NULL,
              cover_path TEXT NOT NULL,
              display_name TEXT NOT NULL,
              created_at INTEGER NOT NULL,
              share_mime_type TEXT NOT NULL
            )
            """.trimIndent(),
        )
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) = Unit

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
            },
            SQLiteDatabase.CONFLICT_REPLACE,
        )
    }

    fun listAndReconcile(): List<Map<String, Any>> {
        val indexed = linkedMapOf<String, Map<String, Any>>()
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
                val coverPath = cursor.getString(cursor.getColumnIndexOrThrow("cover_path"))
                if (!File(coverPath).exists()) continue
                val liveUri = cursor.getString(cursor.getColumnIndexOrThrow("live_uri"))
                indexed[liveUri] = mapOf(
                    "liveUri" to liveUri,
                    "galleryUri" to cursor.getString(cursor.getColumnIndexOrThrow("gallery_uri")),
                    "coverPath" to coverPath,
                    "displayName" to cursor.getString(cursor.getColumnIndexOrThrow("display_name")),
                    "createdAt" to cursor.getLong(cursor.getColumnIndexOrThrow("created_at")),
                    "shareMimeType" to cursor.getString(cursor.getColumnIndexOrThrow("share_mime_type")),
                )
            }
        }
        recoverFromMediaStore().forEach { recovered ->
            indexed.putIfAbsent(recovered.getValue("liveUri") as String, recovered)
        }
        return indexed.values.sortedByDescending { it.getValue("createdAt") as Long }
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
                val uri = Uri.withAppendedPath(collection, cursor.getLong(idColumn).toString())
                val name = cursor.getString(nameColumn)
                val cover = persistentCover(uri, name)
                recovered += mapOf(
                    "liveUri" to uri.toString(),
                    "galleryUri" to uri.toString(),
                    "coverPath" to cover.absolutePath,
                    "displayName" to name.removeSuffix("MP.jpg"),
                    "createdAt" to cursor.getLong(dateColumn) * 1_000L,
                    "shareMimeType" to "image/jpeg",
                )
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
}
