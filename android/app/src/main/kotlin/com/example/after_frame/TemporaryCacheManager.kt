package com.example.after_frame

import java.io.File

/** Owns only disposable files below cacheDir/afterframe. */
internal class TemporaryCacheManager(cacheDirectory: File) {
    private val cacheRoot = cacheDirectory.canonicalFile
    private val root = File(cacheRoot, DIRECTORY_NAME).canonicalFile

    init {
        require(root.parentFile == cacheRoot && root.name == DIRECTORY_NAME) {
            "Temporary cache root escaped the app cache directory"
        }
    }

    fun usage(): Map<String, Long> {
        if (!root.exists()) return emptyUsage()
        var bytes = 0L
        var files = 0L
        root.walkTopDown().forEach { file ->
            if (file.isFile) {
                bytes += file.length().coerceAtLeast(0L)
                files += 1
            }
        }
        return mapOf("bytes" to bytes, "files" to files)
    }

    fun clear() {
        if (root.exists() && !root.deleteRecursively()) {
            throw IllegalStateException("Unable to clear temporary cache")
        }
        check(root.mkdirs() || root.isDirectory) {
            "Unable to recreate temporary cache directory"
        }
    }

    private fun emptyUsage() = mapOf("bytes" to 0L, "files" to 0L)

    private companion object {
        const val DIRECTORY_NAME = "afterframe"
    }
}
