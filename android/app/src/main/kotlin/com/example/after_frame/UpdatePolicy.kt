package com.example.after_frame

import java.util.Locale
import java.net.URI

internal object UpdatePolicy {
    val supportedAbis = setOf("arm64-v8a", "armeabi-v7a", "x86_64")

    fun isUpgrade(currentVersionCode: Long, remoteVersionCode: Long): Boolean =
        remoteVersionCode > currentVersionCode

    fun normalizeMetadata(contents: String): String =
        contents.removePrefix("\uFEFF").trimStart()

    fun requireTrustedGiteeUrl(value: String) {
        val uri = URI(value)
        val host = uri.host?.lowercase(Locale.US).orEmpty()
        val trustedHost = host == "gitee.com" ||
            host.endsWith(".gitee.com") ||
            host == "raw.giteeusercontent.com"
        require(uri.scheme == "https" && trustedHost) {
            "Updates must use an HTTPS Gitee URL"
        }
        require(uri.userInfo == null) { "Credentials are not allowed in update URLs" }
    }

    fun requireSupportedAbi(abi: String): String {
        val normalized = abi.lowercase(Locale.US)
        require(normalized in supportedAbis) { "Unsupported installed ABI: $abi" }
        return normalized
    }

    fun parseSha1(contents: String, expectedFileName: String): String {
        val line = contents.lineSequence().map(String::trim).firstOrNull(String::isNotEmpty)
            ?: throw IllegalArgumentException("Empty SHA-1 file")
        val match = Regex("^([0-9a-fA-F]{40})(?:\\s+[*]?(.+))?$").matchEntire(line)
            ?: throw IllegalArgumentException("Invalid SHA-1 file")
        val fileName = match.groupValues[2].trim()
        require(fileName.isEmpty() || fileName == expectedFileName) {
            "SHA-1 file belongs to a different APK"
        }
        return match.groupValues[1].lowercase(Locale.US)
    }
}
