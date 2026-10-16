package dev.len.len

import java.io.InputStream
import java.io.OutputStream

/**
 * The plain-JVM half of printing (`PrintPlugin.kt`), unit tested without
 * Android: which pages a print asks for, and copying the PDF unless the
 * print is cancelled.
 *
 * The adapter always writes the whole PDF (cutting pages out of a PDF
 * needs a PDF library) and reports every page written; the print spooler
 * then drops the pages the user didn't choose before they reach the printer.
 */
object PrintPages {
    /** `PageRange.ALL_PAGES`'s end. */
    const val ALL_END = Int.MAX_VALUE

    /** `PrintDocumentInfo.PAGE_COUNT_UNKNOWN`. */
    const val UNKNOWN = -1

    /**
     * The zero-based [ranges] a print asks for in a PDF of [pageCount]
     * pages ([UNKNOWN] if it couldn't be counted), sorted and merged
     * (`ALL_PAGES`, start 0 to [ALL_END], becomes every page when the count
     * is known); null when they ask for nothing or for pages the PDF
     * doesn't have.
     */
    fun requested(ranges: List<IntRange>, pageCount: Int): List<IntRange>? {
        if (ranges.isEmpty() || pageCount == 0) return null
        val last = if (pageCount == UNKNOWN) ALL_END else pageCount - 1
        val clean = ranges.map { r ->
            if (r.first < 0 || r.last < r.first) return null
            if (r.first == 0 && r.last == ALL_END) 0..last
            else if (r.last > last) return null
            else r
        }.sortedBy { it.first }
        val merged = mutableListOf<IntRange>()
        for (r in clean) {
            val prev = merged.lastOrNull()
            if (prev != null && r.first <= prev.last.toLong() + 1) {
                merged[merged.size - 1] = prev.first..maxOf(prev.last, r.last)
            } else {
                merged.add(r)
            }
        }
        return merged
    }

    /**
     * Copies [input] to [output] in chunks, checking [cancelled] between
     * them; false (stopped part way) if the print was cancelled.
     */
    fun copyUnlessCancelled(
        input: InputStream,
        output: OutputStream,
        cancelled: () -> Boolean,
        chunk: Int = 64 * 1024,
    ): Boolean {
        val buffer = ByteArray(chunk)
        while (true) {
            if (cancelled()) return false
            val n = input.read(buffer)
            if (n < 0) break
            output.write(buffer, 0, n)
        }
        output.flush()
        return !cancelled()
    }
}
