/// Opens SQLite connections on every platform: FFI (bundled native SQLite)
/// on Android/Linux/Windows, WebAssembly + IndexedDB persistence on the web.
library;

export 'sqlite_connection_native.dart'
    if (dart.library.js_interop) 'sqlite_connection_web.dart';
