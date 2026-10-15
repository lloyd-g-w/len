/// Decompressing in the browser (`inflateUtf8Text`): the web's
/// `DecompressionStream`, which runs off the UI thread, for the records of
/// a Len file (the archive package inflates in Dart: seconds of the UI
/// thread for a big backup in JavaScript). Natively null: the caller
/// inflates (dart:io's zlib, fast).
library;

export 'browser_inflate_native.dart' if (dart.library.js_interop) 'browser_inflate_web.dart';
