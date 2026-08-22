package com.example.after_frame

/** Decides when a 3-cell collage must avoid opening three decoders at once. */
internal object MediaExportPolicy {
    fun limitedConcurrentDecoders(
        hardware: String,
        fingerprint: String,
        model: String,
    ): Boolean {
        val haystack = "$hardware $fingerprint $model".lowercase()
        return haystack.contains("goldfish") ||
            haystack.contains("ranchu") ||
            haystack.contains("emulator") ||
            haystack.contains("generic") ||
            haystack.contains("sdk_gphone")
    }

    fun decoderPressure(error: Throwable): Boolean {
        val blob = sequenceOf(error, error.cause)
            .filterNotNull()
            .flatMap { throwable ->
                sequenceOf(
                    throwable.message,
                    throwable.javaClass.simpleName,
                    throwable.cause?.message,
                )
            }
            .filterNotNull()
            .joinToString(" ")
            .lowercase()
        return blob.contains("no_memory") ||
            blob.contains("nomemory") ||
            blob.contains("0xfffffff4") ||
            blob.contains("codec exception") ||
            blob.contains("codecexception") ||
            blob.contains("failed to query component") ||
            error.cause is android.media.MediaCodec.CodecException
    }
}
