package com.example.after_frame

import org.junit.Assert.assertArrayEquals
import org.junit.Test

class MediaClipWindowsTest {
    @Test
    fun keepsTheRequestedWindowWhenDurationIsUnknown() {
        assertArrayEquals(
            longArrayOf(200L, 1800L),
            MediaClipWindows.clamp(200L, 1800L, 0L),
        )
    }

    @Test
    fun clampsPastTheRealEndOfAnExtractedLiveClip() {
        assertArrayEquals(
            longArrayOf(0L, 1467L),
            MediaClipWindows.clamp(0L, 3000L, 1467L),
        )
    }

    @Test
    fun keepsAWindowThatAlreadyFits() {
        assertArrayEquals(
            longArrayOf(120L, 980L),
            MediaClipWindows.clamp(120L, 980L, 1500L),
        )
    }
}
