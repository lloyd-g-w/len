/// Runs read-only queries off the UI thread (`queryInBackground`): natively
/// on a worker isolate over a connection of its own to the database file;
/// on the web (one connection, no isolates sharing it) on the UI thread,
/// after the current frame.
library;

export 'background_query_native.dart' if (dart.library.js_interop) 'background_query_web.dart';
