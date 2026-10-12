/// Opens the directory for recordings in progress (`openRecordingSpool`):
/// `<app support>/recording` natively, none in browsers.
library;

export 'spool_storage_native.dart' if (dart.library.js_interop) 'spool_storage_web.dart';
