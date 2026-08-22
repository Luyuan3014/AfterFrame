package com.example.after_frame

import android.Manifest
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AndroidMediaPolicyInstrumentedTest {
    @Test
    fun api28UsesLegacyReadWriteAndFilePublishing() {
        assertArrayEquals(
            arrayOf(
                Manifest.permission.READ_EXTERNAL_STORAGE,
                Manifest.permission.WRITE_EXTERNAL_STORAGE,
            ),
            AndroidMediaPolicy.videoPermissions(28),
        )
        assertFalse(AndroidMediaPolicy.usesScopedMediaStore(28))
    }

    @Test
    fun api29UsesLegacyReadAndScopedMediaStore() {
        assertArrayEquals(
            arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE),
            AndroidMediaPolicy.videoPermissions(29),
        )
        assertTrue(AndroidMediaPolicy.usesScopedMediaStore(29))
    }

    @Test
    fun api33UsesReadMediaVideoAndImages() {
        assertArrayEquals(
            arrayOf(
                Manifest.permission.READ_MEDIA_VIDEO,
                Manifest.permission.READ_MEDIA_IMAGES,
            ),
            AndroidMediaPolicy.videoPermissions(33),
        )
        assertTrue(AndroidMediaPolicy.usesScopedMediaStore(33))
    }

    @Test
    fun api34SupportsFullAndUserSelectedVisualAccess() {
        assertArrayEquals(
            arrayOf(
                Manifest.permission.READ_MEDIA_VIDEO,
                Manifest.permission.READ_MEDIA_IMAGES,
                Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED,
            ),
            AndroidMediaPolicy.videoPermissions(34),
        )
        assertTrue(AndroidMediaPolicy.usesScopedMediaStore(34))
    }
}
