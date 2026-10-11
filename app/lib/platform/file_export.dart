/// Hands exported files to the user: `saveOrShare` (one file) and
/// `saveOrShareAll` (several, e.g. one PNG per page) open a save dialog on
/// desktop, the share sheet on Android and iOS and download in browsers.
library;

export 'file_export_native.dart' if (dart.library.js_interop) 'file_export_web.dart';
