/// Opens the app's blob storage (`openBlobBackend`): files on
/// Android/Linux/Windows, IndexedDB on the web.
library;

export 'blob_backend_native.dart' if (dart.library.js_interop) 'blob_backend_web.dart';
