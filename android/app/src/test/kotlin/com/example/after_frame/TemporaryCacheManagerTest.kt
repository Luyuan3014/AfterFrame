package com.example.after_frame

import java.nio.file.Files
import kotlin.io.path.createDirectories
import kotlin.io.path.createFile
import kotlin.io.path.writeBytes
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TemporaryCacheManagerTest {
    @Test
    fun `usage counts nested disposable files`() {
        val sandbox = Files.createTempDirectory("afterframe-cache-test")
        try {
            val cache = sandbox.resolve("cache").createDirectories()
            cache.resolve("afterframe/thumbnails").createDirectories()
            cache.resolve("afterframe/frames").createDirectories()
            cache.resolve("afterframe/thumbnails/a.jpg").writeBytes(ByteArray(7))
            cache.resolve("afterframe/frames/b.jpg").writeBytes(ByteArray(11))

            assertEquals(
                mapOf("bytes" to 18L, "files" to 2L),
                TemporaryCacheManager(cache.toFile()).usage(),
            )
        } finally {
            sandbox.toFile().deleteRecursively()
        }
    }

    @Test
    fun `clear preserves everything outside disposable root`() {
        val sandbox = Files.createTempDirectory("afterframe-cache-test")
        try {
            val cache = sandbox.resolve("cache").createDirectories()
            val disposable = cache.resolve("afterframe/frames/frame.jpg")
            disposable.parent.createDirectories()
            disposable.createFile()
            val unrelatedCache = cache.resolve("other-plugin/keep.bin")
            unrelatedCache.parent.createDirectories()
            unrelatedCache.createFile()
            val persistentWork = sandbox.resolve("files/afterframe/exports/work.mp4")
            persistentWork.parent.createDirectories()
            persistentWork.createFile()

            val manager = TemporaryCacheManager(cache.toFile())
            manager.clear()

            assertFalse(Files.exists(disposable))
            assertTrue(Files.isDirectory(cache.resolve("afterframe")))
            assertTrue(Files.exists(unrelatedCache))
            assertTrue(Files.exists(persistentWork))
            assertEquals(mapOf("bytes" to 0L, "files" to 0L), manager.usage())
        } finally {
            sandbox.toFile().deleteRecursively()
        }
    }
}
