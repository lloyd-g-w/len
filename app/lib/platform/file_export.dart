/// Hands exported files to the user: `saveOrShare` (one file) and
/// `saveOrShareAll` (several, e.g. one PNG per page) open a save dialog on
/// desktop, the share sheet (or with `toDevice` the system's save dialog)
/// on Android and download in browsers (several as one ZIP); `showInFolder` reveals a saved
/// file on desktop. Results are [ExportedFiles] (`file_export_api.dart`).
library;

export 'file_export_api.dart';
export 'file_export_native.dart' if (dart.library.js_interop) 'file_export_web.dart';
