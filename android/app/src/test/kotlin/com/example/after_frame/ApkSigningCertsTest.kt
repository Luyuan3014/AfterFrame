package com.example.after_frame

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.File

class ApkSigningCertsTest {
    @Test
    fun readsV2OnlyReleaseApkCertificateDigest() {
        val apk = File(System.getenv("TEMP") ?: System.getProperty("java.io.tmpdir"), "afterframe-x86_64-0.7.5.apk")
        assumeTrue("Release APK fixture must exist at ${apk.absolutePath}", apk.isFile && apk.length() > 1_000_000L)

        val digests = ApkSigningCerts.sha256Digests(apk)
        assertTrue(digests.isNotEmpty())
        assertEquals(
            setOf("44b53270d49dfeaa53e775af479fb0622ef1589bd479cd62cc23dc0e841c2e21"),
            digests,
        )
    }
}
