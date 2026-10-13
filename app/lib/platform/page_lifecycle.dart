/// Saves pending writes when the page may go away (`watchPageLifecycle`):
/// on the web, flushes when the tab is hidden or unloaded, retries failed
/// writes when it is shown again, and asks before closing while a write is
/// still pending. Native writes are synchronous: nothing to do.
library;

export 'page_lifecycle_native.dart' if (dart.library.js_interop) 'page_lifecycle_web.dart';
