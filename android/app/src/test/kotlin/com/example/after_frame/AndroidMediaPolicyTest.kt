package com.example.after_frame

import android.Manifest
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AndroidMediaPolicyTest {
    @Test
    fun api33RequestsVideoAndImages() {
        assertArrayEquals(
            arrayOf(
                Manifest.permission.READ_MEDIA_VIDEO,
                Manifest.permission.READ_MEDIA_IMAGES,
            ),
            AndroidMediaPolicy.libraryPermissions(33),
        )
    }

    @Test
    fun api34AddsUserSelectedVisualAccess() {
        assertArrayEquals(
            arrayOf(
                Manifest.permission.READ_MEDIA_VIDEO,
                Manifest.permission.READ_MEDIA_IMAGES,
                Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED,
            ),
            AndroidMediaPolicy.libraryPermissions(34),
        )
    }

    @Test
    fun videoPermissionsRemainACompatibleAlias() {
        assertArrayEquals(
            AndroidMediaPolicy.libraryPermissions(29),
            AndroidMediaPolicy.videoPermissions(29),
        )
        assertTrue(AndroidMediaPolicy.usesScopedMediaStore(29))
    }
}
