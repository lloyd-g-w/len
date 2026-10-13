/// Chooses where pulled pages are decoded (`decodePulled`): natively in a
/// worker isolate, so a first sync of a large library never parses on the
/// UI thread; on the web (no shared-memory isolates) on the UI thread.
library;

export 'pull_decoder_native.dart' if (dart.library.js_interop) 'pull_decoder_web.dart';
