package dev.len.len

/**
 * The plain rules of [IncomingFiles] (no Android types, so they run in the
 * JVM unit tests: `tool/wet_ink_check/unit_test.sh`).
 */
object IncomingNames {
    private val unsafe = Regex("[\\\\:*?\"<>|\\x00-\\x1f]")

    /**
     * A file name for a copy of an incoming file: no path (names come from
     * other apps), no characters file systems reject, not hidden, at most
     * 120 characters (keeping the end, where the extension is).
     */
    fun safe(name: String): String {
        val clean = name.substringAfterLast('/').replace(unsafe, "_")
        return clean.trim().trimStart('.').ifEmpty { "file" }.takeLast(120)
    }

    /** Only `content:` URIs are read: other apps cannot send `file:` ones. */
    fun acceptsScheme(scheme: String?): Boolean = scheme == "content"
}
