/// Starts workers that apply pulled pages off the UI isolate
/// (`startPullWorker`): natively over a second connection to the database
/// file; on the web (one connection, no isolates sharing it) never.
library;

export 'pull_worker_native.dart' if (dart.library.js_interop) 'pull_worker_web.dart';
