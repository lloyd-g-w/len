/// Chooses where loaded strokes' outlines are built
/// (`createOutlinePreparer`): natively on worker isolates; on the web on
/// the UI thread.
library;

export 'outline_preparer_native.dart' if (dart.library.js_interop) 'outline_preparer_web.dart';
