/// Measures what Len stores (`surveyStorage`, Settings → Storage): natively
/// on a worker isolate over its own read-only connection, the database's
/// files measured as such; in browsers on the app's connection.
library;

export 'storage_survey_native.dart' if (dart.library.js_interop) 'storage_survey_web.dart';
