package com.example.after_frame

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class UpdatePolicyTest {
    @Test
    fun onlyStrictlyHigherVersionCodesAreUpgrades() {
        assertFalse(UpdatePolicy.isUpgrade(6, 5))
        assertFalse(UpdatePolicy.isUpgrade(6, 6))
        assertTrue(UpdatePolicy.isUpgrade(6, 7))
    }

    @Test
    fun metadataNormalizerRemovesUtf8Bom() {
        assertEquals("{\"schemaVersion\":1}", UpdatePolicy.normalizeMetadata("\uFEFF  {\"schemaVersion\":1}"))
    }

    @Test
    fun officialGiteeRawRedirectHostIsTrusted() {
        UpdatePolicy.requireTrustedGiteeUrl(
            "https://raw.giteeusercontent.com/luyuan567/after_frame_update/raw/master/update.json",
        )
    }

    @Test(expected = IllegalArgumentException::class)
    fun lookalikeGiteeHostIsRejected() {
        UpdatePolicy.requireTrustedGiteeUrl("https://gitee.com.evil.example/update.json")
    }

    @Test
    fun sha1ParserAcceptsStandardFormatAndChecksFileName() {
        val hash = "0123456789abcdef0123456789abcdef01234567"
        assertEquals(hash, UpdatePolicy.parseSha1("$hash  app-arm64-v8a-release.apk\n", "app-arm64-v8a-release.apk"))
    }

    @Test(expected = IllegalArgumentException::class)
    fun sha1ParserRejectsAnotherAbiFile() {
        UpdatePolicy.parseSha1(
            "0123456789abcdef0123456789abcdef01234567  app-x86_64-release.apk",
            "app-arm64-v8a-release.apk",
        )
    }
}
