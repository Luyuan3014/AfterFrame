package com.example.after_frame

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MediaExportPolicyTest {
    @Test
    fun goldfishEmulatorMustStageThreeCellExports() {
        assertTrue(
            MediaExportPolicy.limitedConcurrentDecoders(
                hardware = "goldfish",
                fingerprint = "google/sdk_gphone64_x86_64/emu64xa",
                model = "sdk_gphone64_x86_64",
            ),
        )
    }

    @Test
    fun aPhysicalPhoneKeepsOnePassCollage() {
        assertFalse(
            MediaExportPolicy.limitedConcurrentDecoders(
                hardware = "qcom",
                fingerprint = "google/shiba/shiba:16/BP2A.250605.031.A3",
                model = "Pixel 8",
            ),
        )
    }

    @Test
    fun codecNoMemoryIsTreatedAsDecoderPressure() {
        val error = IllegalStateException(
            "Media3 导出失败：Codec exception",
            RuntimeException("err 0xfffffff4/NO_MEMORY"),
        )
        assertTrue(MediaExportPolicy.decoderPressure(error))
        assertFalse(MediaExportPolicy.decoderPressure(IllegalStateException("封面不存在")))
    }
}
