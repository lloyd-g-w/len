/// Hands an exported file to the user (`saveOrShare`): a save dialog on
/// desktop, the share sheet on Android, a download in browsers.
library;

export 'file_export_native.dart' if (dart.library.js_interop) 'file_export_web.dart';
