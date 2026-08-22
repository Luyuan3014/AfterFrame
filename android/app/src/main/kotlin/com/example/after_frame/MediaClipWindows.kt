package com.example.after_frame

import kotlin.math.max
import kotlin.math.min

/** Clamps a Studio trim window to the real playable duration of a source. */
internal object MediaClipWindows {
    fun clamp(startMs: Long, endMs: Long, durationMs: Long): LongArray {
        require(endMs > startMs) { "结束时间必须晚于开始时间" }
        if (durationMs <= 0L) {
            return longArrayOf(startMs.coerceAtLeast(0L), endMs)
        }
        val limit = durationMs
        val requested = endMs - startMs
        val safeEnd = min(endMs, limit).coerceAtLeast(1L)
        val safeStart = startMs.coerceIn(0L, (safeEnd - 1L).coerceAtLeast(0L))
        if (safeEnd > safeStart) {
            return longArrayOf(safeStart, safeEnd)
        }
        val fallbackEnd = min(limit, max(1L, requested))
        return longArrayOf(0L, fallbackEnd)
    }
}
