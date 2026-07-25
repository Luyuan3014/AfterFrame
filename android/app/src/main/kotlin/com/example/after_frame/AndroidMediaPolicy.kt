package com.example.after_frame

import android.Manifest

/** API-level media policy kept separate so instrumentation can verify every branch. */
object AndroidMediaPolicy {
    fun videoPermissions(sdk: Int): Array<String> = when {
        sdk >= 34 -> arrayOf(
            Manifest.permission.READ_MEDIA_VIDEO,
            Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED,
        )
        sdk >= 33 -> arrayOf(Manifest.permission.READ_MEDIA_VIDEO)
        sdk <= 28 -> arrayOf(
            Manifest.permission.READ_EXTERNAL_STORAGE,
            Manifest.permission.WRITE_EXTERNAL_STORAGE,
        )
        else -> arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)
    }

    fun usesScopedMediaStore(sdk: Int): Boolean = sdk >= 29
}
