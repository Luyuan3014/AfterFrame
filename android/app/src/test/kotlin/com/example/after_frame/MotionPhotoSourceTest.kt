package com.example.after_frame

import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.file.Files
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class MotionPhotoSourceTest {
    @Test
    fun `google motion photo xmp locates the trailing payload`() {
        val video = "ftypdata".toByteArray()
        val header = jpegWithXmp(
            """<rdf:Description Camera:MotionPhoto="1"><Container:Item Item:Mime="video/mp4" Item:Semantic="MotionPhoto" Item:Length="${video.size}"/></rdf:Description>""",
        )
        val payload = MotionPhotoSource.inspectHeader(header + video, (header.size + video.size).toLong())

        assertEquals(header.size.toLong(), payload?.offset)
        assertEquals(video.size.toLong(), payload?.length)
    }

    @Test
    fun `micro video offset is measured from the end of the file`() {
        val video = ByteArray(48) { 7 }
        val header = jpegWithXmp("""GCamera:MicroVideo="1" GCamera:MicroVideoOffset="${video.size}" """)
        val payload = MotionPhotoSource.inspectHeader(header + video, (header.size + video.size).toLong())

        assertEquals(header.size.toLong(), payload?.offset)
        assertEquals(video.size.toLong(), payload?.length)
    }

    @Test
    fun `a still jpeg is not treated as live motion`() {
        val jpeg = jpegWithXmp("""<rdf:Description dc:title="still"/>""")
        assertNull(MotionPhotoSource.inspectHeader(jpeg, jpeg.size.toLong()))
        assertTrue(!MotionPhotoSource.headerSuggestsMotion(jpeg))
    }

    @Test
    fun `extract copies only the trailing motion bytes`() {
        val sandbox = Files.createTempDirectory("afterframe-motion-test")
        try {
            val video = "ftypLIVE!!".toByteArray()
            val source = sandbox.resolve("MVIMG_001.jpg").toFile()
            val xmp = """<Container:Item Item:Mime="video/mp4" Item:Semantic="MotionPhoto" Item:Length="${video.size}"/>"""
            source.writeBytes(jpegWithXmp(xmp) + video)
            val destination = File(sandbox.toFile(), "out.mp4")

            MotionPhotoSource.extract(source, destination)

            assertTrue(destination.exists())
            assertEquals("ftypLIVE!!", destination.readText())
        } finally {
            sandbox.toFile().deleteRecursively()
        }
    }

    @Test
    fun `camera filenames are recognized without opening the file`() {
        assertTrue(MotionPhotoSource.looksLikeMotionName("MVIMG_20240101_120000.jpg"))
        assertTrue(MotionPhotoSource.looksLikeMotionName("PXL_20240101_120000.MP.jpg"))
        assertTrue(MotionPhotoSource.looksLikeMotionName("IMG_001_MP.jpg"))
        assertTrue(!MotionPhotoSource.looksLikeMotionName("IMG_001.jpg"))
    }

    private fun jpegWithXmp(xmp: String): ByteArray {
        val namespace = "http://ns.adobe.com/xap/1.0/\u0000".toByteArray(Charsets.US_ASCII)
        val xml = xmp.toByteArray(Charsets.UTF_8)
        val payload = namespace + xml
        val length = ByteBuffer.allocate(2).order(ByteOrder.BIG_ENDIAN).putShort((payload.size + 2).toShort()).array()
        return byteArrayOf(0xFF.toByte(), 0xD8.toByte(), 0xFF.toByte(), 0xE1.toByte()) +
            length +
            payload +
            byteArrayOf(0xFF.toByte(), 0xD9.toByte())
    }
}
