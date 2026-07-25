package com.example.after_frame

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.antonkarpenko.ffmpegkit.FFmpegKit
import com.antonkarpenko.ffmpegkit.FFprobeKit
import com.antonkarpenko.ffmpegkit.ReturnCode
import java.io.File
import java.io.RandomAccessFile
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Proves that the packaged native ABI can encode, probe and decode on-device. */
@RunWith(AndroidJUnit4::class)
class FfmpegRuntimeInstrumentedTest {
    @Test
    fun packagedRuntimeEncodesProbesAndExtractsAFrame() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val directory = File(context.cacheDir, "ffmpeg-runtime-test").apply { mkdirs() }
        val video = File(directory, "fixture.mp4").apply { delete() }
        val frame = File(directory, "frame.jpg").apply { delete() }

        try {
            var encode = FFmpegKit.executeWithArguments(
                arrayOf(
                    "-y", "-f", "lavfi", "-i", "color=c=0x24342d:s=320x240:r=30:d=1",
                    "-c:v", "h264_mediacodec", "-b:v", "1M", "-pix_fmt", "yuv420p",
                    "-movflags", "+faststart", video.absolutePath,
                ),
            )
            val hardwareProbe = FFprobeKit.getMediaInformation(video.absolutePath)
            val hardwareHasVideo = ReturnCode.isSuccess(hardwareProbe.returnCode) &&
                hardwareProbe.mediaInformation?.streams?.any { it.type == "video" } == true
            if (!ReturnCode.isSuccess(encode.returnCode) || !hardwareHasVideo) {
                video.delete()
                encode = FFmpegKit.executeWithArguments(
                    arrayOf(
                        "-y", "-f", "lavfi", "-i", "color=c=0x24342d:s=320x240:r=30:d=1",
                        "-c:v", "mpeg4", "-q:v", "3", "-pix_fmt", "yuv420p",
                        "-movflags", "+faststart", video.absolutePath,
                    ),
                )
            }
            assertTrue(encode.allLogsAsString, ReturnCode.isSuccess(encode.returnCode))
            assertTrue(video.length() > 0L)

            val probe = FFprobeKit.getMediaInformation(video.absolutePath)
            assertTrue(probe.allLogsAsString, ReturnCode.isSuccess(probe.returnCode))
            assertTrue(
                probe.mediaInformation.allProperties.toString(),
                probe.mediaInformation.streams.any {
                    it.type == "video" && it.width == 320L && it.height == 240L
                },
            )

            val extract = FFmpegKit.executeWithArguments(
                arrayOf("-y", "-i", video.absolutePath, "-frames:v", "1", "-q:v", "2", frame.absolutePath),
            )
            assertTrue(extract.allLogsAsString, ReturnCode.isSuccess(extract.returnCode))
            assertTrue(frame.length() > 0L)

            val renderer = FfmpegRenderEngine(context)
            val gif = File(directory, "fixture.gif")
            val webp = File(directory, "fixture.webp")
            renderer.renderAnimated(video, "gif", gif)
            renderer.renderAnimated(video, "webp", webp)
            assertTrue(gif.length() > 0L)
            assertTrue(webp.length() > 0L)

            val motionPhoto = File(directory, "fixtureMP.jpg")
            MotionPhotoPackager.write(frame, video, motionPhoto, 500_000L, true)
            val trailer = ByteArray(video.length().toInt())
            RandomAccessFile(motionPhoto, "r").use { file ->
                file.seek(file.length() - trailer.size)
                file.readFully(trailer)
            }
            assertArrayEquals(video.readBytes(), trailer)
            val headerBytes = ByteArray(minOf(motionPhoto.length(), 32_768L).toInt())
            motionPhoto.inputStream().use { it.read(headerBytes) }
            val header = headerBytes.toString(Charsets.ISO_8859_1)
            assertTrue(header.contains("Camera:MotionPhoto=\"1\""))
            assertTrue(header.contains("Item:Length=\"${video.length()}\""))
        } finally {
            directory.deleteRecursively()
        }
    }
}
