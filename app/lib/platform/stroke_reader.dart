/// Chooses how surfaces are read for lazy loading (`openStrokeReader`):
/// natively on a background isolate with its own read-only SQLite
/// connection; on the web (no isolates sharing a database file) on the UI
/// thread through the fallback reader.
library;

export 'stroke_reader_native.dart' if (dart.library.js_interop) 'stroke_reader_web.dart';
