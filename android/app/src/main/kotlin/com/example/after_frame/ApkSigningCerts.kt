package com.example.after_frame

import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.MessageDigest
import java.util.jar.JarFile

/**
 * Reads signer certificate digests from an on-disk APK.
 *
 * Release APKs built with modern AGP are often **v2-only** (no JAR v1
 * META-INF signatures). On several Android 13–16 builds,
 * [android.content.pm.PackageManager.getPackageArchiveInfo] then returns
 * PackageInfo with both `signingInfo` and legacy `signatures` empty, which
 * made AfterFrame treat a valid update as VERIFY_FAILED. Parsing the APK
 * Signing Block directly avoids that platform gap.
 */
internal object ApkSigningCerts {
    private const val EOCD_SIG = 0x06054b50
    private const val APK_SIG_BLOCK_MAGIC_HI = 0x3234206b636f6c42L // "Bloc 42"
    private const val APK_SIG_BLOCK_MAGIC_LO = 0x20676953204b5041L // "APK Sig "
    private const val V2_BLOCK_ID = 0x7109871a
    private val V3_BLOCK_ID = 0xf05368c0.toInt()
    private const val V31_BLOCK_ID = 0x1b93ad61

    fun sha256Digests(file: java.io.File): Set<String> {
        val fromBlock = digestsFromSigningBlock(file)
        if (fromBlock.isNotEmpty()) return fromBlock
        return digestsFromJarSigners(file)
    }

    private fun digestsFromJarSigners(file: java.io.File): Set<String> {
        JarFile(file, true).use { jar ->
            val entries = jar.entries()
            while (entries.hasMoreElements()) {
                val entry = entries.nextElement()
                if (entry.isDirectory) continue
                jar.getInputStream(entry).use { input ->
                    val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                    while (input.read(buffer) >= 0) {
                        // Drain fully so JarFile populates certificates.
                    }
                }
                val certificates = entry.certificates ?: continue
                if (certificates.isEmpty()) continue
                return certificates.map(::sha256).toSet()
            }
        }
        return emptySet()
    }

    private fun digestsFromSigningBlock(file: java.io.File): Set<String> {
        RandomAccessFile(file, "r").use { apk ->
            val eocd = findEocd(apk) ?: return emptySet()
            val centralDirOffset = u32(eocd, 16).toLong()
            if (centralDirOffset < 32L || centralDirOffset > apk.length()) return emptySet()
            val signingBlock = findApkSigningBlock(apk, centralDirOffset) ?: return emptySet()
            for (blockId in intArrayOf(V31_BLOCK_ID, V3_BLOCK_ID, V2_BLOCK_ID)) {
                val scheme = findSchemeBlock(signingBlock, blockId) ?: continue
                val digests = digestsFromSchemeBlock(scheme)
                if (digests.isNotEmpty()) return digests
            }
            return emptySet()
        }
    }

    private fun digestsFromSchemeBlock(scheme: ByteBuffer): Set<String> {
        val signers = lengthPrefixedSlice(scheme)
        val digests = linkedSetOf<String>()
        while (signers.hasRemaining()) {
            val signer = lengthPrefixedSlice(signers)
            val signedData = lengthPrefixedSlice(signer)
            // digests
            lengthPrefixedSlice(signedData)
            val certificates = lengthPrefixedSlice(signedData)
            while (certificates.hasRemaining()) {
                digests += sha256(lengthPrefixedBytes(certificates))
            }
        }
        return digests
    }

    private fun findEocd(apk: RandomAccessFile): ByteBuffer? {
        val fileLength = apk.length()
        if (fileLength < 22L) return null
        val maxComment = minOf(0xffffL, fileLength - 22L)
        var comment = 0L
        while (comment <= maxComment) {
            val eocdOffset = fileLength - 22L - comment
            apk.seek(eocdOffset)
            if (Integer.reverseBytes(apk.readInt()) != EOCD_SIG) {
                comment++
                continue
            }
            val buffer = ByteArray((22L + comment).toInt())
            apk.seek(eocdOffset)
            apk.readFully(buffer)
            val eocd = ByteBuffer.wrap(buffer).order(ByteOrder.LITTLE_ENDIAN)
            if (u16(eocd, 20).toLong() == comment) return eocd
            comment++
        }
        return null
    }

    private fun findApkSigningBlock(apk: RandomAccessFile, centralDirOffset: Long): ByteBuffer? {
        apk.seek(centralDirOffset - 24L)
        val footer = ByteArray(24)
        apk.readFully(footer)
        val footerBuf = ByteBuffer.wrap(footer).order(ByteOrder.LITTLE_ENDIAN)
        if (footerBuf.getLong(8) != APK_SIG_BLOCK_MAGIC_LO) return null
        if (footerBuf.getLong(16) != APK_SIG_BLOCK_MAGIC_HI) return null
        val blockSizeInFooter = footerBuf.getLong(0)
        if (blockSizeInFooter < 24L || blockSizeInFooter > Int.MAX_VALUE - 8L) return null
        val totalSize = blockSizeInFooter + 8L
        val blockOffset = centralDirOffset - totalSize
        if (blockOffset < 0L) return null
        apk.seek(blockOffset)
        val block = ByteArray(totalSize.toInt())
        apk.readFully(block)
        val buffer = ByteBuffer.wrap(block).order(ByteOrder.LITTLE_ENDIAN)
        if (buffer.getLong(0) != blockSizeInFooter) return null
        return buffer
    }

    private fun findSchemeBlock(signingBlock: ByteBuffer, blockId: Int): ByteBuffer? {
        // Pairs are uint64-length-prefixed (see ApkSigningBlockUtils in AOSP),
        // not uint32. Using the wrong width misaligns on every entry.
        val pairs = signingBlock.duplicate().order(ByteOrder.LITTLE_ENDIAN)
        pairs.position(8)
        pairs.limit(signingBlock.capacity() - 24)
        while (pairs.remaining() >= 8) {
            val lenLong = pairs.long
            if (lenLong < 4L || lenLong > Int.MAX_VALUE.toLong()) return null
            val len = lenLong.toInt()
            val nextEntryPos = pairs.position() + len
            if (len > pairs.remaining()) return null
            val id = pairs.int
            if (id == blockId) {
                val value = pairs.slice().order(ByteOrder.LITTLE_ENDIAN)
                value.limit(len - 4)
                pairs.position(nextEntryPos)
                return value
            }
            pairs.position(nextEntryPos)
        }
        return null
    }

    private fun lengthPrefixedSlice(source: ByteBuffer): ByteBuffer {
        val length = source.int
        require(length in 0..source.remaining()) { "Invalid length-prefixed slice" }
        val slice = source.slice().order(ByteOrder.LITTLE_ENDIAN)
        slice.limit(length)
        source.position(source.position() + length)
        return slice
    }

    private fun lengthPrefixedBytes(source: ByteBuffer): ByteArray {
        val length = source.int
        require(length in 0..source.remaining()) { "Invalid length-prefixed bytes" }
        val bytes = ByteArray(length)
        source.get(bytes)
        return bytes
    }

    private fun u16(buffer: ByteBuffer, offset: Int): Int =
        buffer.getShort(offset).toInt() and 0xffff

    private fun u32(buffer: ByteBuffer, offset: Int): Int = buffer.getInt(offset)

    private fun sha256(bytes: ByteArray): String =
        MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }

    private fun sha256(certificate: java.security.cert.Certificate): String =
        sha256(certificate.encoded)
}
