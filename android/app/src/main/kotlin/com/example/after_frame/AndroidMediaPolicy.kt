package com.example.after_frame

import android.Manifest

/** API-level media policy kept separate so instrumentation can verify every branch. */
object AndroidMediaPolicy {
    fun libraryPermissions(sdk: Int): Array<String> = when {
        sdk >= 34 -> arrayOf(
            Manifest.permission.READ_MEDIA_VIDEO,
            Manifest.permission.READ_MEDIA_IMAGES,
            Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED,
        )
        sdk >= 33 -> arrayOf(
            Manifest.permission.READ_MEDIA_VIDEO,
            Manifest.permission.READ_MEDIA_IMAGES,
        )
        sdk <= 28 -> arrayOf(
            Manifest.permission.READ_EXTERNAL_STORAGE,
            Manifest.permission.WRITE_EXTERNAL_STORAGE,
        )
        else -> arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)
    }

    /** @deprecated Use [libraryPermissions]; kept as a compatible alias. */
    fun videoPermissions(sdk: Int): Array<String> = libraryPermissions(sdk)

    fun usesScopedMediaStore(sdk: Int): Boolean = sdk >= 29
}
