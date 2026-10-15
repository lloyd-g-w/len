package one.mixin.pasteboard

import android.content.Context
import androidx.core.content.FileProvider

/**
 * Serves the images "write" puts on the clipboard (Len's addition). Its own class, so the
 * manifest entry doesn't clash with another library's `FileProvider`.
 */
class PasteboardFileProvider : FileProvider() {
    companion object {
        /** Folder in the cache that holds the clipboard's image. */
        const val DIRECTORY = "pasteboard"

        fun authority(context: Context) = "${context.packageName}.pasteboard"
    }
}
